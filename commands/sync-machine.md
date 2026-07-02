# /sync-machine — Integrate THIS machine into the GitHub mirroring

Bring the machine you're currently running on into the cross-machine sync that your other machines already use: the **Obsidian vault** (`github.com/<your-username>/<your-vault-repo>`) and the **`~/.claude` config** (`github.com/<your-username>/<your-config-repo>`), both via GitHub `origin/main` as the hub, with **`git merge` as the integration (never a blind overwrite)** and **Obsidian Git** for background auto-sync.

This command is **idempotent and safe to re-run**: already-tracked repos are just pulled; only un-tracked repos get the full adopt. It is **cross-platform** (macOS / Linux / Windows-via-Git-Bash). Run it from the **vault root** (so the current directory is the vault).

> **Bootstrap note (brand-new machine):** this command file lives in `~/.claude/`, so on a machine where `~/.claude` isn't tracked yet it won't appear as a slash command until adopted. Either run the `~/.claude` adopt from `~/.claude/README.md` → "Notes for Claude" first (then `/sync-machine` finishes the rest), or just tell Claude in plain language "sync/adopt this machine" and it will follow the steps below.

---

## Step 0 — Preconditions

1. **Identify OS + shell.** On Windows, the Bash tool must be **Git Bash or WSL**; confirm `git --version` and that `python3 --version` works (if only `python` exists, use that). Use `$HOME`/`~` in all paths — **never** hardcode `/Users/...`, `/home/...`, or `C:\Users\...`.
2. **GitHub auth:** run `gh auth status`. The repos are under **your GitHub account** — confirm it is logged in and active. If not authed, ask the user to run `! gh auth login --web` (interactive — you cannot). Then run `gh auth setup-git` so command-line git (and Obsidian Git on desktop) authenticates non-interactively.
3. **Git identity:** ensure `git config --global user.name` and `user.email` are set (match the other machines — use the same identity everywhere).
4. **Connectivity:** GitHub is the hub, so plain internet is enough. (A mesh VPN like Tailscale is only needed when Claude drives a *remote* machine over SSH — not for the machine it's running on.)

Capture the machine name for safety-branch labels: `MACHINE=$(hostname | tr '[:upper:]' '[:lower:]' | cut -d. -f1)`.

## Step 1 — Adopt each repo (vault + ~/.claude)

Handle **two** repos. For each, use its path and origin URL:

| Repo | Path | Origin URL | Branch |
|---|---|---|---|
| Vault | the current vault root (contains `CLAUDE.md` + `.obsidian/`) | `https://github.com/<your-username>/<your-vault-repo>.git` | `main` |
| Config | `$HOME/.claude` | `https://github.com/<your-username>/<your-config-repo>.git` | `main` |

For each repo, decide the path:

**A) Already a git repo tracking `origin/main`** → just integrate latest:
```
git -C <path> pull --no-rebase origin main
```
- Auto-merges disjoint changes. On a **genuine merge conflict, STOP** and resolve *with the user* — never auto-pick a side. Then continue.

**B) Not a git repo yet (plain files)** → safe, reversible adopt (this is exactly how a prior machine was onboarded):
1. `git -C <path> init -b main && git -C <path> remote add origin <url> && git -C <path> fetch origin`
2. Install the canonical ignore rules so machine-local/secret/cache files are excluded **before** staging:
   `git -C <path> show origin/main:.gitignore > <path>/.gitignore`
3. **Safety snapshot** (makes the whole thing reversible — nothing can be lost):
   `git -C <path> add -A && git -C <path> commit -q -m "<MACHINE> pre-adopt snapshot (safety)" && git -C <path> branch -m ${MACHINE}-pre-adopt`
4. **Assess divergence** before switching:
   `git -C <path> diff ${MACHINE}-pre-adopt origin/main --stat`
   and list files **unique to this machine** (would be lost by a naive checkout):
   `git -C <path> diff ${MACHINE}-pre-adopt origin/main --diff-filter=D --name-only`
   - **`origin` is authoritative for shared files** (it carries the newest shared config/notes) → take origin's version on conflicts.
   - **This machine's unique files** → preserve (re-added in step 6). If they're real, shareable content (e.g. workflow commands/agents), ask the user whether to **push them to the shared repo** so all machines get them.
   - **`settings.json` (config repo only) is special** — it's machine-sensitive. Take **origin's portable** version, and move any machine-local keys (`dangerouslySkipPermissions`, `theme`, hardcoded paths, machine-specific `permissions`) into **`settings.local.json`** (gitignored, stays local). Merge into an existing `settings.local.json` rather than clobbering it.
5. **Clean switch to origin's main** (working tree is clean after the snapshot commit, so **no `-f` needed** — the auto-mode classifier blocks force-checkout on these repos, and it isn't necessary):
   `git -C <path> checkout -b main origin/main`
   (Gitignored machine-local files — `.smart-env/`, `*secrets*`, `.obsidian/`, `settings.local.json` — are untracked and left on disk.)
6. **Restore this machine's unique files** from the snapshot, then commit:
   `git -C <path> checkout ${MACHINE}-pre-adopt -- <file1> <file2> …`
   `git -C <path> add -A && git -C <path> commit -m "Add <MACHINE>-authored files"`
   **Push only with user confirmation** (it adds to the shared repo): `git -C <path> push origin main`.
7. If unique files were pushed, **pull them onto the other machines** too (or note it for their next `/resume`).

> Files were read-only (mode `555`) on at least one machine — if a write is denied, `chmod u+w <file>`, write, then `chmod 555 <file>` to restore.

