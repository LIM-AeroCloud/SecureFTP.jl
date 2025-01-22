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
    eval(Meta.parse("public Client, SFTPStatStruct, download, stat, filemode, islink, isdir, isfile, pwd, cd, mv, rm, mkdir, walkdir, readdir, splitdir"))
end

export PathNotFoundError, upload, rmdir, statscan

end # module SFTP
