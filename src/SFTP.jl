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
include("fileexchange.jl")
include("filestats.jl")
include("filesystem.jl")

@static if VERSION ≥ v"1.11"
    eval(Meta.parse("public Client, StatStruct, download, stat, filemode, ispath, isdir, isfile, islink, pwd, cd, mv, rm, mkdir, mkpath, readdir, walkdir, joinpath, splitdir, basename"))
end

export upload, statscan, URI

end # module SFTP
