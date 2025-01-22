## Structs

"""
    mutable struct SFTP.Client

`SFTP` manages the connection to the server and stores all relevant connection data.

# Constructors

    SFTP.Client(url::AbstractString, username::AbstractString, public_key_file::AbstractString, public_key_file::AbstractString; kwargs) -> SFTP.Client
    SFTP.Client(url::AbstractString, username::AbstractString, password::AbstractString=""; kwargs) -> SFTP.Client

Construct an `SFTP.Client` from the url and either user information or public and private key file.

## Arguments

- `url`: The url to connect to, e.g., sftp://mysite.com
- `username`/`password`: user credentials
- `public_key_file`/`public_key_file`: authentication certificates

## Keyword arguments

- `create_known_hosts_entry`: Automatically create an entry in known hosts
- `disable_verify_peer`: verify the authenticity of the peer's certificate
- `disable_verify_host`: verify the host in the server's TLS certificate
- `verbose`: display a lot of verbose curl information


# Important notice

A username must be provided for both methods to work.

Before using the constructor method for certificate authentication, private and public
key files must be created and stored in the ~/.ssh folder and on the server, e.g.
~/.ssh/id_rsa and ~/.ssh/id_rsa.pub. Additionally, the host must be added to the
known_hosts file in the ~/.ssh folder.

The correct setup can be tested in the terminal with
`ssh myuser@mysitewhereIhaveACertificate.com`.


# Examples

    sftp = SFTP.Client("sftp://mysitewhereIhaveACertificate.com", "myuser", "test.pub", "test.pem")
    sftp = SFTP.Client("sftp://mysitewhereIhaveACertificate.com", "myuser")
    sftp = SFTP.Client("sftp://test.rebex.net", "demo", "password")
"""
mutable struct Client
    downloader::Downloader
    uri::URI
    username::String
    password::String
    disable_verify_peer::Bool
    disable_verify_host::Bool
    verbose::Bool
    public_key_file::String
    private_key_file::String
end


"""
    struct SFTP.StatStruct

Hold information for file system objects on a Server.

# Fields

- `desc::String`: file or folder description/name
- `mode::UInt`: file system object type (file, folder, etc.)
- `nlink::Int`: number of hard links (contents)
- `uid::String`: numeric user ID of the owner of the file/folder
- `uid::String`: numeric group ID (gid) for the file/folder
- `size::Int64`: file/folder size in Byte
- `mtime::Float64`: modified time


# Constructors

    SFTP.StatStruct(stats::AbstractString) -> SFTP.StatStruct

Parse the `stats` string and return an `SFTP.StatStruct`.

The `stats` are of the format:

    "d--x--x---  151 ftp      ftp          8192 Dec  2  2023 .."
"""
struct StatStruct
    desc::String
    mode::UInt
    nlink::Int
    uid::String
    gid::String
    size::Int64
    mtime::Float64
end


## External constructors

# See SFTP.Client struct for help/docstrings
function Client(
    url::AbstractString,
    username::AbstractString,
    public_key_file::AbstractString,
    private_key_file::AbstractString;
    disable_verify_peer::Bool=false,
    disable_verify_host::Bool=false,
    verbose::Bool=false
)::Client
    # Setup Downloader and URI
    downloader = Downloader()
    uri = set_url(url)
    # Instantiate and post-process easy hooks
    sftp = Client(downloader, uri, username, "", disable_verify_peer, disable_verify_host, verbose, public_key_file, private_key_file)
    reset_easy_hook(sftp)
    return sftp
end


# See SFTP.Client struct for help/docstrings
function Client(
    url::AbstractString,
    username::AbstractString,
    password::AbstractString="";
    create_known_hosts_entry::Bool=true,
    disable_verify_peer::Bool=false,
    disable_verify_host::Bool=false,
    verbose::Bool=false
)::Client
    # Setup Downloader and URI
    downloader = Downloader()
    uri = set_url(url)
    # Update known_hosts, if selected
    if !isempty(password) && create_known_hosts_entry
        check_and_create_fingerprint(uri.host)
    end
    # Instantiate and post-process easy hooks
    sftp = Client(downloader, uri, username, password, disable_verify_peer, disable_verify_host, verbose, "", "")
    reset_easy_hook(sftp)
    return sftp
end


# See SFTP.StatStruct struct for help/docstrings
function StatStruct(stats::AbstractString)::StatStruct
    stats = split.(stats, limit = 9)
    StatStruct(stats[9], parse_mode(stats[1]), parse(Int64, stats[2]), stats[3], stats[4],
        parse(Int64, stats[5]), parse_date(stats[6], stats[7], stats[8]))
end


## Overload Base functions

Base.show(io::IO, sftp::SFTP.Client)::Nothing =  println(io, "SFTP.Client(\"$(sftp.username)@$(sftp.uri.host)\")")

Base.broadcastable(sftp::Client) = Ref(sftp)


## Exception handling

"""
    PathNotFoundError(path)

The `path` (file or folder) was not found.
"""
struct PathNotFoundError <: Exception
  path::String
end

function Base.showerror(io::IO, e::PathNotFoundError)
  println(io, "PathNotFoundError: directory or file not found\n$(e.path)")
end


"""
    linkerror(link::String) -> Nothing

Show an error for an anticipated `link` format.
"""
linkerror(link::String)::Nothing = @error "link '$link' did not have anticipated format; link shown as file in walkdir iterator"


## Helper functions for processing of server paths

#¡ Trailing slashes needed for StatStruct and change_uripath!
"""
    set_url(url::URI) -> URI

Ensure URI path with trailing slash.
"""
function set_url(url::AbstractString)::URI
    uri = URI(url)
    change_uripath(uri, uri.path)
end


