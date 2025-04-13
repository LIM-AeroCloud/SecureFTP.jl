## Helper functions


"""
    test_known_hosts()

Test the checks and creation of known_hosts files and possible error handling.
"""
function test_known_hosts()::Nothing
    mktempdir() do path
        file = joinpath(path, ".ssh", "known_hosts")
        cp(joinpath("data", ".ssh"), joinpath(path, ".ssh"))
        @test_throws Base.ProcessFailedException SFTP.check_and_create_fingerprint("new.host", file)
        @test_logs (:info, "host.com found in known_hosts") SFTP.check_and_create_fingerprint("host.com", file)
        @test readlines(file) == readlines(joinpath("data", ".ssh", "known_hosts"))
        @test_logs((:info, "test.rebex.net found in known_hosts"), (:warn, "correct fingerprint not found in known_hosts"),
            (:info, "Creating fingerprint"), (:info, "Adding fingerprint to known_hosts"), SFTP.check_and_create_fingerprint("test.rebex.net", file))
        @test readlines(file) == readlines(joinpath("data", ".ssh", "updated_known_hosts"))
        file = joinpath(path, ".ssh", "unknown_hosts")
        @test_logs((:info, "Creating fingerprint"), (:info, "Adding fingerprint to known_hosts"), SFTP.check_and_create_fingerprint("test.rebex.net", file))
        @test readlines(file) == readlines(joinpath("data", ".ssh", "updated_unknown_hosts"))
        file = joinpath(path, ".ssh", "missing_hosts")
        @test_logs((:warn, "known_hosts not found, creating '$file'"), (:info, "Creating fingerprint"),
            (:info, "Adding fingerprint to known_hosts"), SFTP.check_and_create_fingerprint("test.rebex.net", file))
        @test readlines(file) == readlines(joinpath("data", ".ssh", "updated_missing_hosts"))
        file = joinpath(path, ".missing", "known_hosts")
        @test_logs((:warn, "known_hosts not found, creating '$file'"), (:info, "Creating fingerprint"),
            (:info, "Adding fingerprint to known_hosts"), SFTP.check_and_create_fingerprint("test.rebex.net", file))
        @test isfile(file)
        @test readlines(file) == readlines(joinpath("data", ".ssh", "updated_missing_hosts"))
    end
    return
end


"""
    test_fileupload(sftp::SFTP.Client)

Test the file upload with the upload function and various flags as well as error handling.
"""
function test_fileupload(sftp::SFTP.Client)::Nothing
    mktempdir() do path
        upload(sftp, joinpath("data", ".hidden_file"), "/", __test__=path)
        @test isfile(joinpath(path, ".hidden_file"))
        @test_throws Base.IOError upload(sftp, joinpath("data", ".hidden_file"), "/", __test__=path)
        @test_nowarn upload(sftp, joinpath("data", ".hidden_file"), "/", __test__=path, force=true)
    end
    mktempdir() do path
        upload(sftp, joinpath("data", ".hidden_file"), "/", __test__=path, ignore_hidden=true)
        @test !isfile(joinpath(path, ".hidden_file"))
    end
    return
end


"""
    test_dirupload(sftp::SFTP.Client)

Test the directory upload with the upload function and various flags as well as error handling.
"""
function test_dirupload(sftp::SFTP.Client)::Nothing
    mktempdir() do path
        upload(sftp, "data", "/", __test__=path)
        @test test_upload(path, "data", upload_target)
        @test_throws Base.IOError upload(sftp, "data", "/", __test__=path)
        @test_nowarn upload(sftp, "data", "/", __test__=path, force=true)
    end
    mktempdir() do path
        upload(sftp, "data", "/", __test__=path, ignore_hidden=true)
        @test test_upload(path, "data", visible_upload)
        @test_throws Base.IOError upload(sftp, "data", "/", __test__=path, merge=true)
        upload(sftp, "data", "/", __test__=path, merge=true, force=true)
        @test test_upload(path, "data", upload_target)
    end
    mktempdir() do path
        mkpath(joinpath(path, "data", "existing_dir"))
        touch(joinpath(path, "data", "existing_file"))
        touch(joinpath(path, "data", "existing_dir", "subfile"))
        upload(sftp, "data", "/", __test__=path, merge=true)
        @test test_upload(path, "data", merged_upload)
    end
    return
end


"""
    test_upload(
        tmpdir::AbstractString,
        dir::AbstractString,
        target::Vector{Tuple{String,Vector{String},Vector{String}}}
    ) -> Bool

Compare the contents in the mocked `tmpdir`/`dir` to the `target` path objects.
Return `true`, if all folders and files match, otherwise `false`.
"""
function test_upload(
    tmpdir::AbstractString,
    dir::AbstractString,
    target::Vector{Tuple{String,Vector{String},Vector{String}}}
)::Bool
    for (src, dst) in zip(walkdir(joinpath(tmpdir, dir)), target)
        src[2] == dst[2] || return false
        src[3] == dst[3] || return false
    end
    return true
end


## Target values

#* Upload path structure
# Define expected uploaded path objects
upload_target = collect(walkdir("data"))

# Define uploads without hidden path objects
visible_upload = deepcopy(upload_target)
deleteat!(visible_upload, 2:4)
deleteat!(visible_upload[1][2], 1:2)
popfirst!(visible_upload[1][3])

# Define upload into existing path
merged_upload = deepcopy(upload_target)
insert!(merged_upload[1][2], 3, "existing_dir")
push!(merged_upload[1][3], "existing_file")
insert!(merged_upload, 5, (joinpath("data", "existing_dir"), [], ["subfile"]))


#* Download stats

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

wd_bottomup = [
    ("/pub/example/", String[],
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
    ),
    ("/pub/", ["example"], String[]),
    ("/", ["pub"], ["readme.txt"])
]

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
