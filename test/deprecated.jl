@testset "Deprecations" begin
    @test (@test_deprecated SFTP.pwd(sftp.uri)) == "/pub/example/"
    @test (@test_deprecated SFTP.splitdir(sftp.uri)) == (URI(sftp.uri, path="/pub/"), "example")
    @test (@test_deprecated SFTP.basename(sftp.uri)) == "example"
    @test joinpath(sftp.uri, "/a/b/c") == URI("sftp://test.rebex.net/a/b/c")
end
