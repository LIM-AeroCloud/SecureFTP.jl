## stat functions

"""
    statscan(
        sftp::SecureFTP.Client,
        path::AbstractString=".";
        sort::Bool=true,
        show_cwd_and_parent::Bool=false
    ) -> Vector{SecureFTP.StatStruct}

Like [`stat`](@ref), but returns a Vector of [`SecureFTP.StatStruct`](@ref) with filesystem stats
for all objects in the given `path`.

!!! tip
    **This should be preferred over [`stat`](@ref) for performance reasons.**

!!! note
    You can only run this on directories.

By default, the [`SecureFTP.StatStruct`](@ref) vector is sorted by the descriptions
(`desc` fields). For large folder contents, `sort` can be set to `false` to increase
performance, if the output order is irrelevant. If `show_cwd_and_parent` is set to `true`,
the [`SecureFTP.StatStruct`](@ref) vector includes entries for `"."` and `".."` on position
1 and 2, respectively.

see also: [`stat`](@ref stat(sftp::SecureFTP.Client, ::AbstractString))
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
    stat(sftp::SecureFTP.Client, path::AbstractString=".") -> SecureFTP.StatStruct

Return a [`SecureFTP.StatStruct`](@ref) with information about the `path`
(file, directory or symlink) on the `sftp` server.

!!! note
    This returns only stat data for one object, but stat data for all objects in
    the same folder is obtained internally. If you need stat data for more than object
    in the same folder, use [`statscan`](@ref) for better performance and reduced
    connections to the server.

see also: [`statscan`](@ref)
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
performant to use [`statscan`](@ref) once and then analyse each [`SecureFTP.StatStruct`](@ref).
"""

"""
    filemode(sftp::SecureFTP.Client, path::AbstractString=".") -> UInt
    filemode(st::SecureFTP.StatStruct) -> UInt

Return the filemode of the [`SecureFTP.StatStruct`](@ref). $PERFORMANCE_NOTICE

see also: [`ispath`](@ref ispath(::SecureFTP.Client, ::AbstractString)),
[`isdir`](@ref), [`isfile`](@ref), [`islink`](@ref)
"""
Base.filemode
Base.filemode(st::StatStruct)::UInt = st.mode
Base.filemode(sftp::Client, path::AbstractString=".")::UInt = stat(sftp, path).mode


"""
    ispath(sftp::SecureFTP.Client, path::AbstractString=".") -> Bool

Return `true`, if a `path` exists on the `sftp` server, i.e. is a file, folder or link.
Otherwise, return `false`.

see also: [`filemode`](@ref), [`isdir`](@ref), [`isfile`](@ref), [`islink`](@ref)
"""
Base.ispath(sftp::Client, path::AbstractString=".")::Bool = try
    stat(sftp, path)
    true
catch
    false
end


"""
    isdir(sftp::SecureFTP.Client, path::AbstractString=".") -> Bool
    isdir(st::SecureFTP.StatStruct) -> Bool

Analyse the [`SecureFTP.StatStruct`](@ref) and return `true` for a directory, `false` otherwise.
$PERFORMANCE_NOTICE

see also: [`filemode`](@ref), [`ispath`](@ref ispath(::SecureFTP.Client, ::AbstractString)),
[`isfile`](@ref), [`islink`](@ref)
"""
Base.isdir
Base.isdir(st::StatStruct)::Bool = filemode(st) & 0xf000 == 0x4000
Base.isdir(sftp::Client, path::AbstractString=".")::Bool = filemode(sftp, path) & 0xf000 == 0x4000


"""
    isfile(sftp::SecureFTP.Client, path::AbstractString=".") -> Bool
    isfile(st::SecureFTP.StatStruct) -> Bool

Analyse the [`SecureFTP.StatStruct`](@ref) and return `true` for a file, `false` otherwise.
$PERFORMANCE_NOTICE

see also: [`filemode`](@ref), [`ispath`](@ref ispath(::SecureFTP.Client, ::AbstractString)),
[`isdir`](@ref), [`islink`](@ref)
"""
Base.isfile
Base.isfile(st::StatStruct)::Bool = filemode(st) & 0xf000 == 0x8000
Base.isfile(sftp::Client, path::AbstractString=".")::Bool = filemode(sftp, path) & 0xf000 == 0x8000


"""
    islink(sftp::SecureFTP.Client, path::AbstractString=".") -> Bool
    islink(st::SecureFTP.StatStruct) -> Bool

Analyse the [`SecureFTP.StatStruct`](@ref) and return `true` for a symbolic link, `false` otherwise.
$PERFORMANCE_NOTICE

see also: [`filemode`](@ref), [`ispath`](@ref ispath(::SecureFTP.Client, ::AbstractString)),
[`isdir`](@ref), [`isfile`](@ref)
"""
Base.islink
Base.islink(st::StatStruct)::Bool = filemode(st) & 0xf000 == 0xa000
Base.islink(sftp::Client, path::AbstractString=".")::Bool = filemode(sftp, path) & 0xf000 == 0xa000
