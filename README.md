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

## What's here

| Path | Contents |
|---|---|
| `AGENT.md` | Root operating contract — conductor/worker model + enforcement layer. |
| `_index.md` | Registry of every tracked asset. |
| `hooks/` | `usage-guard.sh` (usage-cap + conductor-model enforcement), `session-router.sh` (LIGHT/MEDIUM/HEAVY tier router). The enforcement layer. |
| `agents/` | Named delegation workers: `researcher`, `code-generator`, `tester`. |
| `commands/` | Slash commands: `/compress`, `/preserve`, `/resume`. |
| `workflows/` | `phased-review.js` — capped, usage-gated spec-drift review. |
| `settings.example.json` | Shared hook wiring + `effortLevel` baseline. |
| `docs/ARCHITECTURE.md` | The 6-layer design and how each layer enforces. |

## Installed skills (external — referenced, not vendored)

These are installed via Claude Code's plugin system and managed/overwritten upstream, so they
are **not** redistributed here. Install them separately:

- `efficient-fable` — conductor/worker delegation design.
- `quick-recap` — the 🟢/🟡/🔴 status-line convention.
- `stay-within-limits` — usage-aware pausing across work waves.
- `visual-plan`, `visual-recap` — interactive plan/diff visualizations.

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
