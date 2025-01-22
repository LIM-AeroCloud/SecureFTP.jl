# Julia SFTP Client 

Package for working with SFTP in Julia. Built on Downloads.jl, but in my opinion much easier to use. Downloads.jl is in turn based on Curl. 

The Julia SFTP client supports username/password as well as certificates for authentication. 

The following methods are supported: readdir, download, upload, cd, rm, rmdir, mkdir, mv, sftpstat
(like stat)



[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://LIM-AeroCloud.github.io/SFTP.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://LIM-AeroCloud.github.io/SFTP.jl/dev/)
[![Build Status](https://github.com/LIM-AeroCloud/SFTP.jl/actions/workflows/CI.yml/badge.svg?branch=dev)](https://github.com/LIM-AeroCloud/SFTP.jl/actions/workflows/CI.yml?query=branch%3Adev)
[![Coverage](https://codecov.io/gh/LIM-AeroCloud/SFTP.jl/branch/dev/graph/badge.svg)](https://codecov.io/gh/LIM-AeroCloud/SFTP.jl)

 

Examples:
```

    using SFTP
    sftp = SFTP.Client("sftp://test.rebex.net/pub/example/", "demo", "password")
    files=readdir(sftp)
    # On Windows, replace this with an appropriate path
    downloadDir="/tmp/"
    download.(sftp, files, downloadDir=downloadDir)

    statStructs = statscan(sftp)

```
   
  
    
```
    #You can also use it like this
    df=DataFrame(CSV.File(download(sftp, "/mydir/test.csv")))
    # For certificates you can use this for setting it up
    sftp = SFTP.Client("sftp://mysitewhereIhaveACertificate.com", "myuser")
    # Since 0.3.8 you can also do this
    sftp = SFTP.Client("sftp://mysitewhereIhaveACertificate.com", "myuser", "cert.pub", "cert.pem") # Assumes cert.pub and cert.pem is in your current path
    # The cert.pem is your certificate (private key), and the cert.pub can be obtained from the private key.
    # ssh-keygen -y  -f ./cert.pem. Save the output into "cert.pub". 

```

[API Documentation](https://stensmo.github.io/SFTP.jl/stable/reference/)
