# /sync-config — Reconcile ~/.claude config with the shared repo

Keep the Claude Code config (`~/.claude` → **your config repo**, e.g. `github.com/<your-username>/<your-config-repo>`, `origin/main` as the hub) **identical across all your machines** (e.g. a laptop, a Linux desktop, a Windows box). This fills the gap that the vault's auto-sync covers but config does not:

- **Vault** syncs both ways automatically (Obsidian Git + `/resume` pull + `/compress` push).
- **`~/.claude` config** is only *pulled* by `/sync-machine`, and is **never pushed by `/compress`** — so config edits made on one machine otherwise sit unshared. **This command is the recurring two-way reconcile for config.**

Run it from anywhere; it operates on `~/.claude` regardless of the current directory. It is **idempotent, cross-platform, and review-first** — it shows what would move before pushing, and never commits machine-local or secret files. For first-time onboarding of a brand-new machine (full adopt + Obsidian Git), use `/sync-machine` instead; use this one for ongoing config sync.

---

## Step 0 — Identify THIS machine (always report it)

Config is shared, but each machine differs (shell, python, paths, credential helper) and some keys are deliberately machine-local. Detect and **state which machine you're on** so later path/shell decisions are correct. From the Bash tool:

```bash
UNAME="$(uname -s 2>/dev/null || echo unknown)"
HOST="$(hostname 2>/dev/null | tr '[:upper:]' '[:lower:]' | cut -d. -f1)"
case "$UNAME" in
  Linux)               M="your-linux-hostname"; NOTE="fill in: login shell, whether a shell-commands plugin needs a bash override, python3 path, \$HOME";;
  Darwin)              M="your-macbook-hostname"; NOTE="zsh; osxkeychain credential helper; python3; \$HOME=/Users/<you>";;
  MINGW*|MSYS*|CYGWIN*) M="your-windows-hostname"; NOTE="Bash tool = Git Bash; python may be 'python'; watch CRLF (git config core.autocrlf input); \$HOME=C:\\Users\\<you>; hooks need python+bash to actually run";;
  *)                   M="UNKNOWN";               NOTE="verify shell/python/paths before trusting them";;
esac
printf 'Running on: %s  [uname=%s host=%s]\n  Caveat: %s\n' "$M" "$UNAME" "$HOST" "$NOTE"
```

> **Why this matters / the caveat:** if two of your machines are the same physical box dual-booting Linux and Windows, they may share the `hostname`, so **`uname -s` is the reliable discriminator** (`Linux` vs `MINGW*`), not hostname alone. Lead any path/shell/python decision in the session with this result. Anything machine-specific (theme, `dangerouslySkipPermissions`, hardcoded paths, machine-only permissions) belongs in **`settings.local.json`** (gitignored), never in the shared `settings.json`.

## Step 1 — Preconditions

- `gh auth status` shows **your GitHub account** active; if not, ask the user to `! gh auth login --web`, then `gh auth setup-git`.
- `git -C "$HOME/.claude" rev-parse --abbrev-ref HEAD` is `main` tracking `origin/main`. If `~/.claude` isn't a git repo yet, this is a fresh machine → stop and tell the user to run **`/sync-machine`** first.
- Always use `git -C "$HOME/.claude" …` (per CLAUDE.md git pattern — no `cd …&&`).

## Step 2 — Pull latest (incoming review)

```bash
git -C "$HOME/.claude" fetch origin
git -C "$HOME/.claude" log --oneline HEAD..origin/main   # what's incoming
git -C "$HOME/.claude" pull --no-rebase origin main
```
- Auto-merges disjoint changes. **On a genuine merge conflict, STOP** and resolve *with the user* — never auto-pick. Hooks/commands are plain files; conflicts are readable.

## Step 3 — Review local changes for sync (outgoing review)

This is the core "reviewed for sync" step — classify before pushing.

```bash
git -C "$HOME/.claude" status --porcelain      # tracked edits + shareable untracked files
```
The `.gitignore` is an **allowlist**: only `README.md`, `settings.json`, `hooks/**`, `agents/**`, `commands/**`, `workflows/**` are tracked; everything else (transcripts, history, `settings.local.json`, `*.local.json`, `*secret*`, `*credential*`, `*token*`) is ignored. So `git status` surfaces exactly the **shareable** changes.

1. **Show the user the diff** of what would be pushed:
   `git -C "$HOME/.claude" diff` (and `git -C "$HOME/.claude" diff --stat` for the summary).
2. **Leak check (important):** scan the shareable changes for machine-specific content that must NOT go to the shared repo:
   - absolute paths: `git -C "$HOME/.claude" diff | grep -nE '/home/[^/]+|/Users/|C:\\\\Users'`
   - machine-local keys landing in `settings.json` (`dangerouslySkipPermissions`, `theme`, machine-only `permissions`).
   If found, move them to `settings.local.json` and exclude from the commit. **Flag and pause** — don't push leaks.
3. **Confirm with the user** before pushing (it changes shared config for all machines), unless the change is trivially obvious and the user already asked to push.

## Step 4 — Commit + push

```bash
git -C "$HOME/.claude" add -A          # .gitignore protects local/secret files
git -C "$HOME/.claude" commit -m "config: <concise description of what changed>"
git -C "$HOME/.claude" pull --no-rebase origin main    # pull-before-push so concurrent edits merge
git -C "$HOME/.claude" push origin main
```
- Skip commit if nothing staged. If a write was blocked by read-only mode (`555` on some machines): `chmod u+w <file>`, edit, then `chmod 555 <file>`.
- **No remote / offline:** commit locally, note the push is deferred.

## Step 5 — Verify + report

- `git -C "$HOME/.claude" fetch` then confirm local `HEAD` == `origin/main`, working tree clean.
- Report: **machine** (Step 0), commits **pulled**, commits **pushed**, and any files held back as machine-local.
- **Reminder:** `settings.json` + hooks are read **once at session start** — config changes pulled/edited now take effect only in a **new** Claude session. Commands/skills are picked up without restart.

## Invariants

- **Lead with the machine identity (Step 0)** — it governs every path/shell/python choice afterward.
- **Never commit secrets or machine-local files** — `*secret*`, `*credential*`, `*token*`, `settings.local.json`, `*.local.json`, transcripts/history are gitignored; keep it that way.
- **`settings.json` is portable-only** — machine-specific keys live in `settings.local.json`.
- **Never force-push / hard-reset**; **stop on genuine merge conflicts** and resolve with the user.
- This is **config only**. The vault is handled by `/resume`/`/compress`/Obsidian Git — don't touch it here.
