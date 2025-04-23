# Troubleshooting

## Request Error -5

```
RequestError: Failure establishing ssh session: -5, Unable to exchange encryption keys while requesting...
```

__Solution:__

Try and upgrade to Julia 1.9.4. It seems to be a bug in an underlying library.

If it does not work, check your `known_hosts` file in your `.ssh` directory. `ED25519` keys do not seem to work.

__Use the `ssh-keyscan` tool:__

From command line, execute: `ssh-keyscan [hostname]`. Add the `ecdsa-sha2-nistp256` line to your
`known_hosts` file. This file is located in your `.ssh` directory. This is directory is located 
in `C:\Users\{your_user}\.ssh` on Windows and `~/.ssh` on Linux and Mac.

## Note: Setting up certificate authentication

To set up certificate authentication, create the certificates in the `~/.ssh/id_rsa` and
`~/.ssh/id_rsa.pub` files. On Windows these are located in `C:\Users\{your user}\.ssh`.

Then use the function  `sftp = SecureFTP.Client("sftp://mysitewhereIhaveACertificate.com", "myuser")`
to create a `Client` type.

### Example files

`known_hosts`:

`mysitewhereIhaveACertificate.com ssh-rsa sdsadxcvacvljsdflsajflasjdfasldjfsdlfjsldfj`

`id_rsa`:

```
-----BEGIN RSA PRIVATE KEY-----
.....
cu1sTszTVkP5/rL3CbI+9rgsuCwM67k3DiH4JGOzQpMThPvolCg=

-----END RSA PRIVATE KEY-----
```

`id_rsa.pub`:

```
ssh-rsa AAAAB3...SpjX/4t Comment here
```

After setting up the files, test using your local sftp client:

`ssh myuser@mysitewhereIhaveACertificate.com`
