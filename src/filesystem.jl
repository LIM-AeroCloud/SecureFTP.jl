## Server exchange functions

"""
    upload(
        sftp::SFTP.Client,
        file::AbstractString;
        remote_dir::AbstractString=".",
        local_dir::AbstractString="."
    ) -> Nothing

Upload (put) a `file` on the server. If file includes a path, this is where it is put
on the server. The path may be relative to the current uri path of the `sftp` server
or absolute. On the local system, a `path` may be specified as last argument.

# Examples

```julia
sftp = SFTP.Client("sftp://test.rebex.net", "demo", "password")

upload(sftp, "test.csv", "/tmp")

files=readdir()
upload.(sftp, files)
```
"""
function upload(
    sftp::Client,
    file::AbstractString,
    path::AbstractString="."
)::Nothing
    # Open local file
    file = normpath(path, basename(file))
    open(file, "r") do local_file
        # Define remote file
        remote_file = change_uripath(sftp.uri, file, isfile=isfile(file)).path
        @debug "file upload local > remote" local_file, remote_file
        uri = change_uripath(sftp.uri, remote_file)
        # Upload to server
        Downloads.request(string(uri), input=local_file; downloader=sftp.downloader)
    end
    return
end


"""
    download(
        sftp::SFTP.Client,
        filename::AbstractString,
        output::String = ""
    ) -> String

Download a file from the `sftp` server. The specified `filename` may include a path
on the remote server, which is ignored on the local system.

The file can be downloaded and saved directly to a variable or it can be saved to
a file in the `output` directory.

# Example

```julia
sftp = SFTP.Client("sftp://test.rebex.net/pub/example/", "demo", "password")
files=readdir(sftp)
download_dir="/tmp"
download.(sftp, files, download_dir)
````

You can also use it like this:
```julia
df=DataFrame(CSV.File(download(sftp, "/mydir/test.csv")))
```
"""
function Base.download(
    sftp::Client,
    filename::AbstractString,
    output::String = ""
)::String
    # Define output
    output = isempty(output) ? tempname() : normpath(output, basename(filename))
    # Error handling for existing folders/files
    if isdir(output)
        @error "the specified download file is a directory and cannot be overwritten"
        return output
    elseif isfile(output)
        @warn "$output already exists; overwrite (y/n)?"
        confirm = readline()
        while true
            if startswith(lowercase(confirm), "y")
                break
            elseif startswith(lowercase(confirm), "n")
                return output
            end
        end
    end

    # Download file
    uri = change_uripath(sftp.uri, filename, isfile=true)
    Downloads.download(string(uri), output; sftp.downloader)
    return output
end


## stat functions

"""
    statscan(
        sftp::SFTP.Client,
        path::AbstractString=".";
        sort::Bool=true,
        show_cwd_and_parent::Bool=false
    ) -> Vector{SFTP.StatStruct}

Like `stat`, but returns a Vector of `SFTP.StatStruct` with filesystem stats
for all objects in the given `path`.

** This should be preferred over `stat` for performance reasons. **

Note that you can only run this on directories.

By default, the `SFTP.StatStruct` vector is sorted by the descriptions (`desc` fields).
For large folder contents, `sort` can be set to `false` to increase performance, if the
output order is irrelevant.
If `show_cwd_and_parent` is set to `true`, the `SFTP.StatStruct` vector includes entries for
`"."` and `".."` on position 1 and 2, respectively.
"""
function statscan(
    sftp::Client,
    path::AbstractString=".";
    sort::Bool=true,
    show_cwd_and_parent::Bool=false
)::Vector{StatStruct}
    # Easy hook to get stats on files
    sftp.downloader.easy_hook = (easy::Easy, info) -> begin
        set_stdopt(sftp, easy)
    end

    # Get server stats for given path
    url = change_uripath(sftp.uri, path)
    io = IOBuffer();
    try
         Downloads.download(string(url), io; sftp.downloader)
    finally
        reset_easy_hook(sftp)
    end
    # Don't know why this is necessary
    res = String(take!(io))
    io = IOBuffer(res)
    stats = readlines(io; keep=false)

    # Instantiate stat structs
    stats = StatStruct.(stats)
    # Filter current and parent directory and sort by description
    if !show_cwd_and_parent
        filter!(s -> s.desc ≠ "." && s.desc ≠ "..", stats)
    end
    sort && sort!(stats)
    return stats
