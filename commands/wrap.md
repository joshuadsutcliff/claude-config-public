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
- `/wrap --quick` — skip preserve-check, write a minimal 15-line session log
  (no raw-log section, no learnings/errors/setup sections — just
  frontmatter + quick reference + files modified + pending tasks), push, done.
  Use for sessions where the full template would be mostly empty sections.
  Does NOT skip sync-config if drift exists.
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

## Step 1b — Credential write-back to the hub machine (non-hub machines only)

If your setup uses a hub-machine architecture (one always-on machine holding
the single canonical secrets note in its vault, with other machines
reading/appending it over SSH — see the `efficient-fable` secrets rule),
and this session used, received, or discovered any credentials that aren't
already in that canonical note, push them back now so the central source of
truth stays current. Skip this step entirely if your setup has no such hub.

**When to fire:** only when ALL of these are true:
- This machine is NOT the hub machine (the hub writes locally — no SSH needed)
- The conductor received or used a credential this session that it read from
  the user directly (not from the secrets note)
- The credential is reusable (not a one-time token or session cookie)

**How:**
1. Format the new credential(s) as a markdown block:
   ```
   ## [Service/Host Name] (added YYYY-MM-DD from [machine-name])
   - [credential-type]: [value]
   - [access-notes if relevant]
   ```

2. Append to the hub's canonical secrets note via SSH:
   ```bash
   ssh <hub-alias> 'cat >> <vault>/path/to/private-secrets-note.md'
   ```
   Pipe the formatted block into that command.

3. Verify the append landed:
   ```bash
   ssh <hub-alias> 'tail -5 <vault>/path/to/private-secrets-note.md'
   ```

**Hard rules:**
- Use `cat >>` (append), NEVER `cat >` (overwrite). Overwriting would
  destroy all existing credentials.
- Never store credentials in a non-hub machine's vault. The local vault has
  NO secrets note — the hub is the only copy.
- If SSH to the hub fails (VPN/tailnet down, machine unreachable), report
  the new credentials to the user in the wrap summary and flag them as
  "NOT YET WRITTEN TO THE HUB — add manually or retry next session."
- On the hub machine itself, this step is a no-op (skip entirely).
- Only write genuinely new credentials. If the credential was read FROM the
  secrets note this session, it's already there — don't re-append duplicates.

**Skip if:** no new credentials were used this session (the common case —
most sessions don't introduce new credentials).

## Step 2 — Compress (delegated assembly)  — always, unless trivial + user opts to skip

The session log is mechanical assembly, not judgment — delegate it.

1. **Conductor writes a bullet brief (inline, ~10 lines):** date, slug,
   project, topics, outcome (1 sentence), decisions (bullets), learnings
   (bullets), files modified (paths), pending tasks (carried forward). This
   is the judgment step — deciding what matters.

2. **Delegate to a Sonnet worker (effort: low):** pass the brief + the
   session-log template (from `commands/compress.md` Step 2) and instruct:
   "Assemble this into a complete session log file. Follow the template
   exactly. Return the full file content."

   Worker dispatch: `model=sonnet, effort=low, subagent_type=code-generator` —
   the template is fully specified; low effort prevents the worker from
   overthinking the assembly.

3. **Conductor reviews** the returned file (~30s scan): frontmatter valid,
   outcome line accurate, no fabricated content, slug is good. Fix any errors
   inline (one-off edit exemption).

4. **Save and push:** write the file, git add/commit/push per the existing
   Step 5 of compress.md.

**Why this works:** the expensive part of `/wrap` is the conductor's OUTPUT tokens
writing a 60-line file. By delegating the write to a cheaper model (which costs
much less per output token and doesn't consume the conductor model's own weekly
cap), the conductor's cost drops to ~10 lines of bullet brief + a short review
scan. The worker's cost comes from the pooled budget, not the conductor's cap.

**Fallback:** if the delegated worker is unavailable (burn too high, spawn denied),
the conductor writes the log inline as before — this is the degraded path, not
the default.

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
