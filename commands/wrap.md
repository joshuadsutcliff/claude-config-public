# /wrap — Wrap Up & Close the Session

The single end-of-session ritual. Pairs with **`/resume`** (which opens a session). `/wrap` decides which closing actions are actually needed and runs them in the **correct order**, deferring to the existing commands as the source of truth — it only adds the decision + sequencing layer.

It orchestrates three things:
1. **Preserve-check** *(confirm-first)* — surface durable decisions/learnings from this session that belong in long-term memory, and route only the ones you confirm.
2. **Compress** *(almost always)* — write the session log + push the vault.
3. **Sync-config** *(only if `~/.claude` drifted)* — reconcile the shared Claude config repo.

It does **NOT** run `/sync-machine` — that's one-time-per-machine onboarding, not a session-end action. `/wrap` only *detects* an un-onboarded machine and tells you to run it.

**Why this order is fixed (preserve → compress → sync-config):** preserve edits `CLAUDE.md` and depth notes, which live **in the vault**, so they must happen *before* compress pushes the vault. Sync-config touches a **separate repo** (`~/.claude`), so it runs last and independently.

---

## Arguments (optional)

- `/wrap` — full intelligent run.
- `/wrap no-preserve` — skip the preserve-check (still compress + sync-config).
- `/wrap no-config` — skip sync-config even if it drifted.
- Any other text → passed to `/compress` as a **slug hint** for the session-log filename.

## Step 0 — Assess & show a plan (do this first)

Gather the signals, then show the user a one-screen plan **before acting**:

1. **Onboarding guard.** `git -C "$HOME/.claude" rev-parse --is-inside-work-tree` — if `~/.claude` is **not** a git repo, this machine isn't onboarded → tell the user to run **`/sync-machine`**, and skip Step 3 (still allow compress if the vault is a repo). Confirm the vault root is a git repo too.
2. **Config drift** (decides whether Step 3 runs). `git -C "$HOME/.claude" fetch origin`, then `git -C "$HOME/.claude" status --porcelain` (local shareable edits) and `git -C "$HOME/.claude" rev-list --left-right --count HEAD...origin/main` (ahead/behind). **Drift = any local change OR any incoming/outgoing commit** → Step 3 is NEEDED; otherwise SKIP it silently.
3. **Preserve candidates.** Review THIS session for durable knowledge not already captured — standing conventions, permanent decisions, reusable reference material, or rules that supersede something in CLAUDE.md. If none, the preserve-check is a no-op.
4. **Session triviality.** If the session did no substantive work (pure Q&A, nothing changed/decided), compress may be noise — offer to skip rather than logging an empty session.
5. **Skill-evolution check** (see the `skill-evolution` skill). Append any unlogged observations from this session to its observation log. If ≥5 entries are unprocessed, run the evolution pass **inline as part of this wrap**: draft the batch, present it for approval inside the wrap flow, apply what's approved, tick entries — don't defer to a later session. Batch approval remains mandatory; never apply silently. Run it before Step 2 so vault-side changes ride the vault push; config-side changes ride Step 3.

Present it compactly, e.g.:
> **Wrap plan:** ① preserve 1 decision (confirm below) · ② compress → vault push · ③ sync-config (3 local edits to push).

## Step 1 — Preserve-check *(confirm-first)*  — skip if `no-preserve`

- List each candidate durable item with the route it would take (**CLAUDE.md core** / **depth note** / **update-archive**) per the `/preserve` routing table.
- **Get explicit confirmation. Never silently edit CLAUDE.md.** The user may approve all, some, or none, or reword them.
- For each confirmed item, follow the **`/preserve`** procedure (`commands/preserve.md`; you may invoke the preserve skill) to route it correctly.
- These edits land in the vault and will be committed by Step 2.

## Step 2 — Compress  — always, unless trivial + user opts to skip

- Follow the full **`/compress`** procedure (`commands/compress.md`; you may invoke the compress skill): write the session log, verify frontmatter, then commit → pull → push the vault.
- If a slug hint was passed as args, use it for the log slug.
- This push carries any CLAUDE.md / depth-note edits made in Step 1.

## Step 3 — Sync-config  — only if Step 0 found drift; skip if `no-config`, clean, or not onboarded

- Follow the full **`/sync-config`** procedure (`commands/sync-config.md`; you may invoke the sync-config skill): identify the machine (Step 0 there), pull, review outgoing shareable changes (leak-check absolute paths + machine-local keys), confirm, then commit → pull → push `~/.claude`.
- If the onboarding guard tripped, skip and remind the user to run **`/sync-machine`**.

## Step 4 — Combined report

End with one consolidated summary:
- **Preserved:** what was routed where (or "nothing").
- **Compressed:** session-log filename + one-line outcome + vault push status.
- **Config:** commits pulled/pushed, or "clean — skipped".
- **Deferred / blocked:** offline pushes, merge conflicts to resolve, or `/sync-machine` needed.
- Honor the `quick-recap` red/yellow/green status-line convention.

## Invariants

- **Order is fixed:** preserve → compress → sync-config. CLAUDE.md edits must precede the vault push; config is a separate repo, handled last.
- **Confirm before any push and before any CLAUDE.md edit** — `/wrap` aggregates actions across two repos + the always-loaded core, so never act silently on those.
- **Never run `/sync-machine` automatically** — detect-and-advise only.
- **Don't duplicate the sub-procedures** — `commands/compress.md`, `commands/sync-config.md`, and `commands/preserve.md` remain the single source of truth; `/wrap` only adds the decision + ordering layer. If one of them changes, `/wrap` needs no edit.
- **Stop on genuine merge conflicts** in either repo and resolve with the user — never auto-pick a side.
