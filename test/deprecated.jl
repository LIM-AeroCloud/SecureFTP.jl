@testset "Deprecations" begin
    @test_deprecated pwd(sftp)
    @test (@test_deprecated pwd(sftp.uri)) == "/pub/example/"
    @test (@test_deprecated splitdir(sftp.uri)) == (URI(sftp.uri, path="/pub/"), "example")
    @test (@test_deprecated basename(sftp.uri)) == "example"
    @test joinpath(sftp.uri, "/a/b/c") == URI("sftp://test.rebex.net/a/b/c")
end
