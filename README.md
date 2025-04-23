# SecureFTP

A Julia Secure File Transfer Protocol (SFTP) Client for exploring the structure
and contents of SFTP servers and exchanging files.

## Overview

This package is based on [SFTPClient.jl](https://github.com/stensmo/SFTPClient.jl.git)
and builds on [Downloads.jl](https://github.com/JuliaLang/Downloads.jl.git) and
[LibCurl.jl](https://github.com/JuliaWeb/LibCURL.jl.git).

_SecureFTP.jl_ supports username/password as well as certificates for authentication.
It provides methods to exchange files with the SFTP server as well as investigate the
folder structure and files with methods based on 
[Julia's Filesystem functions](https://docs.julialang.org/en/v1/base/file/).
Details can be found in the [documentation](docs-dev-url).

| **Documentation**                                                                  | **Build Status**                                                            |
|:----------------------------------------------------------------------------------:|:---------------------------------------------------------------------------:|
| [![Stable][docs-stable-img]][docs-stable-url] [![Dev][docs-dev-img]][docs-dev-url] | [![Build Status][CI-img]][CI-url] [![Coverage][codecov-img]][codecov-url] |

## Showcase

```julia
using SecureFTP
# Set up client for connection to server
sftp = SecureFTP.Client("sftp://test.rebex.net/pub/example/", "demo", "password")
# Analyse contents of current path
files=readdir(sftp)
statStructs = statscan(sftp)
# Download contents
download.(sftp, files)
```

```julia
using SecureFTP
# You can also load file contents to a variable by passing a function to download as first argument
# Note: the function must an AbstractString as parameter for a temporary path of the downloaded file
# Note: the path will be deleted immediately after the contents are saved to the variable
fread(path::AbstractString)::Vector{String} = readlines(path)
array = download(fread, sftp, "data/matrix.csv")

# Certificate authentication works as well
sftp = SecureFTP.Client("sftp://mysitewhereIhaveACertificate.com", "myuser")
sftp = SecureFTP.Client("sftp://mysitewhereIhaveACertificate.com", "myuser", "cert.pub", "cert.pem") # Assumes cert.pub and cert.pem is in your current path
# The cert.pem is your certificate (private key), and the cert.pub can be obtained from the private key.
# ssh-keygen -y  -f ./cert.pem. Save the output into "cert.pub". 
```

[docs-stable-img]: https://img.shields.io/badge/docs-stable-blue.svg
[docs-stable-url]: https://LIM-AeroCloud.github.io/SecureFTP.jl/stable/

[docs-dev-img]: https://img.shields.io/badge/docs-dev-blue.svg
[docs-dev-url]: https://LIM-AeroCloud.github.io/SecureFTP.jl/dev/

[CI-img]: https://github.com/LIM-AeroCloud/SecureFTP.jl/actions/workflows/CI.yml/badge.svg?branch=dev
[CI-url]: https://github.com/LIM-AeroCloud/SecureFTP.jl/actions/workflows/CI.yml?query=branch%3Adev

[codecov-img]: https://codecov.io/gh/LIM-AeroCloud/SecureFTP.jl/graph/badge.svg?token=kYZK3bRvCZ
[codecov-url]: https://codecov.io/gh/LIM-AeroCloud/SecureFTP.jl
