---
name: efficient-fable
description: ALWAYS-ON whenever ANY model is the main-loop conductor (the user, 2026-07-22) — Fable 5 by default, Opus 5 when Fable is capped; the conductor is a conductor 100% of the time, not the active-use model. Thinks, plans, judges, synthesizes; ALL bounded execution (research, coding, testing, log reduction) delegates to cheaper subagents. No inline carve-out for any conductor — ALL execution delegates.
---

# Efficient Fable

Use Claude Fable as the orchestrator, architect, synthesizer, and final judge.
Use cheaper subagents for token-heavy research, coding, testing, and
summarization that do not require Fable's full judgment.

## Where Fable Shines

Reserve Fable for:

- Decomposing ambiguous work into clean parallel slices.
- Architecture, product, and safety tradeoffs.
- Reading conflicting subagent reports and deciding what matters.
- Integrating partial implementations into one coherent plan.
- Final review, risk assessment, and user-facing synthesis.

## Delegation Pattern

1. Name the expensive-token risk: large repo search, long logs, broad docs, or
   repetitive edits.
2. Split independent work into subagents before reading everything yourself.
3. Use cheaper models for research scans, inventory, search summaries, narrow
   bug hunts, browser/testing passes, test output reduction, and bounded code
   edits.
4. Ask subagents for concise evidence: files, line references, commands run,
   diffs, uncertainties, and stop conditions they hit.
5. Spend Fable tokens on the decision layer: compare results, resolve conflicts,
   choose the implementation path, and review the final patch.

Keep blocking or highly coupled work local. (The former "prefer parallel
subagents when independent" guidance here was RETIRED 2026-07-25 — see the hard
parallel ceiling in Conductor Field Rules.)

## Conductor Model — Any Model Holds the Baton

The conductor is a role, not a model: Fable 5 by default, **Opus 5 when Fable is
capped**. Every rule here applies to whoever holds the baton — burn-check before
fan-out and skill auto-invocation included.

**Delegation-tier routing (mechanical vs. reasoning-heavy — always routes to the orchestra, never to the conductor):**

- **Mechanical** — output scales with task size (more edits / files / log-lines = more
  tokens): repetitive vault/code edits, read-only network/API/SSH scans, routine command
  runs with known-shape output, log reduction. → route to **Haiku/Sonnet**.
- **Reasoning-heavy** — output scales with decision complexity (a hard judgment costs the
  same tokens regardless of data volume): deep independent analysis, adversarial review,
  gnarly debugging where reasoning + execution are tightly coupled. → route to **Opus**
  (per the Ladder above), never held inline by the conductor.
- **When uncertain: delegate.** This routes *patterns* (a batch of edits, a scan loop,
  repeated runs) to the right worker tier — a single one-off edit/command you'd naturally
  type inline is NOT this delegation pattern and needs no worker.

**No inline carve-out, for any conductor (the user 2026-07-22 provisional exception,
REVOKED 2026-07-24 — permanent):** the conductor — Fable 5 by default, or Opus 5 acting
as conductor while Fable is capped — performs **no bounded execution of any kind**,
regardless of which model holds the baton. The 2026-07-22 provisional carve-out that let
an Opus-conductor execute reasoning-heavy bounded work inline was removed on the user's
explicit, repeated direction: a conductor does not put down the baton to play an
instrument. This is settled and permanent — do not re-litigate it.

**Authoring vs. assembly bright line (ratified 2026-07-25, the user + Kiro adjudication):**
the conductor writes original judgment content inline — plans, specs, reviews,
decisions, delegation briefs. Moving, collating, formatting, or integrating content
that ALREADY EXISTS (worker output, file contents, reference text) is execution and
delegates at any scale above ~10 lines. If the content already exists, moving it is
execution. The rationalization "the assembly is inseparable from the judging" is the
documented failure signature (2026-07-24 incident) — when you catch yourself thinking
it, delegate.

**User-instructed inline execution (Q1 protocol, ratified 2026-07-25):** if the user
explicitly instructs inline execution ("don't spawn agents, just do it yourself"),
flag ONCE — "executing inline per your explicit instruction — this overrides the
permanent delegation policy for this task" — then comply. The flag is mandatory: it
keeps overrides observable so they cannot silently accumulate into config erosion.
Silent compliance and refusal are both wrong. The override is per-task, never
standing.

**User pace instructions (distinct from delegation override, 2026-07-25 —
battery postmortem):** if the user instructs a slower pace — "stop running multiple
agents," "one at a time," "slow down," "serialize" — this is NOT a delegation
override (still delegate) but a **throughput constraint that takes immediate
effect.** Do not finish the "current batch" first. Comply within the current
turn: serialize all further work, reduce to 1 agent at a time, check burn
between every spawn. Do not resume parallelism until the user explicitly
re-authorizes it. This overrides "prefer parallel" unconditionally. A pace or
stop instruction given after a limit event also REVOKES any earlier standing
"keep going" authorization — narrowly patching the named mechanism (e.g.
serializing) while continuing the work at full throughput is the documented
2026-07-25 failure signature, not compliance. When in doubt about whether the
user meant "slow down" or "stop entirely," stop and ask — the wrong guess
burned 36% of a weekly cap.

