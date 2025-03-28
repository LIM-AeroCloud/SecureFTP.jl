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
