sftp = SFTP.Client("sftp://test.rebex.net", "demo", "password")
cd(sftp, "/pub/example")

stats = statscan(sftp)

files = readdir(sftp)

download.(sftp, files, tempdir())

cd(sftp, "../")
dirs = readdir(sftp)

cd(sftp, "..")

download.(sftp, "readme.txt", ".")

walkdirRoot, walkdirDirs, walkdirFiles = walkdir(sftp, ".")

actualStructs = [
    SFTP.StatStruct("KeyGenerator.png", 0x0000000000008180, 1, "demo", "users", 36672, 1.1742624e9)
    SFTP.StatStruct("KeyGeneratorSmall.png", 0x0000000000008180, 1, "demo", "users", 24029, 1.1742624e9)
    SFTP.StatStruct("ResumableTransfer.png", 0x0000000000008180, 1, "demo", "users", 11546, 1.1742624e9)
    SFTP.StatStruct("WinFormClient.png", 0x0000000000008180, 1, "demo", "users", 80000, 1.1742624e9)
    SFTP.StatStruct("WinFormClientSmall.png", 0x0000000000008180, 1, "demo", "users", 17911, 1.1742624e9)
    SFTP.StatStruct("imap-console-client.png", 0x0000000000008100, 1, "demo", "users", 19156, 1.171584e9)
    SFTP.StatStruct("mail-editor.png", 0x0000000000008100, 1, "demo", "users", 16471, 1.171584e9)
    SFTP.StatStruct("mail-send-winforms.png", 0x0000000000008100, 1, "demo", "users", 35414, 1.171584e9)
    SFTP.StatStruct("mime-explorer.png", 0x0000000000008100, 1, "demo", "users", 49011, 1.171584e9)
    SFTP.StatStruct("pocketftp.png", 0x0000000000008180, 1, "demo", "users", 58024, 1.1742624e9)
    SFTP.StatStruct("pocketftpSmall.png", 0x0000000000008180, 1, "demo", "users", 20197, 1.1742624e9)
    SFTP.StatStruct("pop3-browser.png", 0x0000000000008100, 1, "demo", "users", 20472, 1.171584e9)
    SFTP.StatStruct("pop3-console-client.png", 0x0000000000008100, 1, "demo", "users", 11205, 1.171584e9)
    SFTP.StatStruct("readme.txt", 0x0000000000008180, 1, "demo", "users", 379, 1.69512912e9)
    SFTP.StatStruct("winceclient.png", 0x0000000000008180, 1, "demo", "users", 2635, 1.1742624e9)
    SFTP.StatStruct("winceclientSmall.png", 0x0000000000008180, 1, "demo", "users", 6146, 1.1742624e9)
 ]

 walkdirResults = (
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
