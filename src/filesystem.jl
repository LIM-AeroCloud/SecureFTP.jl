## Server exchange functions

"""
    upload(
        sftp::Client,
        src::AbstractString=".",
        dst::AbstractString=".";
        merge::Bool=false,
        force::Bool=false,
        ignore_hidden::Bool=false,
        hide_identifier::Union{Char,AbstractString}='.'
    ) -> String

Upload (put) `src` to `dst` on the server; `src` can be a file or folder.
Folders are uploaded recursively. `dst` must be an existing folder on the server,
otherwise an `IOError` is thrown. `src` may include an absolute or relative path
on the local system, which is ignored on the server. `dst` can be an absolute path
or a path relative to the current uri path of the `sftp` server. The function returns
`dst` as String.

If `merge` is set to `true`, the content of `src` is merged into any existing `dst`
folder. If `force` is set to `true`, any existing path at `dst` on the `sftp` server is
overwritten without warning. If both flags are set, `upload` first tries to mere folders
and only overwrites files. If `ignore_hidden` is set to `true`, hidden files
are omitted in the upload. The start sequence of `String` or `Char`, with which
a hidden file starts, can be specified by the `hide_identifier`.
By default it is assumed that hidden files start with a dot (`.`).


# Examples

```julia
sftp = SFTP.Client("sftp://test.rebex.net", "demo", "password")

upload(sftp, "data/test.csv", "/tmp") # upload data/test.csv to /tmp/test.csv

files=readdir()
upload.(sftp, files) # all files of the current directory are uploaded to the current directory on the server

upload(sftp, ignore_hidden=true) # the current folder is uploaded to the server without hidden objects
```
"""
function upload(
    sftp::Client,
    src::AbstractString=".",
    dst::AbstractString=".";
    merge::Bool=false,
    force::Union{Nothing,Bool}=nothing,
    ignore_hidden::Bool=false,
    hide_identifier::Union{Char,AbstractString}='.'
)::String
    #* Check remote and local path
    src = realpath(src)
    dst = joinpath(sftp, dst, "").path
    isdir(sftp, dst) || throw(Base.IOError("$dst must be a directory", 1))
    #* Upload src to dst
    if isdir(src)
        #* Upload folder content recursively
        # Handle hidden src
        path, base = splitdir(src)
        hidden_dir = joinpath(path, string(hide_identifier))
        ignore_hidden && startswith(src, hidden_dir) && return dst
        # Create base folder
        root_idx = length(path) + 2 # ℹ +2 for index after the omitted trailing slash
        isempty(base) || mkpath(sftp, joinpath(sftp, dst, base).path)
        for (root, dirs, files) in walkdir(src)
            # Ignore hidden folders and their content
            if ignore_hidden
                startswith.(root, hidden_dir) ? continue : (hidden_dir = joinpath(root, string(hide_identifier)))
            end
            # Handle conflicts
            cwd = joinpath(sftp, dst, root[root_idx:end]).path
            conflicts = readdir(sftp, cwd)
            # Sync folders
            mkfolder(sftp, cwd, dirs, intersect(dirs, conflicts), merge, force, ignore_hidden, hide_identifier)
            # Sync files
            upload_file(sftp, root, cwd, files, intersect(files, conflicts), force, ignore_hidden, hide_identifier)
        end
    else
        # Upload file
        upload_file(sftp, src, dst, force, ignore_hidden, hide_identifier)
    end
    return dst
end


