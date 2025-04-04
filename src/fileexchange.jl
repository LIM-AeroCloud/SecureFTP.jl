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
        dst::AbstractString = ".";
        merge::Bool = false,
        force::Union{Nothing,Bool} = nothing,
        ignore_hidden::Bool = false,
        hide_identifier::Union{Char,AbstractString} = '.'
    ) -> String

Download `src` from the `sftp` server to `dst` on the local system; `src` can be a file or folder.
Folders are downloaded recursively. `dst` must be an existing folder on the local system,
otherwise an `IOError` is thrown. `src` may include an absolute or relative path
on the `sftp` server, which is ignored on the local system. `dst` can be an absolute
or relative path on the local system. The function returns `dst` as String.

# kwargs

- `merge::Bool=false`: download into existing folders, when `true` or throw an `IOError`
- `force::Union{Nothing,Bool}=nothing`: Handle conflicts of existing files/folders
  - `nothing` (default): throw `IOError` for conflicts
  - `true`: overwrite existing files/folders
  - `false`: skip existing files/folders
  - if `merge = true`, `force` counts only for files
- `ignore_hidden::Bool=false`: ignore hidden files and folders
- `hide_identifier::Union{Char,AbstractString}='.'`: start sequence of hidden files and folders

# Example

```julia
sftp = SFTP.Client("sftp://test.rebex.net/pub/example/", "demo", "password")
files=readdir(sftp)
download_dir="/tmp"
download.(sftp, files, download_dir)
```

Alternatively:

```julia
sftp = SFTP.Client("sftp://test.rebex.net/pub/example/", "demo", "password")
donwload(sftp) # downloads current folder on server to current directory on local system
```
"""
function Base.download(
    sftp::Client,
    src::AbstractString = ".",
    dst::AbstractString = ".";
    merge::Bool = false,
    force::Union{Nothing,Bool} = nothing,
    ignore_hidden::Bool = false,
    hide_identifier::Union{Char,AbstractString} = '.'
)::String
    #* Check remote and local path
    base = basename(sftp, src)
    isdir(dst) || throw(Base.IOError("$dst must be an existing directory", 1))
    dst = realpath(dst)
    # Optional check, if src is hidden
    ignore_hidden && startswith(basename(src), hide_identifier) && return dst
    # Get conflicts with dst
    conflicts = readdir(dst)
    conflicts = filter(isequal(base), conflicts)
    #* Download src to dst
    if isdir(sftp, src)
        # Create base folder
        src = joinpath(sftp, src, "").path
        root_idx = length(src) + 1
        mkfolder(dst, [base], conflicts, merge, force)
        dst = joinpath(dst, base)
        # Download folder content recursively
        for (root, dirs, files) in walkdir(sftp, src; ignore_hidden, hide_identifier)
            # Sync folder structure
            cwd = normpath(dst, root[root_idx:end])
            conflicts = readdir(cwd)
            mkfolder(cwd, dirs, intersect(dirs, conflicts), merge, force)
            # Download files
            download_file(sftp, change_uripath(sftp.uri, root, trailing_slash = true), cwd,
                files, intersect(files, conflicts), force)
        end
    else
        # Download file
        download_file(sftp, src, dst, conflicts, force)
        # Update dst for return value
        dst = joinpath(dst, basename(src))
    end
    return dst
end


"""
    download(fcn::Function, sftp::Client, src::AbstractString)

Download `src` from the `sftp` server and use `fcn` to retrieve the data from `src`.`
`src` may include an absolute or relative path to the file on the `sftp` server.
Only temporary files are created on the local system and directly deleted after data reading.

.. info:
    `fcn` must have one `AbstractString` parameter, which is used to pass the temporary file
    path to any function that reads the contents. The function must return the contents of the
    file in any desired format, e.g. Matrix, DataFrame or array.

# Examples

```julia
using CSV, DataFrames
# Define functions to process the file data
fcsv(path::AbstractString)::Matrix{Int} = CSV.read(path, CSV.Tables.matrix)
fread(path::AbstractString)::Vector{String} = readlines(path)
# Download data to variable
matrix = download(fcsv, sftp, "data/matrix.csv", _test=true)
array = download(fread, sftp, "data/matrix.csv", _test=true)
```
"""
function Base.download(fcn::Function, sftp::Client, src::AbstractString; _test::Bool=false)
    mktempdir() do path
        # Check if src is a file
        isfile(sftp, src) || throw(Base.IOError("$src must be an existing file", 1))
        # Download file to temporary directory and return contents with help of fcn
        file = joinpath(path, basename(src))
        file = Downloads.download(string(change_uripath(sftp.uri, src, trailing_slash = false)),
            file; sftp.downloader)
        fcn(file)
    end
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
        [files::Vector{<:AbstractString},]
        conflicts::Vector{<:AbstractString},
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
        Downloads.download(string(change_uripath(src, file, trailing_slash = false)),
            joinpath(dst, file); sftp.downloader)
    end
    return
end

function download_file(
    sftp::Client,
    src::AbstractString,
    dst::AbstractString,
    conflicts::Vector{<:AbstractString},
    force::Union{Nothing,Bool}
)::Nothing
    # Prepare source file and conflicts
    uri, file = splitdir(sftp, src)
    # Call general upload_file method
    download_file(sftp, uri, dst, [file], conflicts, force)
end
