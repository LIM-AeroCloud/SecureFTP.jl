"""
    pwd(sftp::SFTP.Client) -> String

Get the current directory of the `sftp` server. Also checks whether the path is valid
and throws an `IOError` otherwise.

see also: [`cd`](@ref cd(::SFTP.Client, ::AbstractString)),
[`mv`](@ref mv(::SFTP.Client, ::AbstractString, ::AbstractString; force::Bool=false)),
[`rm`](@ref rm(::SFTP.Client, ::AbstractString; recursive::Bool=false, force::Bool=false))
"""
function Base.pwd(sftp::Client)::String
    Base.depwarn("From v0.2.0 on, the validity checks of the URI path in `sftp` are deprecated.", :pwd)
    if isempty(sftp.uri.path)
        return "/"
    else
        # TODO remove stat test -> path should have been validated before
        # Check that path is valid or throw an error
        stat(sftp, sftp.uri.path)
        # Return valid path
        return sftp.uri.path
    end
end


"""
    pwd(uri::URI) -> String

Return the current path of the `uri`.
"""
function Base.pwd(uri::URI)::String
    Base.depwarn(string("pwd(::URI) is deprecated. It will be removed in v0.2.0 to avoid type piracy. ",
        "If you rely on this method open an issue or make a pull request to URIs.jl ",
        "(https://github.com/JuliaWeb/URIs.jl)"), :pwd)
    isempty(uri.path) ? "/" : string(uri.path)
end


"""
    splitdir(uri::URI) -> Tuple{URI, String}

Split the `uri` path into a directory and base part. The directory is returned as a `URI` with a
trailing slash in the path.
"""
function Base.splitdir(uri::URI, path::AbstractString=".")::Tuple{URI,String}
    Base.depwarn(string("splitdir(::URI) is deprecated. It will be removed in v0.2.0 to avoid type piracy. ",
        "If you rely on this method open an issue or make a pull request to URIs.jl ",
        "(https://github.com/JuliaWeb/URIs.jl)"), :splitdir)
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

"""
    basename(uri::URI) -> String

Return the base name (last non-empty part after a path separator (`/` or `\\` in Windows)) of the `uri` path.
"""
function Base.basename(uri::URI, path::AbstractString=".")::String
    Base.depwarn(string("basename(::URI) is deprecated. It will be removed in v0.2.0 to avoid type piracy. ",
        "If you rely on this method open an issue or make a pull request to URIs.jl ",
        "(https://github.com/JuliaWeb/URIs.jl)"), :basename)
    splitdir(uri, path)[2]
end