"""
    change_uripath(uri::URI, path::AbstractString; isfile::Bool=false) -> URI

Return an updated `uri` struct with the given `path`.
Set `isfile` to `true`, if the path is a file to omit the trailing slash.
"""
function change_uripath(uri::URI, path::AbstractString...; isfile::Bool=false)::URI
    # Issue with // at the beginning of a path can be resolved by ensuring non-empty paths
    url = joinpath(uri, string.(path...))
    isfile || (url = joinpath(url, ""))
    @debug "URI path" url.path
    URIs.resolvereference(uri, URIs.escapepath(url.path))
end


"""
    findbase(stats::Vector{SFTP.StatStruct}, base::AbstractString, path::AbstractString) -> Int

Return the index of `base` in `stats` or throw and `PathNotFoundError`, if `base` is not found.
"""
function findbase(stats::Vector{StatStruct}, base::AbstractString, path::AbstractString)::Int
    # Get path names and find base in it
    pathnames = [s.desc for s in stats]
    i = findfirst(isequal(base), pathnames)
    # Exception handling, if path is not found
    if isnothing(i)
        @warn "base not found in path; attempting to recover with similar basename"
        i = findall(startswith(base), pathnames)
        i = length(i) == 1 ? i[1] : throw(PathNotFoundError(path))
    end
    # Return index of base in stats
    return i
end


## Helper functions for SFTP.Client struct and fingerprints

"""
    check_and_create_fingerprint(host::AbstractString) -> Nothing

Check for `host` in known_hosts.
"""
function check_and_create_fingerprint(host::AbstractString)::Nothing
    try
        # Try to read known_hosts file
        known_hosts_file = joinpath(homedir(), ".ssh", "known_hosts")
        rows=CSV.File(known_hosts_file; delim=" ", types=String, header=false)
        # Scan known hosts for current host
        for row in rows
            row[1] != host && continue
            @info "$host found host in known_hosts"
            # check the entry we found
            fingerprint_algo = row[2]
            #These are known to work
            if (fingerprint_algo == "ecdsa-sha2-nistp256" || fingerprint_algo == "ecdsa-sha2-nistp256" ||
                fingerprint_algo ==  "ecdsa-sha2-nistp521"  || fingerprint_algo == "ssh-rsa" )
                return
            else
                @warn "correct fingerprint not found in known_hosts"
            end
        end
        @info "Creating fingerprint" host
        create_fingerprint(host)
    catch error
        @warn "An error occurred during fingerprint check; attempting to create a new fingerprint" error
        create_fingerprint(host)
    end
end


"""
    create_fingerprint(host::AbstractString) -> Nothing

Create a new entry in known_hosts for `host`.
"""
function create_fingerprint(host::AbstractString)::Nothing
    # Check for .ssh/known_hosts and create if missing
    sshdir = mkpath(joinpath(homedir(), ".ssh"))
    known_hosts = joinpath(sshdir, "known_hosts")
    # Import ssh key as trusted key or throw error (except for known test issue)
    keyscan = ""
    try
        keyscan = readchomp(`ssh-keyscan -t ssh-rsa $(host)`)
    catch
        @error "keyscan failed; check if ssh-keyscan is installed"
        if host == "test.rebex.net"
            # Fix missing keyscan on NanoSoldier
            keyscan = """test.rebex.net ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAkRM6RxDdi3uAGogR3nsQMpmt43X4WnwgMzs8VkwUCqikewxqk4U7EyUSOUeT3CoUNOtywrkNbH83e6/yQgzc3M8i/eDzYtXaNGcKyLfy3Ci6XOwiLLOx1z2AGvvTXln1RXtve+Tn1RTr1BhXVh2cUYbiuVtTWqbEgErT20n4GWD4wv7FhkDbLXNi8DX07F9v7+jH67i0kyGm+E3rE+SaCMRo3zXE6VO+ijcm9HdVxfltQwOYLfuPXM2t5aUSfa96KJcA0I4RCMzA/8Dl9hXGfbWdbD2hK1ZQ1pLvvpNPPyKKjPZcMpOznprbg+jIlsZMWIHt7mq2OJXSdruhRrGzZw=="""
        else
            rethrow()
        end
    end

    # Add host to known hosts
    @info "Adding fingerprint to known_hosts" keyscan
    open(known_hosts, "a+") do f
        println(f, keyscan)
    end
end


## Helper functions Curl options

"""
    set_stdopt(sftp::SFTP.Client, easy::Easy) -> Nothing

Set defaults for a number of curl `easy` options as defined by the `sftp` client.
"""
function set_stdopt(sftp::Client, easy::Easy)::Nothing
    # User credentials
    isempty(sftp.username) || Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_USERNAME, sftp.username)
    isempty(sftp.password) || Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_PASSWORD, sftp.password)
    # Verifications
    sftp.disable_verify_host && Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_SSL_VERIFYHOST , 0)
    sftp.disable_verify_peer && Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_SSL_VERIFYPEER , 1)
    # Certificates
    isempty(sftp.public_key_file) || Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_SSH_PUBLIC_KEYFILE, sftp.public_key_file)
    isempty(sftp.private_key_file) || Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_SSH_PRIVATE_KEYFILE, sftp.private_key_file)
    # Verbosity
    sftp.verbose && Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_VERBOSE, 1)
    return
end


"""
    reset_easy_hook(sftp::SFTP.Client) -> Nothing

Reset curl `easy` options to standard as defined by the `sftp` client.
"""
function reset_easy_hook(sftp::Client)::Nothing
    downloader = sftp.downloader
    downloader.easy_hook = (easy::Easy, info) -> begin
        set_stdopt(sftp, easy)
        Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_DIRLISTONLY, 1)
    end
    return
end
