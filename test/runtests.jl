using SFTP
using Test
using CSV

include("setup.jl")

@testset "Connect Test" begin
    @test files == wd_target[3]
    @test stats[1] == target_structs[1]
    @test dirs == ["example"]
    @test wd[3][3] == wd_target[3]
end

#* Test everything possible about structs that is not already covered
# Prepare tests
linkstat = SFTP.StatStruct("foo -> path/to/foo", "symlink", 0x000000000000a000, 1, "demo", "users", 1024, 1.175e9)
io = IOBuffer()
show(io, sftp)
res = String(take!(io))

@testset "Structs" begin
    @test linkstat.desc == "foo"
    @test linkstat.root == "symlink -> path/to"
    @test res == "SFTP.Client(\"demo@test.rebex.net\")\n"
end

#* Test internal URI changes
uri = URI("sftp://test.com/root/path")
cd(sftp, "/pub/example")
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

#* Test file exchange
f(path::AbstractString)::Vector{String} = readlines(path)
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
            @test download(sftp, ".", path, merge=true) == joinpath(path, "example")
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

## Clean-up
rm("readme.txt", force=true)