"""
    download(
        sftp::Client,
        src::AbstractString = ".",
        dst::String = "";
        merge::Bool = false,
        force::Bool = false,
        ignore_hidden::Bool = false,
        hide_identifier::Union{Char,AbstractString} = '.'
    ) -> String

Download `src` from the `sftp` server to `dst` on the local system; `src` can be a file or folder.
Folders are downloaded recursively. `dst` must be an existing folder on the local system,
otherwise an `IOError` is thrown. `src` may include an absolute or relative path
on the `sftp` server, which is ignored on the local system. `dst` can be an absolute
or relative path on the local system. The function returns `dst` as String.

Alternatively, `dst` can be omitted for files on the `sftp` server. In this case,
the file content is directly saved to a variable, see example below. This option does
not work for folders.

If `merge` is set to `true`, the content of `src` is merged into any existing `dst`
folder. If `force` is set to `true`, any existing path at `dst` is overwritten without warning.
If both flags are set, `download` first tries to mere folders and only overwrites files.
If `ignore_hidden` is set to `true`, hidden files are omitted in the download. The start sequence
of `String` or `Char`, with which a hidden file starts, can be specified by the `hide_identifier`.
By default it is assumed that hidden files start with a dot (`.`).

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
    src::AbstractString = ".",
    dst::String = "";
    merge::Bool = false,
    force::Union{Nothing,Bool} = nothing,
    ignore_hidden::Bool = false,
    hide_identifier::Union{Char,AbstractString} = '.'
)::String
    #* Check remote and local path
    base = splitdir(sftp, src)[2]
    dst = if isempty(dst)
        isfile(sftp, src) || throw(Base.IOError("$src must be a file", -9))
        # Download file from server
        out = tempname()
        Downloads.download(string(joinpath(sftp, src, trailing_slash = false)),
            out; sftp.downloader)
        return out
    else
        isdir(dst) || throw(Base.IOError("$dst must be an existing directory", 1))
        realpath(dst)
    end
    # Optional check, if src is hidden
    ignore_hidden && startswith(basename(src), hide_identifier) && return dst
    #* Download src to dst
    if isdir(sftp, src)
        # Create base folder
        src = joinpath(sftp, src, "").path
        root_idx = length(src) + 1
        isempty(base) || mkpath(dst) # ℹ sync folder, don't create folder for root
        # Download folder content recursively
        for (root, dirs, files) in walkdir(sftp, src; ignore_hidden, hide_identifier)
            # Sync folder structure
            cwd = normpath(dst, root[root_idx:end])
            conflicts = readdir(cwd)
            mkfolder(cwd, dirs, intersect(dirs, conflicts), merge, force)
            # Download files
            download_file(sftp, joinpath.(sftp, root, trailing_slash = true), cwd,
                files, intersect(files, conflicts), force)
        end
    else
        # Download file
        download_file(sftp, src, dst, force)
    end
    return dst
end


## Helper functions for server exchange

"""
    mkfolder(
        [sftp::Client,]
        path::AbstractString,
        dirs::Vector{<:AbstractString},
        conflicts::Vector{<:AbstractString},
        merge::Bool,
        force::Union{Nothing, Bool},
        [ignore_hidden::Bool,
        hide_identifier::Union{AbstractString,Char}]
    )

Create the given `path` either on the `sftp` server or the local system, depending on
whether the `sftp` client was passed as first argument. Ignore hidden folders starting with
the `hide_identifier`, if `ignore_hidden` is `true`. For the local system, hidden folders
are filtered by walkdir in the download function.

Only non-existing `dirs` from the source system are created on the destination.
Existing path `conflicts` on the destination system are handled according to the
flag settings of `merge` and `force`.
Only throw an error for existing path `conflicts`, if `merge` is set to `false` and
`force` is set to `nothing`. Delete `conflicts`, if `force` is `true` and `merge` is `false`,
and ignore `conflicts`, if `force` is `false` or `merge` is `true`.
"""
function mkfolder end

function mkfolder(
    sftp::Client,
    path::AbstractString,
    dirs::Vector{<:AbstractString},
    conflicts::Vector{<:AbstractString},
    merge::Bool,
    force::Union{Nothing, Bool},
    ignore_hidden::Bool,
    hide_identifier::Union{AbstractString,Char}
)::Nothing
    # Handle conflicts and hidden folders
    # ¡Avoid in-place replacements with setdiff! and filter! to leave dir unchanged outside mkfolder!
    ignore_hidden && (dirs = filter(!startswith(hide_identifier), dirs))
    if merge || isfalse(force)
        dirs = setdiff(dirs, conflicts)
    elseif istrue(force)
        rm.(sftp, joinpath.(sftp, path, conflicts) .|> pwd, recursive = true, force = true)
    end
    # Create missing folders
    mkdir.(sftp, joinpath.(sftp, path, dirs) .|> pwd)
    return
end

function mkfolder(
    path::AbstractString,
    dirs::Vector{<:AbstractString},
    conflicts::Vector{<:AbstractString},
    merge::Bool,
    force::Union{Nothing, Bool}
)::Nothing
    # Handle conflicts
    if merge || isfalse(force)
        dirs = setdiff(dirs, conflicts)
    elseif istrue(force)
        rm.(joinpath.(path, conflicts), recursive = true, force = true)
    end
    # Create missing folders
    mkdir.(joinpath.(path, dirs))
    return
end

"""
    upload_file(
        sftp::Client,
        src::AbstractString,
        dst::AbstractString,
        [files::Vector{<:AbstractString},
        conflicts::Vector{<:AbstractString},]
        force::Union{Nothing,Bool},
        ignore_hidden::Bool,
        hide_identifier::Union{AbstractString,Char}
    )

