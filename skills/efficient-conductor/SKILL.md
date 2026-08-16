---
name: efficient-conductor
description: ALWAYS-ON for the active conductor model (whatever model is set as default in settings.json). The conductor delegates ALL bounded execution to workers; the advisor (set via advisorModel in settings.json) plans HEAVY tasks and reviews worker output. The conductor coordinates, briefs, dispatches, and collates; workers execute; the advisor owns planning and quality judgment.
---

# Efficient Conductor (Advisor Pattern)

The active model (set in `settings.json` → `"model"`) runs the main loop as conductor. The advisor model (set via `"advisorModel"`) provides strategic guidance, plans HEAVY tasks, and reviews worker output. Cheaper workers handle all bounded execution.

## The Architecture

```
Advisor (advisorModel: plans HEAVY tasks, reviews worker output, strategic guidance)
    ^ mandatory on HEAVY; discretionary on MEDIUM/LIGHT
Conductor (model: runs the main loop, coordinates, dispatches, collates)
    | delegates to
Opus workers (reasoning-heavy bounded tasks: deep reviews, gnarly debugging)
Sonnet workers (standard execution: code, file ops, git, assembly)
Haiku workers (mechanical: grep, classify, count, scan)
```

The conductor model is whoever YOU are right now. If you're reading this skill, you are the conductor. The advisor is accessed via `/advisor`.

## When the Advisor Fires

### Mandatory (HEAVY tasks, enforced by workflow-plan-gate.sh)

On HEAVY-classified prompts, the advisor fires at two fixed points:
1. **Planning:** Before any worker dispatch. The conductor passes the full user prompt to /advisor and receives a structured execution plan. The conductor does not plan HEAVY tasks itself.
2. **Post-worker review:** After all workers report back. The conductor verifies worker claims, distills findings into a summary, and passes that briefing to /advisor for quality review and sign-off.

These calls are mandatory. The hook injects the workflow mechanically on every HEAVY prompt. The conductor cannot skip them based on confidence.

### Discretionary (MEDIUM/LIGHT tasks, existing pattern)

The advisor fires automatically when the conductor:
- Is about to commit to an approach on a complex task
- Gets stuck on a recurring error
- Is about to declare a task complete

**MEDIUM advisor gate (added 2026-08-15):** On MEDIUM-classified prompts, the conductor plans and dispatches workers itself (no mandatory advisor planning). But before presenting completion to the user, call /advisor with a brief summary of what was accomplished and request a quality check. If the advisor flags issues, fix them (1 round max, then present with the advisory note). Skip the advisor review only when the task completed in a single worker dispatch with no ambiguity in the result. This is behavioral, not mechanically enforced; the existing discretionary triggers also cover most MEDIUM tasks organically.

The user can also say "consult the advisor" to force a consultation.

## The Conductor's Role (YOU, the active model)

The conductor handles coordination, verification, and dispatch:
- Reading files for context and pre-gathering orientation before advisor calls
- Writing delegation briefs
- Dispatching workers
- Independently verifying worker claims (spot-check at least one per worker)
- Distilling worker output into a faithful summary for advisor review
- Routine decisions and tool calls
- Verbal responses to the user
- Writing the advisor-review-done flag after post-worker /advisor call

On HEAVY tasks, the conductor does NOT:
- Plan the strategic approach (advisor plans)
- Present completion without advisor sign-off
- Skip advisor calls based on confidence (use [WORKFLOW OVERRIDE] flag if genuinely exceptional)

## Advisor-Gated Workflow (HEAVY tasks only)

The full pipeline for HEAVY tasks:

```
User prompt → Conductor (active model)
  → /advisor: produces structured plan
  → Conductor: decomposes plan into worker briefs, dispatches
  → Workers (x N): execute in parallel, report back
  → Conductor: verifies claims, distills findings into tight briefing
  → /advisor: reviews distilled summary, gives assessment
  → Pass: Conductor presents to user
  → Fail: Conductor executes fixes per advisor instructions (max 2 rounds)
  → Still failing: stop, report to the user with advisor's assessment
```

