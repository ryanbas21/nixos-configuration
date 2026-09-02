# Secrets & agenix

[← README](../README.md) · [Bootstrap](bootstrap.md) · [Identity](programs/identity.md)

Secrets are encrypted with agenix and committed to this repository. The
encrypted `.age` files are safe to store in Git; the private keys used to
decrypt them are never stored in the repository.

The recipient key declared in `secrets.nix` is batman — the desktop's
`~/.ssh/id_borg`: the user-level agenix identity, it decrypts every
secret. Its private half is backed up in 1Password, so a machine-plus-NAS
disaster still leaves a recovery path. GitHub pushes use a separate
dedicated key, `~/.ssh/git` (declared in `modules/batman/ssh.nix`) — see
the [key inventory](bootstrap.md#the-key-inventory-the-only-must-restore-items).

## Layout

```
secrets.nix                     recipients (public keys only) — safe to commit
secrets/
├── borg-passphrase.age         user-level (borgmatic, via EnvironmentFile)
├── zai-api-key.age             user-level (fish exports ZAI_API_KEY from it)
├── gpg.age                     user-level (GPG private-key import at activation)
├── cachix-auth-token.age       user-level (cachix CLI + CI secret sync)
├── cachix-signing-key.age      user-level (cachix CLI + CI secret sync)
└── harmonia-signing-key.age    system-level (the cache server's signing key,
                                modules/computers/harmonia.nix)
```

`secrets.nix` contains only public recipient keys and is safe to commit.
The `.age` files contain the encrypted secret material and are also
committed. **Never** commit a private decryption key (for example
`~/.ssh/id_borg`) — `.gitignore` blocks the usual shapes (`id_*`,
`*.key`, `*.pem`, ...).

## Adding a secret

1. Make sure the recipient's public SSH key is present in `secrets.nix`:

   ```nix
   let
     batman = "ssh-ed25519 AAAA... batman@nixos";
   in
   {
     "secrets/example.age".publicKeys = [ batman ];
   }
   ```

2. Create or edit the encrypted secret from the repository root (agenix
   is on the desktop's package list, pinned by the flake input):

   ```bash
   cd /etc/nixos
   agenix -e secrets/<name>.age
   ```

   Enter the plaintext secret in the editor. Agenix encrypts it when the
   editor is closed, using the recipients from `secrets.nix`.

3. Add the encrypted file to Git (see the Git rule below):

   ```bash
   git add secrets/<name>.age
   ```

4. Declare the secret in the home-manager feature that consumes it —
   desktop secrets go in a `home.pc` module (e.g. `modules/batman/agenix.nix`):

   ```nix
   age.identityPaths = [
     "${config.home.homeDirectory}/.ssh/id_borg"
   ];

   age.secrets.<name> = {
     file = ../../secrets/<name>.age;
   };
   ```

5. Consume the decrypted secret through `config.age.secrets.<name>.path`.
   Decrypted secrets land in agenix's per-session runtime dir
   (`/run/user/<uid>/agenix`, tmpfs) — never on disk. For example, a
   systemd service can use it as an EnvironmentFile:

   ```nix
   systemd.user.services.example = {
     Service.EnvironmentFile = config.age.secrets.<name>.path;
   };
   ```

   Or from fish, guarded so standalone machines (which carry no secrets)
   don't error:

   ```fish
   if test -r "/run/user/"(id -u)"/agenix/zai-api-key"
       set -gx ZAI_API_KEY (cat "/run/user/"(id -u)"/agenix/zai-api-key")
   end
   ```

### Important Git rule

The encrypted `.age` file must be Git-tracked because this repository is
a flake. Nix evaluates the flake from its Git source and will reject an
untracked secret file.

It is therefore expected to see `git add secrets/<name>.age` before
rebuilding. The plaintext secret and the private decryption key must
never be added to Git.

## Rotating the identity

If `~/.ssh/id_borg` is ever replaced, every secret must be re-encrypted
to the new public key: update `secrets.nix`, then
`agenix -r` (re-encrypt all files in place) from the desktop holding the
old + new keys, and commit.

## System-level secrets

The harmonia host is the one consumer of system-level agenix (the
NixOS module, not home-manager): its signing key decrypts with the
**host** ssh key (`age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ]`),
so the server needs no user identity. The host's public key is a
recipient in `secrets.nix` (keyscan'd from the LAN), and the real
signing secret is encrypted to it — verified at extraction to derive
exactly the public half pinned in `modules/nixos/base.nix`. See
[nix caches](programs/nix-caches.md#the-server-82--tracked-in-this-repo).