Upload `src` to the `dst` path on the `sftp` client.
If `files` and `conflicts` are given, all `files` within the `src` folder are uploaded
to the `dst` folder and `conflicts` are handled according to the `force` flag. Otherwise.
`src` must be an existing file that is uploaded to the `dst` folder.

If `force` is nothing, an error is thrown for existing files on `dst`, if `force` is `true`,
existing files are overwritten, and if `force` is `false`, upload is skipped for existing
files. Hidden files starting with the `hide_identifier` are ignored, if `ignore_hidden` is
set to `true`.
"""
function upload_file end

function upload_file(
    sftp::Client,
    src::AbstractString,
    dst::AbstractString,
    files::Vector{<:AbstractString},
    conflicts::Vector{<:AbstractString},
    force::Union{Nothing,Bool},
    ignore_hidden::Bool,
    hide_identifier::Union{AbstractString,Char}
)::Nothing
    #* Handle conflicts and hidden files
    ignore_hidden && filter!(!startswith(hide_identifier), files)
    if isnothing(force)
        !isempty(conflicts) && throw(Base.IOError("cannot overwrite existing path(s) \
            $(join(joinpath.(sftp, dst, files) .|> pwd, ", ", " and "))", -1))
    elseif istrue(force)
        rm.(sftp, joinpath.(sftp, dst, conflicts) .|> pwd,
            recursive = true, force = true)
    else
        files = setdiff(files, conflicts)
    end
    #* Loop over files
    for file in files
        # Open local file and upload to server
        open(joinpath(src, file), "r") do f
            Downloads.request(string(joinpath(sftp, dst, file)), input=f; downloader=sftp.downloader)
        end
    end
    return
end

function upload_file(
    sftp::Client,
    src::AbstractString,
    dst::AbstractString,
    force::Union{Nothing,Bool},
    ignore_hidden::Bool,
    hide_identifier::Union{AbstractString,Char}
)::Nothing
    # Prepare source file and conflicts
    if !isfile(src)
        @error "src in upload_file must be an existing file or files must be passed as vector"
        return
    end
    path, file = splitdir(src)
    conflicts = readdir(sftp, dst)
    conflicts = filter(isequal(file), conflicts)
    # Call general upload_file method
    upload_file(sftp, path, dst, [file], conflicts, force, ignore_hidden, hide_identifier)
end


"""
    download_file(
        sftp::Client,
        src::URI,
        dst::AbstractString,
        [files::Vector{<:AbstractString},
        conflicts::Vector{<:AbstractString},]
        force::Union{Nothing,Bool}
    )

Download `src` from the `sftp` server to `dst` on the local system; `src` can either
be a file or a path to a folder on the `sftp` server. In the latter case, `files` must
be defined as a vector of strings and potential `conflicts` on the server given as
additional vector of strings. The `force` flag determines, whether existing files are
overwritten (`true`), skipped (`false`) or throw an error (`nothing`).
"""
function download_file end

function download_file(
    sftp::Client,
    src::URI,
    dst::AbstractString,
    files::Vector{<:AbstractString},
    conflicts::Vector{<:AbstractString},
    force::Union{Nothing,Bool}
)::Nothing
    #* Prepare local and remote files
    if isnothing(force)
        !isempty(conflicts) && throw(Base.IOError("cannot overwrite existing path(s) \
            $(join(joinpath.(dst, files), ", ", " and "))", -1))
    elseif istrue(force)
        rm.(joinpath.(dst, conflicts), recursive = true, force = true)
    else
        files = setdiff(files, conflicts)
    end
    #* Loop over files
    for file in files
        # Download file from server
        Downloads.download(string(joinpath(src, file, trailing_slash = false)),
            joinpath(dst, file); sftp.downloader)
    end
    return
end

function download_file(
    sftp::Client,
    src::AbstractString,
    dst::AbstractString,
    force::Union{Nothing,Bool}
)::Nothing
    # Prepare source file and conflicts
    uri, file = splitdir(sftp, src)
    conflicts = readdir(dst)
    conflicts = filter(isequal(file), conflicts)
    # Call general upload_file method
    download_file(sftp, uri, dst, [file], conflicts, force)
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

!!! note
    You can only run this on directories.

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
    url = change_uripath(sftp.uri, path, trailing_slash=true)
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
    stats = StatStruct.(stats, url.path)
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

!!! note
    This returns only stat data for one object, but stat data for all objects in
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

Compares equality between the description (`desc` fields) of two `SFTP.StatStruct` objects
and returns `true` for equality, otherwise `false`.
"""
Base.isequal(a::StatStruct, b::StatStruct)::Bool =
    isequal(a.desc, b.desc) && isequal(a.size, b.size) && isequal(a.mtime, b.mtime)