end


"""
    stat(sftp::SFTP.Client, path::AbstractString=".") -> SFTP.StatStruct

Return the stat data for `path` on the `sftp` server.

Note: This returns only stat data for one object, but stat data for all objects in
the same folder is obtained internally. If you need stat data for more than object
in the same folder, use `statscan` for better performance and reduced connections
to the server.
"""
function Base.stat(sftp::Client, path::AbstractString=".")::StatStruct
    # Split path in basename and remaining path
    uri, base = splitdir(sftp, path)
    # Get stats of all path objects in the containing folder of base
    stats = statscan(sftp, uri.path, show_cwd_and_parent=true)
    # Special case for root
    uri.path == "/" && isempty(base) && return stats[1]
    # Find and return the stats of base
    i = findbase(stats, base, path)
    return stats[i]
end


## Base function overloads for comparision and sorting of SFTPStatStructs

"""
    isequal(a::SFTP.StatStruct, b::SFTP.StatStruct) -> Bool

Comares equality between the description (`desc` fields) of two `SFTP.StatStruct` objects
and returns `true` for equality, otherwise `false`.
"""
Base.isequal(a::StatStruct, b::StatStruct)::Bool =
    isequal(a.desc, b.desc) && isequal(a.size, b.size) && isequal(a.mtime, b.mtime)


"""
    isless(a::SFTP.StatStruct, b::SFTP.StatStruct) -> Bool

Comares the descriptions (`desc` fields) of two `SFTP.StatStruct` objects
and returns `true`, if `a` is lower than `b`, otherwise `false`.
"""
Base.isless(a::StatStruct, b::StatStruct)::Bool = a.desc < b.desc


## Helper functions for path stats

"""
    parse_date(month::AbstractString, day::AbstractString, year_or_time::AbstractString) -> Float64

From the abbreviated `month` name, the `day` and the `year_or_time` all given as `String`,
return a unix timestamp.
"""
function parse_date(month::AbstractString, day::AbstractString, year_or_time::AbstractString)::Float64
    # Process date parts
    yearStr::String = occursin(":", year_or_time) ? string(Dates.year(Dates.today())) : year_or_time
    timeStr::String = occursin(":", year_or_time) ? year_or_time : "00:00"
    # Assemble datetime string
    datetime = Dates.DateTime("$month $day $yearStr $timeStr", Dates.dateformat"u d yyyy H:M ")
    # Return unix timestamp
    return Dates.datetime2unix(datetime)
end


"""
    parse_mode(s::AbstractString) -> UInt

From the `AbstractString` `s`, parse the file mode octal number and return as `UInt`.
"""
function parse_mode(s::AbstractString)::UInt
    # Error handling
    if length(s) != 10
        throw(ArgumentError("`s` should be an `AbstractString` of length `10`"))
    end
    # Determine file system object type (dir or file)
    dir_char = s[1]
    dir = if dir_char == 'd'
        0x4000
    elseif dir_char == 'l'
        0xa000
    else
        0x8000
    end
    @debug "mode" dir_char

    # Determine owner
    owner = str2number(s[2:4])
    group = str2number(s[5:7])
    anyone = str2number(s[8:10])

    # Return mode as UInt
    return dir + owner * 8^2 + group * 8^1 + anyone * 8^0
end


"""
    str2number(s::AbstractString) -> Int64

Parse the file owner symbols in the string `s` to the corresponding ownership number.
"""
function str2number(s::AbstractString)::Int64
    b1 = (s[1] != '-') ?  4 : 0
    b2 = (s[2] != '-') ?  2 : 0
    b3 = (s[3] != '-') ?  1 : 0
    return b1+b2+b3
end


## Path object checks

"""
    Base.isdir(st::SFTP.StatStruct) -> UInt

Return the filemode in the `SFTP.StatStruct`.
"""
Base.filemode(st::StatStruct)::UInt = st.mode


"""
    islink(st::SFTP.StatStruct) -> Bool

Analyse the `SFTP.StatStruct` and return `true` for a symbolic link, `false` otherwise.
"""
Base.islink(st::StatStruct)::Bool = filemode(st) & 0xf000 == 0xa000


