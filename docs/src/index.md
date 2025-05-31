# SFTP.jl

*An SFTP Client for Julia.*

_SFTP.jl_ is a pure Julia package for connecting to servers with the secure file
transfer protocol (SFTP), supporting authentication by username and password or
by certificates. Main purpose is the file exchange between the SFTP server and the
local system. Basic file system functions similar to Julia's Base functions and
to the typical Linux functionality exist to explore the SFTP server.

## SFTP Feature overview

- Connection to SFTP server by username/password or with certificate authentication
- File [`upload`](@ref)/[`download`](@ref) to/from server
- Inspect the server with file system functions like [`walkdir`](@ref), [`readdir`](@ref),
  [`stat`](@ref)/[`statscan`](@ref), [`filemode`](@ref), [`ispath`](@ref), [`isdir`](@ref),
  [`isfile`](@ref), [`islink`](@ref)
- Navigate and manipulate server content with functions like [`pwd`](@ref), [`cd`](@ref),
  [`mv`](@ref), [`rm`](@ref), [`mkdir`](@ref), [`mkpath`](@ref)
- Create script with the help of further filesystem functions like [`joinpath`](@ref),
  [`basename`](@ref), [`dirname`](@ref) or [`splitdir`](@ref)

## SFTP Installation

Install using the package manager:

```julia
julia> ]

pkg> add SFTP
```

## Contents

```@contents
Pages = [
    "index.md",
    "server.md",
    "filesystem.md",
    "troubleshooting.md",
    "release-notes.md",
    "register.md"
]
```
