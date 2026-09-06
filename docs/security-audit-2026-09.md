# Security Audit & Remediation Plan — 2026-09-06

**Repo:** `github.com/ryanbas21/nixos-configuration` (public)
**Scope:** every tracked file, all 135 commits of history, CI workflow, secrets architecture, host hardening posture.
**Status:** PLAN ONLY — nothing below has been implemented. Each phase needs owner sign-off (open decisions listed in Phase 0).

> **Addendum — 2026-09-06, post-review decisions and implementation**
>
> - **F1 downgraded to no-action**: the owner confirmed `ryanbas.com` is a
>   public domain used purely as an email identity — no `git.` subdomain or
>   infrastructure exists behind it, so the repo↔infra correlation concern
>   does not apply. The noreply email switch (part of F6) still landed.
> - **F2 left as-is**: age-encrypting the test identity is circular (the
>   test would need a real key to unlock its own key material); the only
>   non-circular fix is CI-generated ephemeral material — deferred as a
>   larger rework. Current scheme verified safe (test key decrypts only
>   vm-test fixtures; trusted nowhere).
> - **F3 implemented**: sshd auth pinned key-only in `nixos.modules.base`
>   (`PasswordAuthentication = false`, `KbdInteractiveAuthentication =
>   false`, `PermitRootLogin = "prohibit-password"`); stale claim fixed in
>   `docs/programs/security.md`.
> - **F4 implemented via restricted keys, not the `remotebuild`/ssh-ng
>   migration**: `docs/programs/nix-caches.md` documents that `ssh-ng://`
>   pushes are rejected by the remote daemon ("lacks a signature by a
>   trusted key") — a war-story constraint that makes the protocol
>   migration risky to do blind. Instead: the fleet-wide
>   `framework-remote-build` key is now `from="192.168.1.0/24"`-scoped,
>   forwarding-disabled, and forced through a `nixStoreServeOnly` command
>   gate (nix store protocol only, no shell); `desktop-nix-cache-push` is
>   LAN-scoped with no forwarding; `id_borg` remains the one unrestricted
>   admin key. The crown-jewel boundary — no root shell on the signing
>   box from any fleet host — is closed without touching the proven wire
>   protocol. Full `remotebuild` demotion stays available as a follow-up
>   box-side experiment.
> - **F5 implemented**: harmonia's host key pinned in
>   `programs.ssh.knownHosts` (it was already public as the agenix
>   recipient); `accept-new` TOFU replaced with `StrictHostKeyChecking=yes`
>   in both the post-build-hook and nix-daemon NIX_SSHOPTS.
> - **F6 implemented (stop-the-bleed)**: `git.nix` email → GitHub noreply;
>   attacker-useful comment detail trimmed from `secrets.nix`/`nixos.nix`
>   ("passphrase-free", "root can read the 600 file", 1Password-location
>   naming). Existing LAN topology in docs accepted as-is per owner.
> - **Deploy order for these changes**: desktop first (`nixos`), then
>   harmonia (`--target-host`), then framework — so the gated key and the
>   pinned host key are in place before/with the authkeys shrink; pushes
>   that land in the window fail soft (`|| true`) by design. After
>   deploying, verify with `scripts/harmonia-warmth.sh` and one manual
>   `nix copy` (see nix-caches.md "Verify").

---

## 1. Method

- Full-file inventory (94 files) + pattern sweeps: password/passwd/secret/token/api-key/psk/credential/private, password-hash forms (`$argon`, `$y$`, `$6$`), SSH/GPG key material, base64-blob heuristics (≥32 chars).
- Recipient verification: every stanza of every `.age` file checked against `secrets.nix` declarations; test key cross-checked against production secrets.
- Git history: all 135 revisions grepped for secret patterns; deleted files (`scripts/fetch-bootstrap-keys.sh`, `secrets/secrets.nix`) recovered and inspected.
- Host posture: sshd, nftables/firewall, authorized_keys, substituters/trusted-users, agenix identity wiring, disko/LUKS, PAM, USBGuard, CI permissions/triggers/pinning.
- Pinned-nixpkgs source consulted to settle sshd defaults (`174eb78…`).

## 2. Threat model

What this repo must protect, given it is public:

1. **Secret material** — API keys (zai), cache signing keys (harmonia, cachix), borg passphrase, GPG private key, IPTV credentials, ntfy URL+token. All currently age-encrypted; the *private halves* must never exist in the repo or its history.
2. **Infrastructure correlation** — personal domain, LAN topology, service inventory that helps an attacker target the home network or impersonate the owner.
3. **The supply chain** — harmonia signs binaries every fleet host substitutes from, and cachix CI secrets push to a public cache. Compromise of either poisons every machine.
4. **Remote access paths** — sshd on all hosts; the shared fleet push key; the traveling framework laptop on hostile networks.

## 3. Findings

Severity: HIGH = act before next push · MEDIUM = act this week · LOW = hardening · INFO = verified good.

| ID | Sev | Finding | Evidence |
|----|-----|---------|----------|
| F1 | **HIGH** | Personal domain leaked via commit metadata | 4 commits on `main` authored **and** committed as `git@ryanbas.com` (`5e7dddf`, `1d09281`, `b4ade98`, `13ef4e6`). The repo's own rationale for `secrets/ntfy-url.age` is: *"a personal domain name is not something the repo should broadcast (scrapers correlate repo ↔ infrastructure)"*. The domain pattern being protected is broadcast in git metadata. |
| F2 | **HIGH** | Real private key + signing key committed (currently safe, unguarded) | `modules/vm-tests/test-identity` (passphrase-less OpenSSH private key) and `modules/computers/harmonia/test-signing-key.nixkey`. Verified today: only `vm-tests/*.age` carry the `4i/8Lw` stanza; `harmonia-test-1` is trusted nowhere. One future mistake (re-encrypting a production secret "for testing", or reusing the identity) leaks secrets. `.gitignore` (`id_*`, `*.key`) does not match these shapes. |
| F3 | **HIGH** | sshd password-auth posture depends on upstream default the repo's own docs disagree about | `modules/system/base.nix:162` enables sshd with **no** `settings`. `docs/programs/security.md` claims "nixpkgs defaults (…no password auth)"; `modules/computers/harmonia.nix` states the opposite, verified empirically on-box ("upstream default true"). Pinned nixpkgs: `PermitRootLogin` defaults `prohibit-password` (confirmed); `PasswordAuthentication` is **not** defaulted off. The **framework laptop** joins hostile networks with port 22 open (module `openFirewall` default) and a PAM password for batman. |
| F4 | **MEDIUM** | Unrestricted fleet-shared root key on the cache signer | `users.users.root.openssh.authorizedKeys.keys` (harmonia.nix:125–130 + `_remote-builder.nix`) grants **full root shells** to: `desktop-nix-cache-push` (= `~/.ssh/harmonia`, "one key shared by every NixOS host" per bootstrap.md), `id_borg`, and `framework-remote-build` — no `from=`, `command=`, or `no-pty`. Any host compromise (traveling laptop!) → root on the box that signs what every fleet machine substitutes = supply-chain chokepoint. |
| F5 | **MEDIUM** | TOFU (`accept-new`) toward the cache server | `post-build-hook` in base.nix and distributed-builds use `StrictHostKeyChecking=accept-new` to `root@192.168.1.82`. First-connect MITM on the LAN can plant a key. The host key is *already known and committed* (in `secrets.nix`) — TOFU is unnecessary. |
| F6 | **MEDIUM** | Plain-text info disclosure: LAN map + personal identifiers | Full IP inventory (.30 Synology NAS/NUT, .33 media, .39 n8n, .52 framework, .82 harmonia, .183 desktop), usernames (ryan/batman), real Gmail in `modules/batman/git.nix` and 130 commits' author fields, timezone, IPTV stack, UPS model. Also attacker-useful comments: `secrets.nix` notes id_borg is **passphrase-free** and that "root can read batman's 600 file" (nixos.nix). RFC1918 addresses are unreachable from the internet — risk is reconnaissance convenience and correlation, not direct access. |
| F7 | **MEDIUM** | Traveling-laptop posture incomplete | framework: no LUKS (accepted for the desktop, weaker case for a machine that leaves the house), USBGuard written but deliberately not imported (lockout risk), and F3's password-auth exposure. Evil-maid/charger threat is already documented in `_usbguard.nix` as the rationale. |
| F8 | **LOW** | GPG signing identity rests on id_borg | `secrets/gpg.age` = private key `F3EB6A98…` used for commit signing, encrypted to id_borg only. id_borg compromise = forged commit signatures. Its private half lives in 1Password (good) but software-only. |
| F9 | **LOW** | CI secret surface acceptable but worth documenting | `pull_request` (not `_target`), fork PRs see no secrets, `permissions: contents: read`, all actions SHA-pinned. Remaining: collaborators with write access can exfiltrate CACHIX secrets via workflow edits (GitHub's model — write access is already near-root). |
| F10 | **LOW** | No guard against future plaintext under `secrets/` | Nothing prevents a `ntfy-url.txt` or `*.nixkey` sibling from being committed; `.gitignore` patterns miss the shapes this repo actually uses. |
| F11 | **INFO** | Verified clean | See §4. |

## 4. Verified clean (no action)

- **All secrets age-encrypted; recipients audited stanza-by-stanza**: borg-passphrase, zai-api-key, gpg, hypnotix-providers, cachix-auth-token, cachix-signing-key (→ batman `gOu1og`); harmonia-signing-key (→ batman + harmonia `2L5qzg`); ntfy-url (→ batman + harmonia + framework `NAgIaA`). Matches `secrets.nix` exactly. No production secret is encrypted to the committed test key.
- **Git history clean**: all 135 revs scanned — no hashes, no key material, no passphrases ever committed. Deleted `scripts/fetch-bootstrap-keys.sh` fetched keys from 1Password at runtime and held nothing; deleted `secrets/secrets.nix` held only public recipient keys.
- **No password hashes, no LUKS passphrases** in any disko/host file; no secrets in hyprland/nvf/agents/vicinae (blob scan clean); `zai-api-key`, borg passphrase, hypnotix credentials all agenix-routed.
- **CI**: SHA-pinned actions, least-privilege token, fork-safe secret skipping, no `pull_request_target`, evaluator pinned.
- **harmonia**: `PasswordAuthentication = false` explicit, key-only root, nftables scoping `ip saddr 192.168.1.0/24 tcp dport { 22, 5000 }` with sshd's global open disabled, IPv6 dropped, signing key root-only 0400 via LoadCredential.
- **Other**: github.com host key pre-trusted (verified against api.github.com/meta per docs); sudo-rs; wifi MAC randomization (stable); wheel-only trusted-users with documented rationale; borg passphrase via EnvironmentFile; `.gitignore` blocks `id_*`, `*.key`, `*.pem`, `.env*`, `credentials/`; LICENSE is Unlicense (no name).

## 5. Remediation plan

### Phase 0 — decisions needed from owner (blocking)

1. **F1**: Is the ntfy server on `ryanbas.com` or a subdomain of it?
   - If **yes**: treat the domain as public from now on. Security must rest on the access token (it already does — line 2 of the secret) and deny-all auth (verified). Optionally move ntfy to a distinct hostname/domain later. History rewrite to purge the email is possible (`git filter-repo --email-callback`) but high-disruption and diminishing-returns — **not recommended**; commits are already public and scraped.
   - If **no**: still fix the email (below) — the leak stands on its own as correlation material.
2. **F2**: Option A (preferred, no private key in git at all) vs Option B (keep, add guards).
3. **F4**: Tier 1 (restrict options on keys) vs Tier 2 (migrate pushes/builds to `remotebuild` user over `ssh-ng://`).
4. **F6**: Accept-and-stop-the-bleed (recommended) vs parametrize/redact vs history scrub.
5. **F7**: Acknowledge roadmap items (LUKS at next reinstall, USBGuard after on-device policy generation).

### Phase 1 — config hardening (one PR, low risk, immediately mergeable)

- **F3** — in `modules/system/base.nix`, pin explicitly:
  ```nix
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "prohibit-password"; # self-documenting; nixpkgs default
  };
  ```
  Fix the stale claim in `docs/programs/security.md`; align harmonia.nix's comment.
- **F5** — add to `programs.ssh.knownHosts` in base.nix:
  ```nix
  "192.168.1.82".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINtxzFwIX6e97M/y8aeL0qdI1lM7IykhxS49fe99c0b0";
  ```
  Then drop `accept-new` → `yes` in `post-build-hook`/distributed-builds NIX_SSHOPTS.
- **F6 (bleed-stop)** — `modules/batman/git.nix`: `user.email = "18267769+ryanbas21@users.noreply.github.com"`; set the same in local git config for this clone. Trim the two attacker-useful comments (passphrase-free, root-reads-file) from `secrets.nix`/`nixos.nix` — move operational notes to `docs/secrets.md` if needed.
- Verify: `nix flake check` + the existing vm-tests (they boot real hosts; sshd change is asserted by eval).

### Phase 2 — harmonia access architecture (F4)

- **Tier 1 (quick)**: prefix all three root keys with
  `from="192.168.1.0/24",no-pty,no-agent-forwarding,no-port-forwarding,no-X11-forwarding`.
  Keep `id_borg` as the full-shell admin path; the push/build keys get `command="/usr/bin/env nice -n20 nix-store --serve --store /nix/store"`-style forced handlers.
- **Tier 2 (target state)**: pushes via `nix copy --to ssh-ng://remotebuild@192.168.1.82`; add `remotebuild` to harmonia's `nix.settings.trusted-users` (it is already a declared system user with 64 build users); root authorized_keys shrinks to `id_borg` only.
- Deploy order: harmonia first (add remotebuild path), then desktop/framework hook+buildMachines change, then remove root keys. Test with `scripts/harmonia-warmth.sh` (a successful push+serve round-trip is its exact purpose).
- The vm-test (`harmonia/vm-test.nix`) must be updated in the same PR — it asserts the current key layout.

### Phase 3 — repo hygiene automation (F2, F10)

- **F2 Option A (preferred)**: delete `test-identity` from git; commit only throwaway *plaintext* fixture values (they are fake today); CI job generates an ephemeral keypair, `rage`-encrypts fixtures to it, and points `activationSecrets.*` at the result before running vm-tests. Zero private-key bytes in history going forward. (History still contains the old throwaway key — acceptable, it decrypts nothing but old test fixtures.)
- **F2 Option B (if A is too invasive)**: keep the scheme; add a `checks` output / pre-commit hook that fails if (a) any `secrets/*.age` contains the test identity's stanza prefix (`4i/8Lw`) or public key, (b) `harmonia-test-1` appears in any `trusted-public-keys`.
- **F10**: hook/gitignore forbidding new non-`.age` files under `secrets/` and new `*.nixkey`/`*identity*` files anywhere outside `modules/vm-tests/`+`modules/computers/harmonia/`.

### Phase 4 — roadmap (schedule, don't block)

- **F7**: generate USBGuard policy on the laptop per `_usbguard.nix` runbook, import, verify fingerprint+password fallback; plan LUKS for framework's next reinstall (disko change + `_hardware` by-partlabel contract already makes this clean).
- **F8**: move GPG signing to a hardware token (YubiKey) so `gpg.age` becomes a backup, not the live key.
- **F9 (optional)**: move CACHIX_* secrets into a GitHub *environment* with required reviewers.
- **F1 (optional)**: `git filter-repo` email rewrite if the owner ever wants history scrubbed anyway — requires force-push + all clones re-based; coordinate.

## 6. What this plan deliberately does NOT do

- No history rewrite by default (F1/F6) — public commits are already scraped; the durable fix is stopping new disclosure and not depending on domain secrecy.
- No LUKS migration of a live disk (F7) — data-loss risk outweighs the audit finding; next reinstall is the correct window.
- No secret rotation required — nothing examined indicates any secret's *ciphertext* is compromised (all leaks are metadata, not material).