"""
    isdir(st::SFTP.StatStruct) -> Bool

Analyse the `SFTP.StatStruct` and return `true` for a directory, `false` otherwise.
"""
Base.isdir(st::StatStruct)::Bool = filemode(st) & 0xf000 == 0x4000


"""
    isfile(st::SFTP.StatStruct) -> Bool

Analyse the `SFTP.StatStruct` and return `true` for a file, `false` otherwise.
"""
Base.isfile(st::StatStruct)::Bool = filemode(st) & 0xf000 == 0x8000


## Base filesystem functions

"""
    pwd(sftp::SFTP.Client) -> String

Return the current URI path of the SFTP client.
"""
Base.pwd(sftp::Client)::String = isempty(sftp.uri.path) ? "/" : sftp.uri.path


"""
    cd(sftp::SFTP.Client, dir::AbstractString)

Change to `dir` in the uri of the `sftp` client.
"""
function Base.cd(sftp::Client, dir::AbstractString)::Nothing
    prev_url = sftp.uri
    try
        # Change server path and save in sftp
        sftp.uri = change_uripath(sftp.uri, dir)
        # Test validity of new path
        readdir(sftp)
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
        old_name::AbstractString,
        new_name::AbstractString;
    )

Move, i.e. rename, the file from `old_name` to `new_name` in the uri of the `sftp` client.
"""
function Base.mv(
    sftp::Client,
    old_name::AbstractString,
    new_name::AbstractString;
)::Nothing
    ftp_command(sftp, "rename '$(unescape_joinpath(sftp, old_name))' '$(unescape_joinpath(sftp, new_name))'")
end


"""
    rm(sftp::SFTP.Client, file::AbstractString)

Remove (delete) the `file` in the uri of the `sftp` client.
"""
function Base.rm(sftp::Client, file::AbstractString; recursive::Bool=true)::Nothing
    r = recursive ? "-r " : ""
    ftp_command(sftp, "rm $r'$(unescape_joinpath(sftp, file))'")
end


"""
    rmdir(sftp::SFTP.Client, dir::AbstractString)

Remove (delete) the directory `dir` in the uri of the `sftp` client.
"""
function rmdir(sftp::Client, dir::AbstractString)::Nothing
    Base.depwarn("rmdir(sftp, dir) is deprecated. Use rm(sftp, dir; recursive=true) instead.", :rmdir)
    ftp_command(sftp, "rmdir '$(unescape_joinpath(sftp, dir))'")
end


"""
    mkdir(sftp::SFTP.Client, dir::AbstractString)

Create a directory `dir` in the uri of the `sftp` client.
"""
function Base.mkdir(sftp::Client, dir::AbstractString)::Nothing
    ftp_command(sftp, "mkdir '$(unescape_joinpath(sftp, dir))'")
end


"""
    walkdir(
        sftp::SFTP.Client,
        root::AbstractString=".";
        topdown::Bool=true,
        follow_symlinks::Bool=false,
        sort::Bool=true
    ) -> Channel{Tuple{String,Vector{String},Vector{String}}}

Return an iterator that walks the directory tree of the given `root` of the `sftp` client.
If the `root` is ommitted, the current URI path of the `sftp` client is used.
The iterator returns a tuple containing `(rootpath, dirs, files)`.
The iterator starts at the `root` unless `topdown` is set to `false`.
If `follow_symlinks` is set to `true`, the sources of symlinks are listed rather
than the symlink itself as file. If `sort` is set to `true`, the files and directories
are listed alphabetically.

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
    sort::Bool=true
)::Channel{Tuple{String,Vector{String},Vector{String}}}
    function _walkdir(chnl, root)::Nothing
        # Init
        uri = change_uripath(sftp.uri, root)
        pathobjects = (;
            dirs = Vector{String}(),
            files = Vector{String}(),
            scans = Dict{String,Any}()
        )
        # Get stats on current folder
        scans = statscan(sftp, uri.path; sort)
        # Loop over stats of current folder
        for statstruct in scans
            name = statstruct.desc
            # Handle symbolic links and assign files and folders
            if islink(statstruct)
                symlink_source!(sftp, name, pathobjects, follow_symlinks)
            elseif isdir(statstruct)
                push!(pathobjects.dirs, name)
            elseif isfile(statstruct)
                push!(pathobjects.files, name)
            else
                @warn "skipping path object of unknown mode" name
            end
        end
        # Save path objects top-down
        if topdown
            push!(chnl, (uri.path, pathobjects.dirs, pathobjects.files))
        end
        # Scan subdirectories recursively
        for dir in pathobjects.dirs
            _walkdir(chnl, joinpath(uri, dir).path)
        end
        # Save path objects bottom-up
        if !topdown
            push!(chnl, (uri.path, pathobjects.dirs, pathobjects.files))
        end
        return
    end
    return Channel{Tuple{String,Vector{String},Vector{String}}}(chnl -> _walkdir(chnl, root))
