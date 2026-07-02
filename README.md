# claude-config — Enforced Runtime

A portable, public [Claude Code](https://claude.com/claude-code) configuration. The repo
*is* `~/.claude/` on each machine, tracking only an allowlisted, non-secret slice.

Its distinguishing idea: **turn agent-operation conventions into executable enforcement.**
Most operating frameworks document how an agent *should* behave (token discipline, routing,
delegation) and trust it to comply. This one wires those rules into **hooks** — the agent is
*blocked* from the failure mode, not merely *asked* to avoid it. An unbounded fan-out can
silently spawn many expensive subagents and exhaust a usage window quickly; the guard hook
makes that limit mechanical rather than aspirational.

Start with **`AGENT.md`** (the operating contract), then **`_index.md`** (asset registry) and
**`docs/ARCHITECTURE.md`** (the layered design).

---

## Obsidian + Claude quick start

This repo also documents a full **Obsidian-vault-as-memory-backend** workflow — session
lifecycle (`/resume` → work → `/wrap`), frontmatter-driven surfacing, daily/weekly notes, project
scaffolding, and more. If you want that:

1. Clone this repo (or point an existing Claude Code session at it).
2. Tell Claude: *"Read `docs/OBSIDIAN-SETUP.md` and integrate this into my setup."*
3. Claude will walk through copying commands/skills/agents/hooks into `~/.claude/`, wiring
   `settings.example.json`, scaffolding your vault folders, and adapting
   `templates/CLAUDE.vault.example.md` into your vault's own `CLAUDE.md` — asking you for your
   real paths/usernames along the way.

See `docs/OBSIDIAN-SETUP.md` for the full guide, including which pieces (multi-machine sync,
usage-guard, session-router) are optional.

---

## What's here

| Path | Contents |
|---|---|
| `AGENT.md` | Root operating contract — conductor/worker model + enforcement layer. |
| `_index.md` | Registry of every tracked asset. |
| `hooks/` | `usage-guard.sh` (usage-cap + conductor-model enforcement), `session-router.sh` (LIGHT/MEDIUM/HEAVY tier router), `post-compact.sh` (re-grounds the model after auto-compaction). |
| `agents/` | Named delegation workers: `researcher`, `code-generator`, `tester`, plus `code-reviewer` (reviews completed work against its plan). |
| `commands/` | Session lifecycle: `/compress`, `/preserve`, `/resume`, `/wrap`, `/goal`. Vault workflow: `/sync-config`, `/sync-machine`, `/daily-note`, `/inbox-process`, `/meeting-note`, `/new-project`, `/weekly-review`. |
| `skills/` | Hand-authored cognitive-technique skills (auto-invoked): parallel-lens-synthesis, consequence-simulation, detached-judgment, pressure-test, nod-protocol. Also vendored upstream skills: `efficient-fable`, `quick-recap`, `stay-within-limits` (see "Skills" below). |
| `workflows/` | `phased-review.js` — capped, usage-gated spec-drift review. |
| `settings.example.json` | Shared hook wiring + `effortLevel` baseline. |
| `docs/` | `ARCHITECTURE.md` (the layered design), `goal-loop-engineering.md` (Goal Contracts + Loop Specs), `OBSIDIAN-SETUP.md` (Claude-facing integration guide for the vault workflow). |
| `templates/` | `CLAUDE.vault.example.md` — fill-in-the-blanks vault-level CLAUDE.md. |

## Skills

The 5 hand-authored cognitive-technique skills in `skills/` (parallel-lens-synthesis,
consequence-simulation, detached-judgment, pressure-test, nod-protocol) are **included** here
(adapted from Compound AI Operating Standards, CC BY 4.0). They auto-invoke based on their
`description`.

Three more skills are **vendored** from the upstream Claude Code skills distribution — copied in
full (including assets), marked with a provenance comment in each README, and may drift from
upstream over time:

- `efficient-fable` — conductor/worker delegation design.
- `quick-recap` — the 🟢/🟡/🔴 status-line convention.
- `stay-within-limits` — usage-aware pausing across work waves.

`visual-plan` and `visual-recap` (interactive plan/diff visualizations) remain **external** —
install them separately via Claude Code's plugin system; they are not redistributed here.

## Try it

```bash
git clone https://github.com/<your-username>/claude-config-public.git ~/claude-config-demo
# Inspect AGENT.md + hooks/. To actually run the hooks, wire settings.example.json
# into a ~/.claude/settings.json and restart Claude Code (hooks read once at startup).
```

The hooks are **bash + `python3`**. On Windows, run under Git Bash or WSL and confirm
`python3 --version` resolves (it's often just `python`). Hooks use `~`/`$HOME` only — no
absolute user paths. Per-machine values belong in a gitignored `settings.local.json`.

---

## ⚠️ Secrets policy (for anyone forking this layout)

This repo **must never contain secrets, credentials, or conversation history.** The intended
`.gitignore` is allowlist-style (ignore everything, re-include only safe paths) so that the
following are *never* committed: `~/.claude.json`, `.credentials.json`, auth caches,
`projects/` · `sessions/` · `history.jsonl` (transcripts), local caches/telemetry/backups, and
`settings.local.json` (the per-machine override layer). Before every commit, verify nothing
sensitive is staged.

## Provenance

This repo carries a SHA256 integrity manifest so anyone can confirm a copy is unmodified
(and detect forks). Regenerate it after changing any tracked file, and verify a clone with:

```bash
python3 scripts/build-manifest.py     # writes scripts/manifest.json + scripts/manifest.sha256
python3 scripts/verify-integrity.py   # re-hashes the tree; exits non-zero on any drift
```

## License & provenance

This is a public, scrubbed export of a personal configuration, shared for comparison and
reuse. No warranty. Adapt the vault-shaped commands (`/compress`, `/preserve`, `/resume`) to
your own memory backend — they assume a notes-vault-style long-term store.
