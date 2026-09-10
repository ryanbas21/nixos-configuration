# Identity

[← program notes](index.md) · modules: `batman/git.nix`, `batman/gh_cli.nix`, `batman/ssh.nix`, `batman/agenix.nix`, `batman/gpg.nix`

Who the machine says you are: git identity, commit signing, and the SSH
keys each concern uses.

## Git (`batman/git.nix`)

Everywhere (`home.base`):

- identity: `ryan bas <ryanbas21@gmail.com>`; `init.defaultBranch =
  "main"`;
- **signing by default** — `signing.key` pins the signing **subkey**
  fingerprint (`0818A0D4E91914B4265FD243D1ADFE3B04FA3CE2`, rsa4096,
  2026-09-09), `signByDefault = true`; the primary secret never
  touches a host (see GPG below), so every signature comes from the
  subkey — rotating it means updating the fingerprint here;
- `pull.rebase` + `rebase.autoStash` (rebase-style pulls, dirty tree
  tolerated);
- `push.autoSetupRemote` (no more `--set-upstream` on new branches);
- aliases: `co`, `st`, and `sync = !git pull --rebase && git push`.

## GPG: subkey-only signing (`batman/gpg.nix`)

Both the keyring delivery and the signing policy are repo state.

- **Delivery** — the secret key material is in the repo, encrypted
  (`secrets/gpg.age`, agenix recipient `id_borg`). On every
  activation the hook decrypts it **inline** (rage +
  `~/.ssh/id_borg` — not the agenix runtime dir, which does not exist
  during first-boot activation) and `gpg --import`s it if the
  fingerprint is not already in the keyring; `gpg
  --import-ownertrust` pins ownertrust `6` (ultimate) — idempotent,
  so a fresh system shows clean "good signature" checks with zero
  manual `gpg --edit-key` steps (GnuPG ≥ 2.4 requires the full
  40-char fingerprint; the 16-char ID is rejected). A legacy cleanup
  removes `~/.gnupg/private-key.asc` from the pre-inline-decrypt
  revision of this module.
- **Enforcement, layer 1 — by construction** — `gpg.age` holds
  `gpg --export-secret-subkeys` output: the signing subkey's secret
  plus a gpg-agent **stub** for the primary (`sec#` in `gpg -K`).
  The real primary secret lives only in 1Password. No host — not
  even one that leaks its keyring AND the repo — can produce a new
  primary-key signature.
- **Enforcement, layer 2 — by assertion** — `assertGpgSubkeyOnly`
  runs after every activation: the primary's `--with-colons` sec
  line must carry flag `#` (stub); `+` (real material) aborts the
  switch with instructions. A mistaken full-key `--export-secret-keys`
  in `gpg.age`, or a manual full-key import on any host, is caught
  at the next activation instead of silently re-arming the primary.
- The fresh-boot VM tests assert the same contract on a committed
  throwaway key of the same shape (cert-only primary + `[S]` subkey,
  exported subkeys-only — see the regeneration recipe in
  `modules/vm-tests.nix`).

### Runbook: subkey-only migration / key rotation

One-time, from a machine holding the full key (passphrase prompts
are interactive — that is the point):

```bash
FPR=BEB93A0F2837F4D1CCDDF341F3EB6A9821002B2C

# 1. dedicated signing subkey
#    (skip on rotation: the subkey already exists)
gpg --quick-add-key "$FPR" ed25519 sign never

# 2. demote the primary to certify-only: change-usage with nothing
#    selected edits the PRIMARY; toggle S off, then Q, then save.
#    Old signatures stay valid (the old self-signature is kept —
#    never re-export with export-options export-minimal).
gpg --edit-key "$FPR"

# 3. refresh the 1Password copy of the FULL secret — from here on
#    it is the only place the primary's secret exists
gpg --export-secret-keys -a "$FPR" | <store in 1Password>

# 4. replace the repo secret's plaintext with the SUBKEYS-ONLY export.
#    Piping makes agenix -e non-interactive (EDITOR becomes
#    "cp /dev/stdin") — verified against a throwaway rules file.
#    NOTE: agenix -r would NOT work: it re-encrypts the OLD plaintext
#    to the current recipients and takes no new content.
gpg --export-secret-subkeys "$FPR" | agenix -e secrets/gpg.age
# sanity: 1 = stubbed primary (good); 0 = full export (do not proceed)
nix shell nixpkgs#rage -c sh -c 'rage -d -i ~/.ssh/id_borg secrets/gpg.age' \
  | gpg --list-packets | grep -c gnu-dummy

# 5. delete the full key BEFORE switching, or the (correct) stub
#    assert fails the activation on purpose
gpg --delete-secret-and-public-key "$FPR"

# 6. switch — activation imports the stub, re-pins ownertrust,
#    asserts '#'
just rebuild nixos        # desktop; just rebuild framework on the laptop

# 7. every OTHER desktop-style host: delete the full key there too
#    (step 5), then rebuild — the stub import is automatic.
```

## SSH keys: one key per purpose

| Key | Purpose | Declared in | Private half |
|---|---|---|---|
| `~/.ssh/id_borg` | agenix identity — decrypts every secret | `batman/backup.nix` (identityPaths), `secrets.nix` (recipient) | 1Password |
| `~/.ssh/git` | GitHub pushes (git + gh over ssh) | `batman/ssh.nix` | 1Password |
| `/root/.ssh/id_ed25519` | harmonia cache push (runs as root) | `system/base.nix` post-build-hook comment | 1Password |

Why `id_borg` and `git` are separate: the agenix identity only ever
needs to decrypt on this machine; the push key is the one that
authenticates to GitHub constantly (manual pushes, `gh` over ssh).
Compromise of one doesn't grant the other.

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
