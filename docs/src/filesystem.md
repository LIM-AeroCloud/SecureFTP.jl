# Filesystem functions

_SecureFTP.jl_ overloads a number of Julia's Base Filesystem functions to navigate and
manipulate server paths and retrieve stats on path objects (files, symlinks or folders).
The SecureFTP filesystem methods mimic Julia's Filesystem functions or Linux filesystem
functions, respectively, however, _SecureFTP.jl_'s functionality might be reduced.

## URI

Several of the Filesystem functions return a `URI` struct from the
[URIs package](https://github.com/JuliaWeb/URIs.jl.git) to represent the complete
server address including the path on the server. `URI` structs are also accepted as
input argument by serveral of _SecureFTP.jl_'s Filesystem functions.
For easier handling, the `URI` struct is exported by _SecureFTP.jl_ as well. See
[URIs' documentation](https://docs.juliahub.com/URIs/eec2u/1.5.1/#URIs.URI)
for more details on the `URI` struct.

## Navigating server paths

```@docs
pwd
cd(::SecureFTP.Client, ::AbstractString)
mv(::SecureFTP.Client, ::AbstractString, ::AbstractString; force::Bool=false)
rm(::SecureFTP.Client, ::AbstractString; recursive::Bool=false, force::Bool=false)
mkdir(::SecureFTP.Client, ::AbstractString)
mkpath(::SecureFTP.Client, ::AbstractString)
readdir(::SecureFTP.Client, ::AbstractString; kwargs...)
walkdir(::SecureFTP.Client, ::AbstractString; kwargs...)
```

## Analyse and manipulate server paths

```@docs
joinpath(::SecureFTP.Client)
basename
splitdir
```

## Getting statistics on path objects

The [`SecureFTP.StatStruct`](@ref) holds all relevant information on server path objects.
It can be directly analysed by functions analysing the filemode ([`filemode`](@ref),
[`isdir`](@ref), [`isfile`](@ref) or [`islink`](@ref)). For these functions, additional
convenience methods exist, which take the `SecureFTP.Client` and an `AbstractString` of the
`path` as input arguments.

!!! tip
    [`statscan`](@ref) should be preferred, whenever several objects are analysed
    in the same folder. Further analysis should be performed on the `SecureFTP.StatStruct`
    rather than with the convenience functions to improve performance.  
    The convenience functions are mainly for single operations or when interactively
    exploring a server, but can mean significantly longer processing times for large
    folders on the server. Internally, the whole folder content is always scanned and
    the stats for the desired files are then retrieved from all scans.

```@docs
SecureFTP.StatStruct
```

```@docs
statscan
stat(sftp::SecureFTP.Client, ::AbstractString)
filemode
ispath(::SecureFTP.Client, ::AbstractString)
isdir
isfile
islink
```