## Step 2 — Obsidian Git plugin (vault auto-sync)

If `<vault>/.obsidian/plugins/obsidian-git/` is missing, install + configure it (it's gitignored, so per-machine):
1. Download the latest release assets into the plugin dir:
   `gh release download --repo Vinzent03/obsidian-git --pattern main.js --pattern manifest.json --pattern styles.css --dir "<vault>/.obsidian/plugins/obsidian-git" --clobber`
   (omit a tag to get the latest, or pin one).
2. Enable it: add `"obsidian-git"` to `<vault>/.obsidian/community-plugins.json`.
3. Write `<vault>/.obsidian/plugins/obsidian-git/data.json`:
   ```json
   {
     "commitMessage": "vault sync: {{date}}",
     "commitDateFormat": "YYYY-MM-DD HH:mm:ss",
     "autoSaveInterval": 10,
     "autoPushInterval": 10,
     "autoPullInterval": 10,
     "autoPullOnBoot": true,
     "disablePush": false,
     "pullBeforePush": true,
     "syncMethod": "merge",
     "disablePopups": false,
     "showStatusBar": true,
     "refreshSourceControl": true,
     "gitPath": ""
   }
   ```
   On **desktop** Obsidian Git shells out to **system git**, so it uses the credential helper from Step 0 (Git Credential Manager on Windows, osxkeychain on macOS, the `gh` helper on Linux) — **no PAT entry needed**.

## Step 2b — Shared auto-memory (symlink into the vault)

Claude's auto-memory normally lives at `~/.claude/projects/<cwd-encoded>/memory/`, which is **gitignored and per-machine** (the dir name encodes this machine's vault path, so it can't sync as-is). To make memory identical everywhere, it's stored once in the **synced vault** at `<vault>/System/Claude-Memory/` and each machine symlinks its memory path to that.

```
ENC=$(pwd | sed 's#[/_]#-#g')                 # claude encodes the cwd: / and _ both -> -
MEMDIR="$HOME/.claude/projects/$ENC/memory"
TARGET="$(pwd)/System/Claude-Memory"          # synced via the vault repo (already pulled in Step 1)
```

1. **Already wired?** If `[ -L "$MEMDIR" ]` (symlink), it's done — skip.
2. **Merge local memories into the shared store FIRST (never clobber):** if `$MEMDIR` is a real dir, copy any memory files the shared store lacks — `cp -n "$MEMDIR"/*.md "$TARGET"/ 2>/dev/null`. **`MEMORY.md` must be merged by hand** — take the union of the index lines from both (the shared one is authoritative for shared entries). If this machine had genuinely new memories, **commit them to the vault** (with user confirmation) so the other machines get them.
3. **Replace the dir with a symlink** (only after step 2): `rm -rf "$MEMDIR" && mkdir -p "$(dirname "$MEMDIR")" && ln -s "$TARGET" "$MEMDIR"`.
   - **Windows (Git Bash):** native symlinks need Developer Mode; otherwise make a junction from cmd — `cmd //c mklink /J "%USERPROFILE%\.claude\projects\<ENC>\memory" "<win-vault-path>\System\Claude-Memory"`.
4. **Verify:** `readlink "$MEMDIR"` resolves to `<vault>/System/Claude-Memory`, and `head -3 "$MEMDIR/MEMORY.md"` reads the shared index.

## Step 3 — Verify

Confirm, for **both** repos: on `main`, tracking `origin/main`, working tree clean, and local `HEAD` == `origin/main` (after a `git fetch`). Confirm `obsidian-git` is in `community-plugins.json`. Confirm gitignored local files survived (`.smart-env/`, secrets, `settings.local.json`). Optionally run a **round-trip test** (create a marker note → push → pull on another machine → delete → confirm it propagates back).

Report a tight summary: what was taken-from-origin, what was preserved/pushed as machine-unique, and the final synced HEADs.

## Step 4 — Hand-off + cleanup

Tell the user to:
- **Reload Obsidian** on this machine (the plugin won't load until reload/restart), and confirm the sync status in the status bar.
- **Start a fresh Claude session** — `settings.json` + hooks are read once at startup, so the new config/hooks (e.g. session-router, the `/resume`·`/compress` git-sync steps) only take effect next session.
- Offer to **drop the `${MACHINE}-pre-adopt` safety branch(es)** once they've confirmed everything looks right: `git -C <path> branch -D ${MACHINE}-pre-adopt`.
- Update `~/.claude/README.md`'s machine-sync table (mark this machine ✅ synced with today's date) and push.

## Windows-specific reminders

- Bash tool = **Git Bash/WSL**; `python3` may be `python`.
- Credentials: **Git Credential Manager** usually ships with Git for Windows — `gh auth setup-git` wires it; verify a `git -C <path> push --dry-run origin main` authenticates before trusting auto-sync.
- **Verify the hooks actually run** (`usage-guard.sh`, `session-router.sh` are bash + python) — don't assume; see README "Windows caveats".
- Watch for **CRLF** churn — if `git status` shows whole files modified after checkout, set `git config core.autocrlf input` (or add a `.gitattributes`) before committing.

## Invariants

- **Never force-checkout (`-f`) or hard-reset** these repos — always snapshot-then-clean-switch (reversible). The classifier blocks `-f` here anyway.
- **Never overwrite** a machine's unique content — diff first, preserve, and prefer a real merge.
- **Stop for the user on genuine merge conflicts** and on pushing new files to a shared repo.
- **Secrets/machine-state stay local** — `*secrets*`, `.smart-env/`, `.obsidian/`, `settings.local.json` are gitignored; never commit them.