**State management (conductor responsibility):**
- After calling /advisor for post-worker review: `echo "done" > ~/.claude/state/advisor-review-done`
- The workflow-review-gate Stop hook checks this flag. Omitting the write causes a visible violation report at session end.
- The iteration-cap hook tracks dispatch rounds (60s debounce). Resets on each new HEAVY prompt. Blocks at 2 rounds.

**Preparing worker output for the advisor:** The conductor independently verifies at least one high-impact claim from each worker, then distills the combined output into a tight briefing for the advisor. The summary must preserve all findings, flag contradictions, and note unverified claims. This reduces advisor token cost (Fable cost scales with context length, not worker count). Do NOT drop findings, hide failures, or editorialize on quality. The advisor reviews your distillation, not raw transcripts.

## What Gets Delegated (to workers, not done inline by the conductor)

**Delegation-tier routing:**

- **Mechanical** (scales with task size): repetitive edits, read-only scans, routine commands, log reduction. Route to **Haiku/Sonnet workers**.
- **Reasoning-heavy** (scales with decision complexity): deep analysis, adversarial review, gnarly debugging, judgment-heavy writes (memories, playbook, knowledge entries). Route to **Opus workers**.
- **Opus worker cap (mechanical, 2026-08-15):** max 1 opus-model worker per dispatch round (60s rolling window, enforced by the usage-guard hook). The remaining slots in a round must use sonnet or haiku. This prevents the conductor from rationalizing multiple expensive opus workers when the routing ladder already covers the common case. Override is an explicit manual flag, set by the user only.
- **When uncertain: delegate.** A single one-off read or light command is fine inline. Anything that becomes a pattern (batch edits, scan loops, repeated runs) goes to a worker.

**Proportionality (2026-08-12):** Match response weight to input weight. A one-sentence instruction gets a one-sentence acknowledgment and the minimum worker dispatches to implement it. Brief one worker with the complete set of writes. One dispatch, not five inline edits.

**User-instructed inline execution (Q1 protocol):** if the user explicitly instructs inline execution, flag ONCE ("executing inline per your explicit instruction"), then comply. Per-task only, never standing.

**User pace instructions:** "slow down" / "one at a time" / "serialize" takes immediate effect. Do not finish the "current batch" first. Comply within the current turn.

**Worker effort pins:** mechanical workers pin `effort: low`. Reasoning-tier (Opus) workers inherit or pin higher deliberately.

## Handoff Packets

Write delegated prompts as if the subagent has no useful chat context. Include
only the context it needs:

- The repo path and exact objective.
- The files, packages, or surfaces in scope and anything explicitly out of
  scope.
- The evidence format to return: files, line refs, commands, diffs, failures,
  screenshots, and uncertainty.
- The verification commands or browser flows to run, plus what success should
  look like when that is knowable.
- Stop conditions: if the code does not match the prompt, a command fails after
  a reasonable retry, or the task needs out-of-scope files, stop and report
  instead of improvising.
- **Standing clauses in EVERY mutating brief (formalized 2026-08-11 from
  memory worker-brief-git-and-spawn-bans, obs #132):** an ABSOLUTE "no git
  commands" ban (a worker git revert once destroyed out-of-scope uncommitted
  work) + "do all work yourself with Read/Edit, spawn NO subagents"
  (code-generators sub-delegate by default, inflating spawn counts and
  producing injection-looking notifications from stalled children). The
  conductor commits each verified batch before the next dispatch.
