## Base filesystem functions

"""
    pwd(sftp::SFTP.Client) -> String
    pwd(uri::SFTP.URI) -> String

Return the current URI path of the SFTP `Client` or an `URI` struct.
If a `SFTP.Client` is given, `pwd` checks whether the path is valid and throws an
`IOError` otherwise. For `URI` there are no validity checks.
"""
Base.pwd

Base.pwd(uri::URI)::String = isempty(uri.path) ? "/" : string(uri.path)

function Base.pwd(sftp::Client)::String
    if isempty(sftp.uri.path)
        return "/"
    else
        # Check that path is valid or throw an error
        stat(sftp, sftp.uri.path)
        # Return valid path
        return sftp.uri.path
    end
end


"""
    cd(sftp::SFTP.Client, dir::AbstractString)

Change to `dir` in the uri of the `sftp` client.
"""
function Base.cd(sftp::Client, dir::AbstractString)::Nothing
    prev_url = sftp.uri
    try
        # Change server path and save in sftp
        sftp.uri = change_uripath(sftp.uri, dir, trailing_slash=true)
        # Test validity of new path
        isadir = analyse_path(sftp, sftp.uri.path)
        isadir || throw(Base.IOError("$dir is not a directory", -1))
    catch
        # Ensure previous url on error
        sftp.uri = prev_url
        rethrow()
    end
    return
end


"""
    mv(
        sftp::SFTP.Client,
        src::AbstractString,
        dst::AbstractString;
        force::Bool=false
    )

Move `src` to `dst` in the uri of the `sftp` client.
The parent folder `dst` is moved to must exist. The `src` is overwritten without
warning, if `force` is set to `true`.
"""
function Base.mv(
    sftp::Client,
    src::AbstractString,
    dst::AbstractString;
    force::Bool=false
)::Nothing
    # Check if parent folder for dst exists
    stat(sftp, splitdir(sftp, dst)[1].path)
    try
        #* Move file
        # Optional automatic overwrite of src
        force && rm(sftp, dst; recursive=true, force)
        # Move file
        ftp_command(sftp, "rename '$(unescape_joinpath(sftp, src))' '$(unescape_joinpath(sftp, dst))'")
    catch
        # Initial check of src
        uri = joinpath(sftp, src, "")
        root_idx = length(uri.path) + 1
        stats = stat(sftp, uri.path)
        if isdir(stats)
            #* Move folder
            # Setup root folder
            mkpath(sftp, joinpath(sftp, dst).path)
            # Loop over folder contents
            for (path, dirs, files) in walkdir(sftp, uri.path)
                # Sync folders
                mkpath.(sftp, joinpath.(sftp, dst, path[root_idx:end], dirs) .|> pwd)
                # Sync files
                isempty(files) && continue
                old_file = joinpath.(sftp, path, files) .|> pwd
                new_file = joinpath.(sftp, dst, path[root_idx:end], files) .|> pwd
                [ftp_command(sftp,
                    "rename '$(unescape_joinpath(sftp, old_file[i]))' '$(unescape_joinpath(sftp, new_file[i]))'")
                    for i = 1:length(files)
                ]
            end
            # Clean up src
            rm(sftp, src; recursive=true, force=true)
        else
            throw(Base.IOError("cannot move non-existing file", -1))
        end
    end
end


"""
    rm(sftp::Client, path::AbstractString; recursive::Bool=false, force::Bool=false)

Remove (delete) the `path` on the `sftp` client.
Set the `recursive` flag to remove folders recursively.
Suppress errors by setting `force` to `true`.

!!! warning
    Recursive deletions can be very slow for large folders.
"""
function Base.rm(sftp::Client, path::AbstractString; recursive::Bool=false, force::Bool=false)::Nothing
    if recursive
        # Recursively delete the given path
        try
            for (root, dirs, files) in walkdir(sftp, path, topdown=false)
                [ftp_command(sftp, "rm '$(unescape_joinpath(sftp, joinpath(root, file)))'") for file in files]
                [ftp_command(sftp, "rmdir '$(unescape_joinpath(sftp, joinpath(root, dir)))'") for dir in dirs]
            end
            # Delete the main folder (or file)
            r = isdir(stat(sftp, path)) ? "rmdir" : "rm"
            ftp_command(sftp, "$r '$(unescape_joinpath(sftp, path))'")
        catch
            if force
                return
            else
                rethrow()
            end
        end
    else
        # Delete the given file
        try
            ftp_command(sftp, "rm '$(unescape_joinpath(sftp, path))'")
        catch
            # Delete possible empty folder
            try
                content = readdir(sftp, path)
                if isempty(content)
                    ftp_command(sftp, "rmdir '$(unescape_joinpath(sftp, path))'")
                elseif !force
                    throw(Base.IOError("cannot delete non-empty folder without recursive flag", -1))
                end
            catch
                if force
                    return
                else
                    rethrow()
                end
            end
        end
    end
