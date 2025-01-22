using SFTP
using Test

include("setup.jl")

@testset "Connect Test" begin
    @show tempdir()
    @test files == walkdirResults[3]
    @test stats[1] == actualStructs[1]
    @test isfile(joinpath(tempdir(), "KeyGenerator.png"))
    @test dirs == ["example"]
    @test isfile("readme.txt")
    @test walkdirFiles[3] == walkdirResults[3]

end