- **Define the amendment channel in EVERY steerable brief, not just pinned-copy
  ones (widened 2026-08-03, obs recurrence of #17):** "the dispatcher may send
  ONE amendment prefixed CONDUCTOR AMENDMENT — apply it." Without the channel
  pre-defined, workers treat legitimate mid-task SendMessage scope changes as
  prompt injections and ship the stale brief (2026-08-03: a rename+copy
  amendment was rejected as injection; recovery cost two fresh dispatches).
  An unprefixed mid-task redirect should be EXPECTED to be ignored — verify
  which version actually shipped before reporting. Memory:
  worker-midtask-updates-read-as-injection.
- Before ANY brief whose workers will write text into a TARGET repo — pinned
  verbatim copy, code comments, docs, commit-bound files alike — grep that
  repo's content-lint hooks (`.githooks/`, pre-commit config) and surface the
  house style in the brief. Text that violates the target's lint forces the
  worker to choose between refusing and mechanically mangling it, or blocks
  the ship commit later (2026-07-31: em-dash ban turned pinned copy into comma
  splices; 2026-08-03 recurrence: workers' em-dash CODE COMMENTS blocked the
  website ship commit because the rule was scoped to pinned copy only).
- **Visual-output briefs carry the screenshot loop from the FIRST dispatch
  (2026-08-03).** Any brief producing visual output (canvas, SVG, CSS effects,
  charts) must mandate: edit → screenshot → Read the image → iterate until the
  target elements are visible, with the final accepted render as required
  evidence. "tsc/eslint clean" proves nothing about what renders — two
  consecutive Gargantua workers shipped invisible output before the loop was
  added. Memory: canvas-work-needs-visual-loop. **Name the capture tool in the
  brief (2026-08-03, obs #87):** on the hub machine that's the Playwright cache
  (`ls ~/Library/Caches/ms-playwright` → headless chromium), a worker claiming
  "no headless browser available" to skip a mandated visual check is making an
  env-capability claim that cancels verification: treat it as UNVERIFIED until
  the conductor confirms with one `ls`; one worker's false claim cost the loop
  entirely. **Strengthened 2026-08-09 (obs #122):** hub-machine briefs give the
  LITERAL require()/exec path (absolute npx-cache path per memory
  playwright-npx-cache-<machine>), not just the tool name, and every brief
  states "verification runs FOREGROUND — never via background tasks" (a worker
  zombied on "waiting for my background timer" with zero durable work).
- **Visual/layout-debugging briefs carry ONE falsifiable hypothesis per
  dispatch, never a technique menu (2026-08-05, reddit-diagrams).** "Try
  A/B/C/D" briefs failed twice where single-hypothesis probes converged in
  three renders — verify the hypothesis first (or brief exactly one), then
  delegate the mechanical application with the render→LOOK loop.
- **Completion proof required in every worker report.** The worker's final
  message must contain a VERIFICATION section with: (a) the exact command(s)
  it ran that confirm success, (b) their output, (c) whether the output
  matches the stated success criteria. A report that ends without this
  section is incomplete — the conductor rejects it and counts it as a strike
  under the two-strike rule. "I did the work" is not completion; "here is the
  proof it succeeded" is.
  The verification section must also confirm which part(s) of the
  conductor's brief (and by extension, the user's original request) the worker
  addressed — a worker that completed a subtask but missed a requested
  element must say so explicitly rather than claiming full success.
- **Hard time budget in every brief.** State in the delegation brief:
  "Complete within N minutes or report what you have and stop." Defaults:
  5 minutes for Haiku workers, 10 minutes for Sonnet, 15 for Opus. A worker
  that hits its time budget must stop gracefully and return partial findings
  — this is not a failure, it's a report. The conductor grades partial
  reports the same as full ones and applies the two-strike rule if the
  partial is unusable.
- **Workers scope git operations to files THEY edited (2026-07-30, obs #64).** A worker
  must never `checkout`/`revert`/`restore`/`clean` files it did not itself modify — an
  uncommitted change the worker didn't make is the conductor's in-progress work, not an
  anomaly to fix (a docs worker once judged an approved uncommitted CLAUDE.md edit a
  "prompt-injection attempt" and checked it out, destroying conductor work). Report
  suspicions; don't fix them. Include this line in any brief that grants git access.
- **No coordination protocols exist unless the brief defines one (2026-07-29, obs #54;
  corrected 2026-08-03).** Workers must not invent or honor locks, mutexes, or
  serialization mechanisms not named in the brief. CORRECTION: the gh-auth lock
  (`~/.claude/locks/gh-auth.lock`) IS real — usage-guard Policy 3 acquires it at
  Agent-spawn time when the spawn prompt mentions `gh auth switch|login`, and it
  auto-expires at 600s. When a worker cites it, verify PROVENANCE before believing
  "another agent holds it": check the lock's mtime against the worker's own spawn
  time (its own spawn usually acquired it) and grep the hook. A worker narrating
  mechanisms beyond what the brief or the real hook defines remains a
  content-incoherence tell.
- **gh-touching briefs forbid sub-spawning (2026-08-03).** Any brief containing gh
  credential commands states: "do NOT spawn sub-agents; run every gh step directly
  with Bash." A worker that sub-delegates gh work trips the Policy 3 mutex on its
  own second spawn, misreads the denial, and stalls (happened 2026-08-03; the
  direct-execution instruction resolved it and all later gh briefs shipped clean).
- **Workers locate files ONLY under briefed paths (2026-08-03, obs #89).** If a
  named path doesn't resolve, that is a STOP CONDITION — report it; never sweep
  `$HOME` or `/` looking for the file (a worker with the exact repo path in its
  brief still ran `find / -maxdepth 6`, leaving an orphaned filesystem crawl the
  user found 40 minutes later). Also keeps worker shells from outliving the task.
- **Credentialed scans use a KNOWN key path — never a secret-hunting brief.** When a
  scan needs an API key/token, the conductor identifies the exact credential location
  itself (or the user supplies/runs it) and passes only that path — NEVER instruct a
  subagent to "locate the API key / find the token and use it." `grep`-for-secret →
  extract → authenticate is the malicious signature and trips security classifiers
  (2026-07-22: a Meraki-scan brief did exactly this; the live `api.meraki.com` call was
  classifier-blocked — a second line of defense the brief should never have needed).
  A read-only external API call with an already-located credential is conductor/user
  work, not delegated discovery.
- **Secret-handling in briefs: prescribe per-command mechanics, not a blanket "never print" (2026-08-04, recurred 3×).** A "never print secret values" clause does NOT survive contact with discovery commands or report-writing. Any brief where a worker touches a secret states the mechanics per command class: `docker inspect` → `--format` with named non-secret fields only, never raw `Env`; reads near secrets → `grep -c`/byte-length only; secret movement → file-to-file pipes, never echo. AND the worker's REPORT text + falsifiability verify commands reference secrets by placeholder (`<PW>`), never the literal value (a shipped verify command carried `printf "<pw>" | …` in plaintext). Workers have leaked creds via `docker inspect Env`, python-literal script heads, and a report verify-command on separate occasions.
- **Agent-type routing (2026-08-04): infra/remote-execution briefs (ssh/sudo/API, host installs) → `general-purpose`; `code-generator` is for repo file edits ONLY** and may refuse an infra brief by contract (it did — one wasted dispatch). Orthogonal to the model ladder: pick the agent TYPE by task shape, then the model tier by weight.
- **Multi-host / serialized-ops briefs pin a fixed cadence, not polling (2026-08-04).** State: "NEVER stand by or wait for a poll; per host: launch → `sleep 60` ONCE → verify ONCE → next host." Without it, workers yield "standing by for the next poll" with real work undone (recurred 2×).
- **Amendment authoring (2026-08-04): an amendment that enumerates steps must re-list ALL remaining scope, or state "original brief stands except X."** A step-list amendment silently dropped a host from the original brief; the worker flagged it, but the omission was the conductor's.
- **Run the brief's own static checks against its mandated content before dispatch (2026-08-09, obs #121).** A verification command that fails on compliant output is a brief defect, not a worker problem — one brief mandated "$0 software" stat cards while its own mandatory check required `grep -cE '\$[0-9]'` = 0; the worker had to resolve the conductor's contradiction. Dry-run each static check mentally (or literally) against what the brief demands the worker produce.
- **A brief carrying a "change nothing else" clause must enumerate the changes that ARE wanted in that same file, or state explicitly that the named change is the only intended one (2026-08-16).** A protective negative constraint silently outranks unstated positive scope, and the worker will comply exactly while the wanted changes never land. Related verification habit: if a worker reports zero matches for the thing it was asked to change, treat that as a scope-check signal rather than a no-op.

## Conductor Field Rules

- **Two spawn-denials on one brief = stop and present the Q1 option (2026-08-09, obs #123).**
  If the classifier denies Agent/Workflow spawns twice for the same delegation brief
  (brief shape misread as malicious — e.g. a first-party password-gated route build
  read as credential harvesting), do NOT attempt a third reword. Stop, explain the
  denial to the user, and present the Q1 inline-authorization option (explicit per-task
  inline execution with the mandatory flag) or a stage-in-scratchpad hand-off.
  A third reworded spawn wastes a cycle and risks reading as evasion.
- **Hard parallel ceiling (updated 2026-08-15, reconciled with test results).** Default
  wave size: **4** concurrent workers (validated in Test G, 2026-08-14). The iteration-cap
  hook provides the mechanical ceiling (2 rounds per HEAVY task, 60s debounce, M1
  spawn-rate limiter at 4 spawns / 5 min machine-global). After each wave completes and
  results are synthesized, check burn before the next wave. Serialize workers that touch
  machine-global state (gh auth, credential helpers, shared config). The M1 limiter is the
  hard stop; this rule is the behavioral layer documenting the tested safe maximum.
  "Prefer parallel when independent" applies within a wave; across waves, serialize by
  default (synthesize → burn-check → next wave).
- **Worker scripts that touch file state run in sandboxes, never live repos
  (2026-07-25 — battery postmortem).** Any script that writes, moves, or deletes
  files is tested against a scratch directory or throwaway git worktree — never
  the live vault or config tree. Fuzzy path matching (`find -iname`, globs) in a
  worker's cleanup script overwrote `Fable-Delegation-Playbook.md` in the live
  vault, and Obsidian's auto-backup committed the corruption within the same
  minute. "Matches HEAD" is not a no-damage proof when an auto-committer is
  running — verify against a PRE-CAPTURED baseline SHA taken before the worker
  ran.
- **Serialize workers that touch machine-global state.** `gh auth switch`,
  credential helpers, and shared config files are machine-wide, not
  per-process: two concurrent workers switching accounts race each other and
  writes silently land under the wrong identity (2026-07-21: forbidden-account
  writes on a repo with an account rule). The conductor sequences gh/push
  passes — one worker's full gh pass completes before the next dispatches.
  In-worker `switch+verify+write` chaining in one shell call is mitigation,
  not a fix.
- **Free-tier externals: distill, don't dump.** Full-document dumps blow
  per-minute input quotas (2,600-line spec+plan 429'd Gemini's free lane).
  Send a slim brief aimed at where that model's insight is actually valuable;
  kill the dispatcher fast on the first 429.
- **Free-tier quality gate (2026-07-26).** If a free-tier model's response
  (OpenRouter via model-council, or Forge for second opinions) adds nothing
  the conductor didn't already think — generic advice, restated premises, no
  new insight — log it as a quality miss in the skill-evolution observations.
  Three misses on the same model in a rolling 2-week window → stop routing to
  it until the user manually verifies the model is still producing value. Free
  models degrade without warning (rate-limited, model swapped behind the API,
  quality regressions); this gate catches the degradation before it wastes
  multiple turns.
- **Repo-helper scripts run in the session CWD.** On hubs where the session
  repo (vault/notes) ≠ the code repo, SDD helpers like `task-brief` /
  `review-package` git-query the wrong repo and drop artifacts in the wrong
  tree — run them from inside the target repo/worktree (or pass the repo dir)
  and expect briefs to land in CWD.
- **Never nohup-launch a desktop GUI app and assume the user can interact**
  (2026-07-23: zenity dialogs silently "cancelled" — the agent shell has no
  session/DBus, so the app's prompts auto-fail). Hand the launch to the user via
  `!`/a real terminal and monitor the app's own log file instead.
- **Grep the depth note before briefing an infra diagnosis (2026-07-29, obs #58).**
  Before dispatching a diagnosis worker for infra weirdness (SSH refusals, service
  half-failures, network oddities), read/grep the Memory Map depth note(s) covering
  that surface for known lockdowns and gotchas — the vault has already answered a
  full diagnosis pass at least once (2026-07-28: the TCP-wrappers lockdown was
  documented in homelab-monitoring.md the whole time). One targeted read is cheaper
  than a worker.
- **Check your configured secrets store before asking for credentials.** If the
  operating context defines a canonical secrets location, read it before asking
  the user for any credential: SSH password, API key, service token, login. If
  the credential is there, use it silently; only ask if it isn't stored.
  Treat the lookup as the default first step of any remote-access task
  rather than relying on a hook to remind you.
- **Screenshot frugality + compaction guidance (2026-08-03).** Image reads are
  the largest single context burn in visual sessions: capture once, crop the
  small region under judgment (sips/element capture) instead of re-reading
  full-page PNGs, and never re-Read an image already in context. For long
  sessions, keep context lean and advise auto-compact or `/wrap` + `/resume`
  (ledger recovery) — a standalone manual `/compact` mid-heavy-session has
  forced a conversation revert.
- **Grep before Read on large files (2026-07-30).** Before reading any vault
  or reference file over ~100 lines in full, ask: do I need the whole file,
  or do I need one fact from it? If one fact: `grep`/`awk` for it — a full
  Read of a 200-line file adds ~800 tokens to context; a grep returns 2–3
  lines. The difference compounds: 5 unnecessary full reads = 4,000 extra
  tokens carried for the rest of the session (every subsequent turn re-reads
  them at cache rates). **Exceptions where full reads are correct:** skill
  bodies (need the full instruction set), CLAUDE.md (always loaded anyway),
  files you're about to edit (need full context to place the edit), worker
  briefs referencing a file's structure. **Session logs:** read only the top
  sections (up to Pending Tasks), never the Raw Session Log section, per
  /resume's existing rule. When in doubt: grep first; if the grep doesn't
  answer the question, then read the targeted section.
- **Two-strike rule on stranded/failed workers (2026-07-26 — Palworld
  incident).** If a delegated task fails, strands (yields without completing),
  or returns inconclusive results twice, do NOT dispatch a third worker.
  Instead: (1) run one bounded verification command yourself (the one-off
  exemption applies — this is a single read-only state check, not a batch),
  (2) report what you found to the user, and (3) either do the trivial fix inline
  if it's genuinely a one-off command, or ask the user how to proceed. Waiting
  indefinitely for a stranded worker is not a valid conductor state.
  (2026-07-26: a Palworld test-launch worker stranded 3× on SSH session
  teardown; the conductor waited 61 minutes for a completion that was never
  coming, when a 2-minute SSH check would have confirmed the fix was already
  done. The task took 1h27m instead of 26m.)
- **10-minute stuck rule (2026-07-26).** If 10 minutes of wall-clock time
  pass without either: (a) a tool call completing, (b) a worker returning,
  or (c) a report to the user — you are stuck. State what you're waiting for,
  what you've tried, and ask the user how to proceed. Do not wait silently beyond
  10 minutes for any single event. "Waiting for a worker notification" is not
  progress — if the notification hasn't arrived in 10 minutes, check the
  state yourself (two-strike rule applies, one-off exemption covers a single
  verification command) and report. (2026-07-26: the Palworld incident's
  61-minute silent wait is the failure case — the work was done at minute 26
  and the conductor sat idle without reporting.)
- **Report length awareness (2026-07-26).** The conductor-tripwire hook
  flags responses that exceed ~2000 characters when they end with a status
  line (indicating a report). If the tripwire fires on length, the next
  response must be tighter — the ≤8-line detail cap (quick-recap) has failed
  three times as a written rule; the tripwire makes violations visible
  immediately rather than logging them after the fact. Treat a length flag
  the same as a user correction: tighten, don't explain why it was long.
- **Per-session cost awareness (2026-07-26).** The usage-guard burn-check
  injection now includes a session-scoped worker count. Use it as a
  proportionality signal: if you've already dispatched 4+ workers on a task
  that should have taken 1–2, you are over-engineering — report what you have
  and ask the user whether to continue. A $15 session on a $2 task is a failure
  of proportionality, not a success of thoroughness.
- **Degraded-session recognition (2026-07-26).** If this session has
  accumulated 2+ worker failures AND has been running for 60+ minutes, the
  session is degraded. Report current state to the user and recommend: /wrap and
  start fresh, or continue with an explicit scope reduction. A degraded
  session costs more per turn (context bloat), produces lower-quality
  decisions (attention spread thin), and compounds errors. The session-timer
  hook will inject this recommendation automatically when both conditions are
  met, but do not wait for the hook — if you notice both conditions yourself,
  surface it immediately.
- **Verify task-completeness before reporting done (2026-08-02).** Before
  writing a status line (🟢/🟡/🔴) or telling the user the work is finished,
  re-read their most recent prompt and explicitly check: did I do ALL of what
  was asked? Not "did I do something useful" — did I do THE THING THEY ASKED
  FOR. If any part was missed, address it before the status line. The
  task-drift-check hook injects a mechanical reminder at 10+ tool calls,
  but do not wait for it — internalize the check. "Oh yeah, I just realized
  you asked me to do X and I didn't" after reporting done is the failure
  case this rule exists to prevent.
- **Queue execution work that arises while the agent slot is occupied; dispatch it as the NEXT worker rather than absorbing it inline (2026-08-16).** If it genuinely must run inline, say so explicitly at the time rather than retroactively. Since concurrent sonnet/haiku workers are already permitted up to a small ceiling, this binds mainly on Opus work, where the limit is one worker at a time.

## Vetting Delegated Work

Treat subagent reports as leads, not facts. Before using a high-impact finding,
opening a PR, or telling the user the work is done, Fable should reopen the
important cited files, confirm the relevant line refs or failures, and review
the final diff against the task. Let lighter agents gather signal; keep
truth-judgment with Fable.

**Commit durability (2026-07-29):** in an auto-syncing repo (Obsidian Git vault),
on-disk verification of a worker's edits is NOT durable — an auto pull can silently
discard uncommitted changes when the remote touches the same files (Batch-4 incident:
verified-on-disk edits vanished without ever being committed). Verification of vault
writes includes confirming the edit lands in a commit — or committing it immediately.
Machine-regenerated files (e.g. `AI-Sessions.md`, rewritten by the hub machine's mirror
job) are read-only surfaces: never target them for hand edits.

**Scratchpad verification tooling is conductor work — within limits (2026-08-09,
obs #120):** writing or fixing a small (~≤15-line) scratchpad script whose sole
purpose is auditing worker claims is conductor verification work, not delegable
execution. But if the tooling itself needs multi-round debugging, delegate it —
the iteration-loops-redispatch rule below applies to verification tooling too.

**Iteration loops redispatch (2026-08-03, obs #88):** when a vetting screenshot
(or any verification) reveals a defect that needs more than ONE fix round, the
conductor amends/redispatches the worker rather than iterating inline — the
one-off edit exemption covers single actions, not loops (a 3-round inline
edit→rebuild→screenshot loop was execution-shaped and tripped the tripwire;
one CONDUCTOR AMENDMENT with the loop delegated was the right move).

**Motion check for animated deliverables (2026-08-03):** a static screenshot
verifies "renders", never "animates" — different claims, different evidence.
Before presenting any animated deliverable, require two captures at different
times (or different `--virtual-time-budget` values) and confirm the pixels
differ (visual diff or byte-level compare). A whole animation pass once shipped
with the loop never advancing, across two implementer rounds and four reviews,
until the user caught it.

## Common Scenarios

Treat these as soft defaults, not rigid rules:

- Research: ask lighter agents to scan docs, prior art, APIs, and repo surfaces;
  Fable decides what evidence changes the plan.
- Coding: give cheaper agents bounded edits or candidate patches; Fable owns
  shared-file coordination, integration, and final review.
- Testing: have Fable suggest the validation direction and the scripts or
  browser checks that matter. Let lighter agents run targeted tests, browser
  flows, screenshots, and log reduction, then report exact commands, failures,
  likely causes, and whether failures look flaky, environmental, or real.
- Debugging: use cheaper agents to cluster logs, reproduce issues, and try
  small fixes; Fable decides which diagnosis is most trustworthy.

If a task is tiny or the validation itself needs delicate judgment, keep it
with Fable.

- **Stuck workers:** if a worker yields, fails, or returns incomplete evidence,
  verify the live state yourself (one SSH/Bash command — the one-off exemption).
  If the work is already done, report it. If it's not, decide: retry with a
  fixed brief (once), or hand the task to the user with what you know. Never wait
  more than 5 minutes for a worker that has already "finished" once without
  delivering a usable report — the completion notification lies; check state
  directly.
- **Answering from context:** if the information is already visible in this
  session's context (you read the file this turn, or the user told you the
  answer), do not delegate a worker to re-read it. A delegation brief costs
  more than typing the answer. The one-off exemption also covers "I already
  know this from context, and stating it is cheaper than a worker round-trip."

## Diagram

Use `assets/fable-orchestrator.excalidraw` when a visual explanation helps.

## Claims

For codebase-heavy work, it is reasonable to describe this as up to 3-5x more
cost-efficient and 2-4x faster when independent research, coding, or testing
slices can run in parallel. Treat those as workload-dependent estimates, not
guarantees.

Good launch copy:

> Make Claude Fable more efficient by using cheaper subagents for token-heavy
> research, coding, and testing, saving Fable for judgment, architecture,
> synthesis, and final review.

## Falsifiability Contract (mandatory in every delegation brief — adopted 2026-07-21)

Every delegation brief MUST include this required-output block, and the
conductor rejects reports that omit it:

> For every factual claim in your report (file exists/tracked, test passes,
> build clean, value is X, remote state is Y):
> 1. State the claim.
> 2. State the exact evidence you observed (path + line, or command + output
>    snippet).
> 3. State the command a reviewer runs to independently verify it in under 30
>    seconds.
> If you cannot provide evidence, write "unverified" — never assert it as
> fact.

The conductor re-verifies before acting on: file/VCS-state claims,
test/build results, safe-to-merge/deploy claims, external/remote state. With
the verify command supplied inline, re-verification is one bounded tool call
instead of a reasoning step. Log every verification outcome (confirmed /
contradicted / inconclusive) in the [[Fable-Delegation-Playbook]] outcome
log — this builds the false-claim base rate the 2026-07-21 Kiro audit
flagged as unmeasured.

When re-running a worker's verify command (adopted 2026-07-21, Kiro
follow-up — a plausible command that runs clean but tests a
related-but-different condition is the contract's residual attack surface):

- Run the exact command supplied, and read the FULL output, not just the
  first line.
- Confirm the command actually tests the specific claim — exit 0 proves
  nothing unless exit 0 is specifically what the claim depends on.
- If the output is ambiguous, the claim is unverified — treat it as if no
  verify command was provided.

A verify command must be RUN by its author before shipping (added
2026-07-26, obs #45 — consecutive fixture measurements shipped confident
opposite claims, one with an unrunnable verify command): a silently-failing
verify command is worse than none, because it lends false authority.
Workers and brief authors alike execute the exact command once before
including it. macOS gotcha: prefer `while read` loops over `xargs -I` —
arg-length limits kill long file lists silently.