end


"""
    mkdir(sftp::SFTP.Client, dir::AbstractString) -> String

Create a new `dir` on the `sftp` server and return the name of the created directory.
Although a path can be given as `dir`, `dir` can only be created in an existing directory,
i.e. the path up to the basename of `dir` must exist. Otherwise, and in case of already
existing folders, an error is thrown.
"""
function Base.mkdir(sftp::Client, dir::AbstractString)::String
    uripath = joinpath(sftp, dir) |> pwd
    uri, base = splitdir(sftp, uripath)
    isadir = analyse_path(sftp, uri.path)
    if isadir
        stats = statscan(sftp, uri.path)
        if basename(dir) in [s.desc for s in stats]
            throw(Base.IOError("$dir already exists", -2))
        else
            mkpath(sftp, uripath)
        end
    else
        # ¡This should not be reached and covered by error handling of analyse_path!
        throw(Base.IOError("$dir is not a directory", -1))
    end
    return dir
end


"""
    mkpath(sftp::SFTP.Client, path::AbstractString) -> String

Create a `path` on the `sftp` client and return `path` as String on success.
"""
function Base.mkpath(sftp::Client, path::AbstractString)::String
    ftp_command(sftp, "mkdir '$(unescape_joinpath(sftp, path))'")
    return path
end


"""
    readdir(
        sftp::SFTP.Client,
        path::AbstractString = ".";
        join::Bool = false,
        sort::Bool = true,
        check_path::Bool = false
    ) -> Vector{String}

Read the current directory on the `sftp` client and return a vector of strings
with the file names just like Julia's `readdir`.
If `join` is set to `true`, the list of file names include the absolute path.
Sorting of file names can be switched off with the `sort` flag to optimise performance.
Depending on the server settings, readdir may return an empty vector for non-existant paths.
To ensure an error is thrown for non-existant paths, set `check_path` to `true`.

!!! note
    Setting `check_path` to `true` can drastically reduce the performance for
    large existing folders. If you know the folder structure, you should avoid setting this flag.
"""
function Base.readdir(
    sftp::Client,
    path::AbstractString = ".";
    join::Bool = false,
    sort::Bool = true,
    check_path::Bool = false
)::Vector{String}
    # Set path and optionally check validity
    uri = joinpath(sftp.uri, path, "")
    check_path && stat(sftp, uri.path)

    # Reading folder
    io = IOBuffer();
    Downloads.download(string(uri), io; sftp.downloader)

    # Don't know why this is necessary
    res = String(take!(io))
    io = IOBuffer(res)
    files = readlines(io; keep=false)

    # Post-Processing
    filter!(x->x ≠ ".." && x ≠ ".", files)
    sort && sort!(files)
    join && (files = [joinpath(uri, f).path for f in files])

    return files
end

function Base.readdir(sftp::Client, path::AbstractString, __test__::AbstractString)
    isempty(__test__) && return readdir(sftp, path)
    isempty(path) && return readdir(sftp, __test__)
    if isabspath(path)
        path =splitpath(path)[2:end]
        path = isempty(path) ? "" : joinpath(path...)
    end
    readdir(joinpath(__test__, path))
end


