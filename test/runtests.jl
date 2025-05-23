using SFTP
using Test

## Setup
include("setup.jl")
sftp = SFTP.Client("sftp://test.rebex.net/pub/example/", "demo", "password")
stats = statscan(sftp)
files = readdir(sftp)


## Test Connection to server
@testset "Connect Test" begin
    sftp = SFTP.Client("sftp://test.rebex.net", "demo", "password")
    @test sftp.uri.path == "/"
    @test sftp.username == "demo"
    @test sftp.password == "password"
    sftp = SFTP.Client("sftp://test.rebex.net/foo/bar", "demo", "password")
    @test sftp.uri.path == "/foo/bar"
    sftp = SFTP.Client("sftp://test.rebex.net/foo/bar/", "demo", "password")
    @test sftp.uri.path == "/foo/bar/"
    test_known_hosts()
end


## Test file system navigation

dirs = readdir(sftp, "/pub")
wd = collect(walkdir(sftp, "/"))
wd_bu = collect(walkdir(sftp, "/", topdown=false))
wd_closed = walkdir(sftp, "/pub/example/readme.txt")

@testset "filesystem" begin
    sftp_root = SFTP.Client("sftp://test.rebex.net", "demo", "password")
    @test sftp_root.uri.path == "/"
    @test pwd(sftp_root) == "/"
    cd(sftp_root, "pub/example")
    @test sftp_root.uri.path == sftp.uri.path
    @test pwd(sftp) == "/pub/example/"
    @test SFTP.unescape_joinpath(sftp, "unescaped dir") == "/pub/example/unescaped dir"
    @test files == wd_target[3]
    @test dirs == ["example"]
    @test wd[3][3] == wd_target[3]
    @test_throws Base.IOError cd(sftp, "foo")
    @test_throws Base.IOError mv(sftp, "foo", "bar")
    @test_throws SFTP.Downloads.RequestError mv(sftp, "/pub/example", "foo")
    @test_throws Base.IOError rm(sftp, "/pub/example")
    @test_nowarn rm(sftp, "/pub/example/KeyGenerator.png", recursive=true, force=true)
    @test_throws Base.IOError mkdir(sftp, "foo/bar")
    @test_throws Base.IOError mkdir(sftp, "/pub")
    @test_throws SFTP.Downloads.RequestError mkdir(sftp, "/pub/example/foo")
    @test_throws SFTP.Downloads.RequestError mkpath(sftp, "/pub/example/foo")
    @test wd_closed.state == :closed
    sftp_err = SFTP.Client("sftp://test.rebex.net", "demo", "pass")
    @test_throws SFTP.Downloads.RequestError walkdir(sftp_err)
    @test wd_bu == wd_bottomup
    sftp.uri = URI("sftp://test.rebex.net")
    @test sftp.uri.path == ""
    @test pwd(sftp) == "/"
    cd(sftp, "/")
    @test basename(sftp) == ""
    @test splitdir(sftp) == (sftp.uri, "")
    @test splitdir(sftp, "pub") == (sftp.uri, "pub")
    cd(sftp, "pub/")
    @test basename(sftp) == "pub"
    @test splitdir(sftp, "/pub/example/") == (sftp.uri, "example")
end

## Test everything possible about structs and stat that is not already covered
# Prepare tests
sftp = SFTP.Client("sftp://test.rebex.net/pub/example/", "demo", "password")
linkstat = SFTP.StatStruct("foo -> path/to/foo", "symlink", 0x000000000000a000, 1, "demo", "users", 1024, 1.175e9)
io = IOBuffer()
show(io, sftp)
res = String(take!(io))

# Run tests
@testset "Stats and structs" begin
    @test stats[1] == target_structs[1]
    @test linkstat.desc == "foo"
    @test linkstat.root == "symlink -> path/to"
    @test res == "SFTP.Client(\"demo@test.rebex.net\")\n"
    @test isequal(stat(sftp, "KeyGenerator.png"), target_structs[1]) == true
    @test isequal(stat(sftp, "KeyGenerator.png"), target_structs[2]) == false
    @test SFTP.parse_mode("lxxxxx-x--") == 0xa1f4
    @test_nowarn SFTP.parse_mode("dx--x--x--")
    @test_throws ArgumentError SFTP.parse_mode("dx--x----")
    @test_throws ArgumentError SFTP.parse_mode("dx--x--x---")
    @test ispath(sftp, "/pub") == true
    @test ispath(sftp, "foo") == false
    st = stat(sftp, "/pub/example/KeyGenerator.png")
    @test isfile(st) == true
    @test isdir(st) == false
    @test islink(st) == false
    @test islink(sftp, "/pub/example/KeyGenerator.png") == false
end

