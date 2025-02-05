module SFTP

import Downloads
import LibCURL
import URIs
import CSV
import Dates
import Downloads: Downloader, Curl.Easy
import URIs: URI
import Logging

include("client.jl")
include("filesystem.jl")

@static if VERSION ≥ v"1.11"
    eval(Meta.parse("public Client, SFTPStatStruct, download, stat, filemode, islink, isdir, isfile, pwd, cd, mv, rm, mkpath, walkdir, readdir, splitdir, basename"))
end

export PathNotFoundError, upload, statscan

end # module SFTP
