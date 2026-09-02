# Identity

[← program notes](index.md) · modules: `batman/git.nix`, `batman/gh_cli.nix`, `batman/ssh.nix`, `batman/agenix.nix`

Who the machine says you are: git identity, commit signing, and the SSH
keys each concern uses.

## Git (`batman/git.nix`)

Everywhere (`home.base`):

- identity: `ryan bas <ryanbas21@gmail.com>`; `init.defaultBranch =
  "main"`;
- **signing by default** — `signing.key = "F3EB6A9821002B2C"` (the GPG
  key's long ID; the full fingerprint is
  `BEB93A0F2837F4D1CCDDF341F3EB6A9821002B2C`), `signByDefault = true`;
- `pull.rebase` + `rebase.autoStash` (rebase-style pulls, dirty tree
  tolerated);
- `push.autoSetupRemote` (no more `--set-upstream` on new branches);
- aliases: `co`, `st`, and `sync = !git pull --rebase && git push`.

## GPG: declarative key import (`batman/agenix.nix`, desktop-only)

The GPG **private key itself is in the repo**, encrypted
(`secrets/gpg.age`). On every activation:

- if the key is not already in the keyring, `gpg --import` it from the
  agenix tmpfs path (`/run/user/<uid>/agenix/gpg-private-key` — no
  custom `path`, so the plaintext never touches disk and never rides
  into the borg backup);
- `gpg --import-ownertrust` pins ownertrust `6` (ultimate) — idempotent,
  so a fresh system shows clean "good signature" checks with **zero
  manual `gpg --edit-key` steps**. GnuPG ≥ 2.4 requires the full
  40-char fingerprint here; the 16-char key ID is rejected as "invalid
  fingerprint";
- removes `~/.gnupg/private-key.asc` — leftover of an earlier revision
  of this module that decrypted the key to disk.

## SSH keys: one key per purpose

| Key | Purpose | Declared in | Private half |
|---|---|---|---|
| `~/.ssh/id_borg` | agenix identity — decrypts every secret | `batman/backup.nix` (identityPaths), `secrets.nix` (recipient) | 1Password |
| `~/.ssh/git` | GitHub pushes (git + gh over ssh) | `batman/ssh.nix` | 1Password |
| `/root/.ssh/id_ed25519` | harmonia cache push (runs as root) | `nixos/base.nix` post-build-hook comment | 1Password |

Why `id_borg` and `git` are separate: the agenix identity only ever
needs to decrypt on this machine; the push key is the one that
authenticates to GitHub constantly (and is the one the unattended
git-backup timer uses). Compromise of one doesn't grant the other.

System-side, `programs.ssh.knownHosts` pre-trusts GitHub's host key so
unattended pushes never prompt — see [security](security.md#pre-trusted-github-host-key).

## gh (`batman/gh_cli.nix`)

GitHub CLI, everywhere: enabled with `git_protocol = "ssh"` — so `gh`
clones and pushes over ssh using `~/.ssh/git`, not https credentials.
Authentication itself is interactive, once per machine
(`gh auth login`) — and it's load-bearing beyond gh: the desktop's
[cachix provisioning](nix-caches.md#nix-configs-cachix-the-cache-as-repo-state)
syncs CI secrets via `gh secret set`, and warns loudly until `gh` is
authenticated.