## Test internal URI changes
uri = URI("sftp://test.com/root/path")
@testset "path changes" begin
    @testset "URI" begin
        @test SFTP.change_uripath(uri, "newpath") == URI("sftp://test.com/root/path/newpath")
        @test SFTP.change_uripath(uri, "newpath/") == URI("sftp://test.com/root/path/newpath/")
        @test SFTP.change_uripath(uri, "/newroot") == URI("sftp://test.com/newroot")
        @test SFTP.change_uripath(uri, "/newroot/") == URI("sftp://test.com/newroot/")
        @test SFTP.change_uripath(uri, "/newroot", "and", "path") == URI("sftp://test.com/newroot/and/path")
        @test SFTP.change_uripath(uri, "new", "path", "parts") == URI("sftp://test.com/root/path/new/path/parts")
        @test SFTP.change_uripath(uri, "/newroot", "path", "/secondroot") == URI("sftp://test.com/secondroot")
        @test SFTP.change_uripath(uri, "/newroot", trailing_slash=true) == URI("sftp://test.com/newroot/")
        @test SFTP.change_uripath(uri, "/newroot", trailing_slash=false) == URI("sftp://test.com/newroot")
        @test SFTP.change_uripath(uri, "/newroot/", trailing_slash=true) == URI("sftp://test.com/newroot/")
        @test SFTP.change_uripath(uri, "/newroot/", trailing_slash=false) == URI("sftp://test.com/newroot")
    end
    @testset "Client" begin
        @test SFTP.change_uripath(sftp, "/pub") == URI("sftp://test.rebex.net/pub/")
        @test SFTP.change_uripath(sftp, "/pub", "example") == URI("sftp://test.rebex.net/pub/example/")
        @test SFTP.change_uripath(sftp, "/pub/example") == URI("sftp://test.rebex.net/pub/example/")
        @test SFTP.change_uripath(sftp, "/pub/example", "KeyGenerator.png") == URI("sftp://test.rebex.net/pub/example/KeyGenerator.png")
        @test SFTP.change_uripath(sftp, "..") == URI("sftp://test.rebex.net/pub/")
        @test_throws Base.IOError SFTP.change_uripath(sftp, "/foo")
    end
    @test_throws Base.IOError SFTP.findbase(target_structs, "foo", "bar")
end

## Test file exchange
f(path::AbstractString)::Vector{String} = readlines(path)

@testset "upload" begin
    @testset "wrong path" begin
        @test_throws Base.IOError upload(sftp, "foo.txt", "pub")
        @test_throws Base.IOError upload(sftp, "setup.jl", "foo")
    end
    @testset "file" test_fileupload(sftp)
    @testset "directory" test_dirupload(sftp,)
end

@testset "download" begin
    @testset "to dir" begin
        mktempdir() do path
            path = realpath(path)
            @test download.(sftp, files, path) == joinpath.(path, files)
            @test download(sftp, "readme.txt", path, force = true) == joinpath(path, "readme.txt")
            @test download(sftp, "readme.txt", path, force = false) == joinpath(path, "readme.txt")
            @test_throws Base.IOError download(sftp, "readme.txt", path)
            dir = mkdir(joinpath(path, "example")) # create example folder to test merge flag
            @test_throws Base.IOError download(sftp, ".", path) == joinpath(path, "example")
            @test_nowarn download(sftp, ".", path, merge=true)
            @test_nowarn download(sftp, ".", path, force=true)
            @test isfile(joinpath(path, "readme.txt"))
            @test isfile(joinpath(path, "KeyGenerator.png"))
            rm.(readdir(path, join=true), recursive=true, force=true)
            @test download(sftp, ".", path, ignore_hidden=true, hide_identifier='p') == joinpath(path, "example")
            @test readdir(joinpath(path, "example")) == filter(!startswith("p"), files)
        end
    end
    @testset "to variable" begin
        @test download(f, sftp, "readme.txt") == readme_content
        @test download(f, sftp, "readme.txt") == readme_content # test repeated loading (no force needed)
        @test_throws Base.IOError download(f, sftp, "foo.txt")
        @test_throws Base.IOError download(f, sftp, "pub")
    end
end


## URI methods
# Test that joinpath method for URI structs gives the corrected results
# and the correct method is used by change_uripath
@testset "URI methods" begin
    sftp = SFTP.Client("sftp://test.rebex.net", "demo", "password")
    @test SFTP.change_uripath(sftp.uri, "/a/b/c").path == "/a/b/c"
    cd(sftp, "/pub/example")
    @test_skip @test_throws MethodError pwd(sftp.uri)
    @test SFTP.cwd(sftp.uri) == "/pub/example/"
    @test (@test_nowarn pwd(sftp)) == "/pub/example/"
end

## Deprecations
include("deprecated.jl")