"""
    walkdir(
        sftp::SFTP.Client,
        root::AbstractString=".";
        topdown::Bool=true,
        follow_symlinks::Bool=false,
        skip_restricted_access::Bool=true,
        sort::Bool=true
    ) -> Channel{Tuple{String,Vector{String},Vector{String}}}

Return an iterator that walks the directory tree of the given `root` on the `sftp` client.
If the `root` is omitted, the current URI path of the `sftp` client is used.
The iterator returns a tuple containing `(rootpath, dirs, files)`.
The iterator starts at the `root` unless `topdown` is set to `false`.

If `follow_symlinks` is set to `true`, the sources of symlinks are listed rather
than the symlink itself as a file. If `sort` is set to `true`, the files and directories
are listed alphabetically. If a remote folder has restricted access, these directories
are skipped with an info output on the terminal unless `skip_restricted_access` is set
to `false`, in which case an `Downloads.RequestError` is thrown.

# Examples

```julia
sftp = SFTP.Client("sftp://test.rebex.net/pub/example/", "demo", "password")
for (root, dirs, files) in walkdir(sftp, "/")
    println("Directories in \$root")
    for dir in dirs
        println(joinpath(root, dir)) # path to directories
    end
    println("Files in \$root")
    for file in files
        println(joinpath(root, file)) # path to files
    end
end
```
"""
function Base.walkdir(
    sftp::Client,
    root::AbstractString=".";
    topdown::Bool=true,
    follow_symlinks::Bool=false,
    skip_restricted_access::Bool=true,
    sort::Bool=true,
    ignore_hidden::Bool=false,
    hide_identifier::Union{AbstractString,Char}='.'
)::Channel{Tuple{String,Vector{String},Vector{String}}}
    function _walkdir!(chnl, root)::Nothing
        # Init
        dirs = Vector{String}()
        files = Vector{String}()
        # Get complete URI of root
        uri = change_uripath(sftp.uri, root, trailing_slash=true)
        # Get stats on current folder
        scans = try statscan(sftp, uri.path; sort)
        catch err
            if err isa Downloads.RequestError && skip_restricted_access
                @info "skipping $(uri.path) due to restricted access"
                return
            else
                rethrow(err)
            end
        end
        if ignore_hidden
            hidden = findall(startswith(hide_identifier), [s.desc for s in scans])
            deleteat!(scans, hidden)
        end
        # Loop over stats of current folder
        for statstruct in scans
            name = statstruct.desc
            # Handle symbolic links and assign files and folders
            if islink(statstruct)
                symlink_target!(sftp, statstruct, root, dirs, files, follow_symlinks)
            elseif isdir(statstruct)
                push!(dirs, name)
            else
                push!(files, name)
            end
        end
        # Save path objects top-down
        if topdown
            push!(chnl, (uri.path, dirs, files))
        end
        # Scan subdirectories recursively
        for dir in dirs
            _walkdir!(chnl, joinpath(uri, dir) |> pwd)
        end
        # Save path objects bottom-up
        if !topdown
            push!(chnl, (uri.path, dirs, files))
        end
        return
    end

    # Check that root is a folder or link to folder
    isadir = analyse_path(sftp, root)
    if isadir
        return Channel{Tuple{String,Vector{String},Vector{String}}}(chnl -> _walkdir!(chnl, root))
    else
        chnl = Channel{Tuple{String,Vector{String},Vector{String}}}()
        close(chnl)
        return chnl
    end
end


## Path analysis and manipulation functions

"""
    joinpath(sftp::SFTP.Client, path::AbstractString...; kwargs...) -> URI
    joinpath(sftp::URI, path::AbstractString...; kwargs...) -> URI

Join any `path` with the uri of the `sftp` client or the `uri` directly and return
an `URI` with the updated path.

!!! note
    The `uri` field of the `sftp` client remains unaffected by joinpath.
    Use `sftp.uri = joinpath(sftp, "new/path")` to update the URI on the `sftp` client.
"""
function Base.joinpath(::Client) end
# Fix for docs: add Client to function signature for combined docstring and filtering of Base docstring
Base.joinpath(sftp::Client, path::AbstractString...)::URI = joinpath(sftp.uri, path...)
Base.joinpath(uri::URI, path::AbstractString...)::URI = change_uripath(uri, path...)


"""
    joinrootpath(root::AbstractString, parts::AbstractString...) -> String

Join all path `parts` to the `root` path and return as `String`.
The `parts` are joined to the `root` even if the yield an absolute path.

!!! note
    This is an internal version for testing mocked file uploads.
    The `root` is expected to be a tempdir.
"""
function joinrootpath(root::AbstractString, parts::AbstractString...)::String
    path = joinpath(parts...)
    isempty(root) && return path
    if isabspath(path)
        path = splitpath(path)[2:end]
        path = isempty(path) ? "" : joinpath(path...)
    end
    normpath(joinpath(root, path))
end


"""
    splitdir(uri::SFTP.URI, path::AbstractString=".") -> Tuple{URI,String}
    splitdir(sftp::SFTP.Client, path::AbstractString=".") -> Tuple{URI,String}

Join the `path` with the path of the URI in `sftp` (or itself, if only a `URI`
is given) and then split it into the directory name and base name. Return a Tuple
of `URI` with the split path and a `String` with the base name.
"""
Base.splitdir

function Base.splitdir(uri::URI, path::AbstractString=".")::Tuple{URI,String}
    # Join the path with the sftp.uri, ensure no trailing slashes in the path
    # ℹ First enforce trailing slashes with joinpath(..., ""), then remove the slash with path[1:end-1]
    path = joinpath(uri, string(path), "").path[1:end-1]
    # ¡ workaround for URIs joinpath
    startswith(path, "//") && (path = path[2:end])
    # Split directory from base name
    dir, base = splitdir(path)
    # Convert dir to a URI with trailing slash
    joinpath(URI(uri; path=dir), ""), base