"""
    isless(a::SFTP.StatStruct, b::SFTP.StatStruct) -> Bool

Compares the descriptions (`desc` fields) of two `SFTP.StatStruct` objects
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

const PERFORMANCE_NOTICE = """
A convenience method exists to directly check the `path` on the `sftp` server.
However, if several path objects in the same folder are analysed, it is much more
performant to use `statscan` once and then analyse each `SFTP.StatStruct`.
"""

"""
    filemode(sftp::SFTP.Client, path::AbstractString = ".") -> UInt
    filemode(st::SFTP.StatStruct) -> UInt

Return the filemode of the `SFTP.StatStruct`. $PERFORMANCE_NOTICE
"""
Base.filemode
Base.filemode(st::StatStruct)::UInt = st.mode
Base.filemode(sftp::Client, path::AbstractString = ".")::UInt = stat(sftp, path).mode


"""
    ispath(sftp::Client, path::AbstractString = ".") -> Bool

Return `true`, if a `path` exists on the `sftp` server, i.e. is a file, folder or link.
Otherwise, reture `false`.
"""
Base.ispath(sftp::Client, path::AbstractString = ".")::Bool = try
  stat(sftp, path)
  true
catch
  false
end


"""
    isdir(sftp::SFTP.Client, path::AbstractString = ".") -> Bool
    isdir(st::SFTP.StatStruct) -> Bool

Analyse the `SFTP.StatStruct` and return `true` for a directory, `false` otherwise.
$PERFORMANCE_NOTICE
"""
Base.isdir
Base.isdir(st::StatStruct)::Bool = filemode(st) & 0xf000 == 0x4000
Base.isdir(sftp::Client, path::AbstractString = ".")::Bool = filemode(sftp, path) & 0xf000 == 0x4000


"""
    isfile(sftp::SFTP.Client, path::AbstractString = ".") -> Bool
    isfile(st::SFTP.StatStruct) -> Bool

Analyse the `SFTP.StatStruct` and return `true` for a file, `false` otherwise.
$PERFORMANCE_NOTICE
"""
Base.isfile
Base.isfile(st::StatStruct)::Bool = filemode(st) & 0xf000 == 0x8000
Base.isfile(sftp::Client, path::AbstractString = ".")::Bool = filemode(sftp, path) & 0xf000 == 0x8000


"""
    islink(sftp::SFTP.Client, path::AbstractString = ".") -> Bool
    islink(st::SFTP.StatStruct) -> Bool

Analyse the `SFTP.StatStruct` and return `true` for a symbolic link, `false` otherwise.
$PERFORMANCE_NOTICE
"""
Base.islink
Base.islink(st::StatStruct)::Bool = filemode(st) & 0xf000 == 0xa000
Base.islink(sftp::Client, path::AbstractString = ".")::Bool = filemode(sftp, path) & 0xf000 == 0xa000


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

# kwargs

- `trailing_slash::Bool=false`: Add a trailing slash to the path when `true` or for directories
  when `nothing`. Omit when `false` or otherwise.
"""
Base.joinpath
Base.joinpath(sftp::Client, path::AbstractString...; kwargs...)::URI = joinpath(sftp.uri, path...; kwargs...)
Base.joinpath(uri::URI, path::AbstractString...; kwargs...)::URI = change_uripath(uri, path...; kwargs...)


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
    path = (pwd∘joinpath)(uri, string(path), "")[1:end-1]
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