end


"""
    readdir(sftp::SFTP.Client, join::Bool = false, sort::Bool = true)

Reads the current directory. Returns a vector of Strings just like the regular readdir function.
"""
function Base.readdir(
    sftp::Client,
    path::AbstractString=".";
    join::Bool = false,
    sort::Bool = true
)::Vector{String}
    uri = joinpath(sftp.uri, path, "")

    io = IOBuffer();
    Downloads.download(string(uri), io; sftp.downloader)

    # Don't know why this is necessary
    res = String(take!(io))
    io = IOBuffer(res)
    files = readlines(io; keep=false)

    filter!(x->x ≠ ".." && x ≠ ".", files)

    sort && sort!(files)
    join && (files = [joinpath(uri, f).path for f in files])

    return files
end


"""
    splitdir(sftp::SFTP.Client, path::AbstractString=".") -> Tuple{URI,String}

Join the `path` with the path of the URI in `sftp` and then split it into the
directory name and base name. Return a Tuple of `URI` with the split path and
a `String` with the base name.
"""
function Base.splitdir(sftp::Client, path::AbstractString=".")::Tuple{URI,String}
    # Join the path with the sftp.uri, ensure no trailing slashes in the path
    # ℹ First enforce trailing slashes with joinpath(..., ""), then remove the slash with path[1:end-1]
    path = joinpath(sftp.uri, string(path), "").path[1:end-1]
    # ¡ workaround for URIs joinpath
    startswith(path, "//") && (path = path[2:end])
    # Split directory from base name
    dir, base = splitdir(path)
    # Convert dir to a URI with trailing slash
    joinpath(URI(sftp.uri; path=dir), ""), base
end


## Helper functions for filesystem operations

"""
    symlink_source!(
        sftp::SFTP.Client,
        link::AbstractString,
        pathobjects::@NamedTuple{dirs::Vector{String},files::Vector{String},scans::Dict{String,Any}},
        follow_symlinks::Bool
    ) -> Nothing

Analyse the symbolic `link` on the `sftp` server and add it to the respective `pathobjects` list.
Save the source of the symlink, if `follow_symlinks` is set to `true`, otherwise save symlinks as files.
"""
function symlink_source!(
    sftp::Client,
    link::AbstractString,
    pathobjects::@NamedTuple{dirs::Vector{String},files::Vector{String},scans::Dict{String,Any}},
    follow_symlinks::Bool
)::Nothing
    # Split file name and link source
    linkparts = split(link, "->") .|> strip

    # Get file name and source path of symlink
    file, source = linkparts
    uri, base = splitdir(sftp, source)
    # Check correct link format
    if isempty(linkparts)
        return linkerror(link)
    elseif length(linkparts) ≠ 2
        push!(pathobjects.files, file)
        return linkerror(link)
    # Add link to files and return, if not following symlinks
    elseif !follow_symlinks
        push!(pathobjects.files, file)
        return
    end
    if uri.path ∉ keys(pathobjects.scans)
        # Get stats for containing source folder
        linkscans = statscan(sftp, uri.path)
        pathobjects.scans[uri.path] = Dict(getfield.(linkscans, :desc) .=> linkscans)
    end
    # Add link source to pathobjects
    try
        isdir(pathobjects.scans[uri.path][base]) ?
            push!(pathobjects.dirs, file) : push!(pathobjects.files, file)
    catch
        push!(pathobjects.files, file)
    end
    return
end


"""
    unescape_joinpath(sftp::SFTP.Client, path::AbstractString) -> String

Join the `path` with the URI path  in `sftp` and return the unescaped path.
Note, this function should not use URL:s since CURL:s api need spaces
"""
unescape_joinpath(sftp::Client, path::AbstractString)::String =
    URIs.resolvereference(sftp.uri, path).path |> URIs.unescapeuri


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