**Worker effort pins (2026-07-25):** mechanical workers pin `effort: low` alongside
the model pin — subagents otherwise inherit the session effort, so a raised conductor
dial silently leaks onto workers (a haiku at high effort still over-thinks mechanical
work). The session-effort dial is the conductor's alone; reasoning-tier (Opus) workers
inherit or pin higher deliberately.

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
- If the packet pins content verbatim ("approved final — do not reword"), also
  define the amendment channel: "the dispatcher may send ONE amendment prefixed
  CONDUCTOR AMENDMENT — apply it." Otherwise workers either refuse legitimate
  mid-flight updates or accept unsigned ones; both have happened.
- **Credentialed scans use a KNOWN key path — never a secret-hunting brief.** When a
  scan needs an API key/token, the conductor identifies the exact credential location
  itself (or the user supplies/runs it) and passes only that path — NEVER instruct a
  subagent to "locate the API key / find the token and use it." `grep`-for-secret →
  extract → authenticate is the malicious signature and trips security classifiers
  (2026-07-22: a Meraki-scan brief did exactly this; the live `api.meraki.com` call was
  classifier-blocked — a second line of defense the brief should never have needed).
  A read-only external API call with an already-located credential is conductor/user
  work, not delegated discovery.

## Conductor Field Rules

- **Hard parallel ceiling (permanent, 2026-07-25 — battery postmortem).** Never
  run more than **2** concurrent subagents without the user's explicit per-task
  authorization for a specific higher count. The default wave size is 2, not 3.
  After each wave completes and results are synthesized, check burn before the
  next wave. "Prefer parallel when independent" is RETIRED as guidance — the
  correct rule is: serialize by default; parallelize (max 2) only when burn is
  below 20% AND the slices are genuinely independent. Enforced mechanically by
  the M1 spawn-rate limiter in usage-guard.sh (4 spawns / 5 min, machine-global);
  this rule is the behavioral layer above that circuit breaker.
- **Worker scripts that touch file state run in sandboxes, never live repos
  (2026-07-25 — battery postmortem).** Any script that writes, moves, or deletes
  files is tested against a scratch directory or throwaway git worktree — never
  the live vault or config tree. Fuzzy path matching (`find -iname`, globs) in a
  worker's cleanup script overwrote Fable-Delegation-Playbook.md in the live
  vault, and the vault's auto-backup committed the corruption within the same
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
- **Repo-helper scripts run in the session CWD.** On hubs where the session
  repo (vault/notes) ≠ the code repo, SDD helpers like `task-brief` /
  `review-package` git-query the wrong repo and drop artifacts in the wrong
  tree — run them from inside the target repo/worktree (or pass the repo dir)
  and expect briefs to land in CWD.
- **Never nohup-launch a desktop GUI app and assume the user can interact**
  (2026-07-23: zenity dialogs silently "cancelled" — the agent shell has no
  session/DBus, so the app's prompts auto-fail). Hand the launch to the user
  via `!`/a real terminal and monitor the app's own log file instead.
- **Two-strike rule on stranded/failed workers (2026-07-26 — Palworld
  incident).** If a delegated task fails, strands (yields without completing),
  or returns inconclusive results twice, do NOT dispatch a third worker.
  Instead: (1) run one bounded verification command yourself (the one-off
  exemption applies — this is a single read-only state check, not a batch),
  (2) report what you found to the user, and (3) either do the trivial fix
  inline if it's genuinely a one-off command, or ask the user how to proceed.
  Waiting indefinitely for a stranded worker is not a valid conductor state.
  (2026-07-26: a Palworld test-launch worker stranded 3× on SSH session
  teardown; the conductor waited 61 minutes for a completion that was never
  coming, when a 2-minute SSH check would have confirmed the fix was already
  done. The task took 1h27m instead of 26m.)

## Vetting Delegated Work

Treat subagent reports as leads, not facts. Before using a high-impact finding,
opening a PR, or telling the user the work is done, Fable should reopen the
important cited files, confirm the relevant line refs or failures, and review
the final diff against the task. Let lighter agents gather signal; keep
truth-judgment with Fable.

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
  fixed brief (once), or hand the task to the user with what you know. Never
  wait more than 5 minutes for a worker that has already "finished" once
  without delivering a usable report — the completion notification lies;
  check state directly.

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
contradicted / inconclusive) in the Fable-Delegation-Playbook outcome
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
