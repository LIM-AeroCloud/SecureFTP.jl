using SFTP
using Test
using CSV

include("setup.jl")

@testset "Connect Test" begin
    @show tempdir()
    @test files == wd_target[3]
    @test stats[1] == target_structs[1]
    @test isfile(joinpath(tempdir(), "KeyGenerator.png"))
    @test dirs == ["example"]
    @test isfile("readme.txt")
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
@testset "file exchange" begin
    @test download(f, sftp, "readme.txt") == [
        "Welcome to test.rebex.net!",
        "",
        "You are connected to an FTP or SFTP server used for testing purposes",
        "by Rebex FTP/SSL or Rebex SFTP sample code. Only read access is allowed.",
        "",
        "For information about Rebex FTP/SSL, Rebex SFTP and other Rebex libraries",
        "for .NET, please visit our website at https://www.rebex.net/",
        "",
        "For feedback and support, contact support@rebex.net",
        "",
        "Thanks!"
    ]
    @test_throws Base.IOError download(f, sftp, "foo.txt")
    @test_throws Base.IOError download(f, sftp, "pub")
end