end

Base.splitdir(sftp::Client, path::AbstractString=".")::Tuple{URI,String} = splitdir(sftp.uri, path)


"""
    basename(uri::SFTP.URI, path::AbstractString=".") -> String
    basename(sftp::SFTP.Client, path::AbstractString=".") -> String

Get the file name or current folder name of a `path`. The `path` can be absolute
or relative to the `uri` or current directory of the `sftp` server given.
If no `path` is given, the current path from the `uri` or `sftp` server is taken.

!!! note
    In contrast to Julias basename, trailing slashes in paths are ignored and the last
    non-empty part is returned, except for the root, where the `basename` is empty.
"""
Base.basename
Base.basename(uri::URI, path::AbstractString=".")::String = splitdir(uri, path)[2]
Base.basename(sftp::Client, path::AbstractString=".") = splitdir(sftp.uri, path)[2]


## Helper functions for filesystem operations

"""
    symlink_target!(
        sftp::SFTP.Client,
        stats::SFTP.StatStruct,
        root::AbstractString,
        dirs::Vector{String},
        files::Vector{String},
        follow_symlinks::Bool
    )

Analyse the symbolic link on the `sftp` server from its `stats` and add it to the respective `dirs`
or `files` list. The `root` path is needed to get updated stats of the symlink.
Save the source of the symlink, if `follow_symlinks` is set to `true`, otherwise save symlinks as
files.
"""
function symlink_target!(
    sftp::Client,
    stats::StatStruct,
    root::AbstractString,
    dirs::Vector{String},
    files::Vector{String},
    follow_symlinks::Bool,
)::Nothing
    # Add link to files and return, if not following symlinks
    if !follow_symlinks
        push!(files, stats.desc)
        return
    end
    # Get stats of link target
    target = try
        target = split(stats.root, "->")[2] |> strip |> string
        joinpath(sftp.uri.path, root, target)
    catch
        throw(ArgumentError("the link root of the StatsStruct has the wrong format"))
    end
    # Add link target to iterator
    scan = stat(sftp, target)
    try
        if isdir(scan)
            push!(dirs, stats.desc)
        elseif islink(scan)
            symlink_target!(sftp, scan, root, dirs, files, follow_symlinks)
        else
            push!(files, stats.desc)
        end
    catch
        @warn "could not identify mode of $target; added as file"
        push!(files, stats.desc)
    end
    return
end


"""
    analyse_path(sftp::SFTP.Client, root::AbstractString) -> Bool

Return, whether the `root` on the `sftp` server is a directory or a link pointing
to a directory and the path of the directory.
"""
function analyse_path(sftp::Client, root::AbstractString)::Bool
    # Return, if not a link
    stats = stat(sftp, root)
    islink(stats) || return isdir(stats)
    # Check link target
    files, dirs = Vector{String}(), Vector{String}()
    symlink_target!(sftp, stats, root, dirs, files, true)
    # Return, if link is a folder and the path
    if length(dirs) == 1
        true
    elseif length(files) == 1
        false
    else
        Base.IOError("unknown link target", -2)
    end
end


"""
    unescape_joinpath(sftp::SFTP.Client, path::AbstractString) -> String

Join the `path` with the URI path in `sftp` and return the unescaped path.
Note, this function should not use URL:s since CURL:s api need spaces
"""
unescape_joinpath(sftp::Client, path::AbstractString)::String =
    change_uripath(sftp.uri, path).path |> URIs.unescapeuri


"""
    ftp_command(sftp::SFTP.Client, command::String)

Execute the `command` on the `sftp` server.
"""
function ftp_command(sftp::Client, command::String)::Nothing
    # Set up the command
    slist = Ptr{Cvoid}(0)
    slist = LibCURL.curl_slist_append(slist, command)
    # ¡Not sure why the unused info param is needed, but otherwise walkdir will not work!
    sftp.downloader.easy_hook = (easy::Easy, info) -> begin
        set_stdopt(sftp, easy)
        Downloads.Curl.setopt(easy,  Downloads.Curl.CURLOPT_QUOTE, slist)
    end
    # Execute the
    uri = string(sftp.uri)
    io = IOBuffer()
    output = ""
    try
        output = Downloads.download(uri, io; sftp.downloader)
    finally
        LibCURL.curl_slist_free_all(slist)
        reset_easy_hook(sftp)
    end
    return
end
