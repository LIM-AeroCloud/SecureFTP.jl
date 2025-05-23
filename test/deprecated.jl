# ¡ joinpath does not give deprecation warning, but uses URIs' joinpath instead
@testset "Deprecations" begin
    @test (@test_deprecated SFTP.pwd(sftp.uri)) == "/pub/example/"
    @test (@test_deprecated SFTP.splitdir(sftp.uri)) == (URI(sftp.uri, path="/pub/"), "example")
    @test (@test_deprecated SFTP.basename(sftp.uri)) == "example"
end
