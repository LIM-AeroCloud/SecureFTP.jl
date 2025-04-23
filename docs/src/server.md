# Server functionality

The main purpose of _SecureFTP.jl_ is to connect to a server with the secure file transfer
protocol and exchange files between the server and the local system.

## Connecting to the server

_SecureFTP.jl_ takes care of the connection to the server all by itself. All that needs
to be done is to instantiate a [`SecureFTP.Client`](@ref) with one of the appropriate
constructors for either authentication with username and password or with a certificate.

```@docs
SecureFTP.Client
```

## File exchange with the server

Use the [`upload`](@ref) and [`download`](@ref) functions to exchange data with the
SFTP server. Options exist for conflicts with already existing files to throw an
error, skip the exchange or force an overwrite. The functions can be used to exchange
single files, exchange directories recursively or broadcast over a number of files or
folders.

For [`download`](@ref download(::Function, ::SecureFTP.Client, ::AbstractString)),
an additional method exists to save contents from a remote file directly to a variable.

```@docs
upload
download(
    ::SecureFTP.Client,
    ::AbstractString=".",
    ::AbstractString=".";
    merge::Bool = false,
    force::Union{Nothing,Bool} = nothing,
    ignore_hidden::Bool = false,
    hide_identifier::Union{Char,AbstractString} = '.'
)
download(::Function, ::SecureFTP.Client, ::AbstractString)
```
