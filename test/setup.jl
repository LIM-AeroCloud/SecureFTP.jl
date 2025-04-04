## Helper functions

function test_known_hosts()::Nothing
    mktempdir() do path
        file = joinpath(path, ".ssh", "known_hosts")
        cp("data", joinpath(path, ".ssh"))
        @test_logs (:info, "host.com found in known_hosts") SFTP.check_and_create_fingerprint("host.com", file)
        @test readlines(file) == readlines("data/known_hosts")
        @test_logs((:info, "test.rebex.net found in known_hosts"), (:warn, "correct fingerprint not found in known_hosts"),
            (:info, "Creating fingerprint"), (:info, "Adding fingerprint to known_hosts"), SFTP.check_and_create_fingerprint("test.rebex.net", file))
        @test readlines(file) == readlines("data/updated_known_hosts")
        file = joinpath(path, ".ssh", "unknown_hosts")
        @test_logs((:info, "Creating fingerprint"), (:info, "Adding fingerprint to known_hosts"), SFTP.check_and_create_fingerprint("test.rebex.net", file))
        @test readlines(file) == readlines("data/updated_unknown_hosts")
        file = joinpath(path, ".ssh", "missing_hosts")
        @test_logs((:warn, "known_hosts not found, creating '$file'"), (:info, "Creating fingerprint"),
            (:info, "Adding fingerprint to known_hosts"), SFTP.check_and_create_fingerprint("test.rebex.net", file))
        @test readlines(file) == readlines("data/updated_missing_hosts")
        file = joinpath(path, ".missing", "known_hosts")
        @test_logs((:warn, "known_hosts not found, creating '$file'"), (:info, "Creating fingerprint"),
            (:info, "Adding fingerprint to known_hosts"), SFTP.check_and_create_fingerprint("test.rebex.net", file))
        @test isfile(file)
        @test readlines(file) == readlines("data/updated_missing_hosts")
    end
    return
end

# Connect to example folder on server
sftp = SFTP.Client("sftp://test.rebex.net", "demo", "password")
cd(sftp, "/pub/example")

#=
sftp_uri = SFTP.Client("sftp://test.rebex.net/pub/example/", "demo", "password")
@test sftp.uri.path == sftp_uri.uri.path
cd(sftp, "foo")
=#

# TODO move to runtests
# Get contents of example folder
stats = statscan(sftp)
files = readdir(sftp)


cd(sftp, "../")
dirs = readdir(sftp)
cd(sftp, "..")
wd = collect(walkdir(sftp, "."))
cd(sftp, "/pub/example")

## Results (for comparison)

target_structs = [
    SFTP.StatStruct("KeyGenerator.png", "/pub/example/", 0x0000000000008180, 1, "demo", "users", 36672, 1.1742624e9),
    SFTP.StatStruct("KeyGeneratorSmall.png", "/pub/example/", 0x0000000000008180, 1, "demo", "users", 24029, 1.1742624e9),
    SFTP.StatStruct("ResumableTransfer.png", "/pub/example/", 0x0000000000008180, 1, "demo", "users", 11546, 1.1742624e9),
    SFTP.StatStruct("WinFormClient.png", "/pub/example/", 0x0000000000008180, 1, "demo", "users", 80000, 1.1742624e9),
    SFTP.StatStruct("WinFormClientSmall.png", "/pub/example/", 0x0000000000008180, 1, "demo", "users", 17911, 1.1742624e9),
    SFTP.StatStruct("imap-console-client.png", "/pub/example/", 0x0000000000008100, 1, "demo", "users", 19156, 1.171584e9),
    SFTP.StatStruct("mail-editor.png", "/pub/example/", 0x0000000000008100, 1, "demo", "users", 16471, 1.171584e9),
    SFTP.StatStruct("mail-send-winforms.png", "/pub/example/", 0x0000000000008100, 1, "demo", "users", 35414, 1.171584e9),
    SFTP.StatStruct("mime-explorer.png", "/pub/example/", 0x0000000000008100, 1, "demo", "users", 49011, 1.171584e9),
    SFTP.StatStruct("pocketftp.png", "/pub/example/", 0x0000000000008180, 1, "demo", "users", 58024, 1.1742624e9),
    SFTP.StatStruct("pocketftpSmall.png", "/pub/example/", 0x0000000000008180, 1, "demo", "users", 20197, 1.1742624e9),
    SFTP.StatStruct("pop3-browser.png", "/pub/example/", 0x0000000000008100, 1, "demo", "users", 20472, 1.171584e9),
    SFTP.StatStruct("pop3-console-client.png", "/pub/example/", 0x0000000000008100, 1, "demo", "users", 11205, 1.171584e9),
    SFTP.StatStruct("readme.txt", "/pub/example/", 0x0000000000008180, 1, "demo", "users", 379, 1.69512912e9),
    SFTP.StatStruct("winceclient.png", "/pub/example/", 0x0000000000008180, 1, "demo", "users", 2635, 1.1742624e9),
    SFTP.StatStruct("winceclientSmall.png", "/pub/example/", 0x0000000000008180, 1, "demo", "users", 6146, 1.1742624e9)
 ]

 wd_target = (
    "/pub/example/", String[],
    ["KeyGenerator.png",
    "KeyGeneratorSmall.png",
    "ResumableTransfer.png",
    "WinFormClient.png",
    "WinFormClientSmall.png",
    "imap-console-client.png",
    "mail-editor.png",
    "mail-send-winforms.png",
    "mime-explorer.png",
    "pocketftp.png",
    "pocketftpSmall.png",
    "pop3-browser.png",
    "pop3-console-client.png",
    "readme.txt",
    "winceclient.png",
    "winceclientSmall.png"]
)

readme_content = [
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
