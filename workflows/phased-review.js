export const meta = {
  name: 'phased-review',
  description: 'Spec-drift review: contract checklist → prior-work baseline → surface audits → batched verification → ranked synthesis report',
  whenToUse: 'Use to review a codebase, document set, or feature against a spec/PRD for drift, gaps, or correctness issues. Hard caps: ≤5 surfaces, ≤4 findings verified per surface, waves of 3, ≤25 total work agents, all subagents on sonnet/haiku. The conductor/manager model reviews the returned report — it does not run inside this workflow. On halt, resume with Workflow({scriptPath, resumeFromRunId}).',
  phases: [
    { title: 'Contract',  detail: 'distill spec into a checkable requirement checklist' },
    { title: 'Baseline',  detail: 'identify prior-known issues to avoid duplicate findings' },
    { title: 'Audit',     detail: 'parallel surface audits in waves of 3 (sonnet)' },
    { title: 'Verify',    detail: 'one batched verifier per surface — keep-case adversarial (sonnet)' },
    { title: 'Synthesis', detail: 'ranked report: delete > collapse > rewrite (sonnet)' },
  ],
}

// ── schemas ──────────────────────────────────────────────────────────────────

const CHECKLIST_SCHEMA = {
  type: 'object',
  properties: {
    requirements: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id:          { type: 'string' },
          requirement: { type: 'string' },
          category:    { type: 'string' },
        },
        required: ['id', 'requirement'],
      },
    },
  },
  required: ['requirements'],
}

const BASELINE_SCHEMA = {
  type: 'object',
  properties: {
    knownIssues: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title:       { type: 'string' },
          file:        { type: 'string' },
          description: { type: 'string' },
        },
        required: ['title', 'description'],
      },
    },
    surfaces: {
      type: 'array',
      items: { type: 'string' },
      description: 'Suggested surface names for auditing, e.g. ["auth", "api", "data-layer"]',
    },
  },
  required: ['knownIssues', 'surfaces'],
}

const FINDINGS_SCHEMA = {
  type: 'object',
  properties: {
    surface: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title:        { type: 'string' },
          file:         { type: 'string' },
          line:         { type: 'string' },
          contract_ref: { type: 'string', description: 'Requirement ID from the checklist' },
          rationale:    { type: 'string' },
          severity:     { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['title', 'contract_ref', 'rationale', 'severity'],
      },
    },
  },
  required: ['surface', 'findings'],
}

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    surface: { type: 'string' },
    verdicts: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          finding_title: { type: 'string' },
          isReal:        { type: 'boolean' },
          keepCase:      { type: 'string', description: 'Best argument FOR keeping/ignoring this finding' },
          confidence:    { type: 'number', description: '0–1' },
          action:        { type: 'string', enum: ['delete', 'collapse', 'rewrite', 'note'] },
        },
        required: ['finding_title', 'isReal', 'action'],
      },
    },
  },
  required: ['surface', 'verdicts'],
}

const SYNTHESIS_SCHEMA = {
  type: 'object',
  properties: {
    report: {
      type: 'string',
      description: 'Ranked markdown report. Sections: DELETE (remove/no-op), COLLAPSE (merge/simplify), REWRITE (substantial fix), NOTES (low-confidence). Each item: title, surface, file:line, impact×ease score, recommended action.',
    },
    totalConfirmed: { type: 'number' },
    totalDropped:   { type: 'number' },
  },
  required: ['report', 'totalConfirmed', 'totalDropped'],
}

// ── helpers ───────────────────────────────────────────────────────────────────

const cfg = {
  maxSurfaces:           args?.maxSurfaces           ?? 5,
  maxFindingsPerSurface: args?.maxFindingsPerSurface ?? 4,
  waveSize:              args?.waveSize              ?? 3,
  maxAgents:             args?.maxAgents             ?? 25,
  blockPct:              args?.blockPct              ?? 90,
}

let agentCount = 0
const countedAgent = async (prompt, opts) => {
  agentCount++
  if (agentCount > cfg.maxAgents) {
    log(`Agent cap reached (${cfg.maxAgents}). Halting.`)
    return null
  }
  return agent(prompt, opts)
}

const checkUsage = async () => {
  const result = await countedAgent(
    'Run `bash ~/.claude/hooks/usage-guard.sh pct` and return ONLY the integer from stdout. Nothing else.',
    { label: 'usage-gate', model: 'haiku', effort: 'low', phase: 'Audit' }
  )
  return parseInt(result?.trim()) || -1
}

// ── phase 1: contract ─────────────────────────────────────────────────────────

phase('Contract')

const specPath = args?.spec ?? ''
// Accept a bare-string args as the target path; NEVER default to '.' — the session cwd is
// the vault, and defaulting there is exactly the 2026-07-18 misfire (16 agents audited the
// wrong repo). No target → halt before spending a single agent.
const target = typeof args === 'string' ? args : (args?.repo ?? args?.target ?? null)
if (!target) {
  return { halted: true, reason: 'No target passed — refusing to default to the session cwd. Pass args.repo (absolute path to the repo under review).', unauditedSurfaces: [], confirmedFindings: [], synthesis: null }
}
// Injected into EVERY agent prompt (contract included — it previously got no target at all).
const TARGET_BLOCK =
  `TARGET REPO (MANDATORY): ${target}\n` +
  `Operate ONLY inside this absolute path. If it does not exist, is not a repo, or is ` +
  `plainly not the codebase the spec describes, STOP immediately and say so in your ` +
  `output instead of auditing anything else.\n\n`

const contract = await countedAgent(
  TARGET_BLOCK +
  `Read the spec/PRD at: ${specPath || '(see task description)'}\n\n` +
  (args?.specContent ? `Spec content:\n${args.specContent}\n\n` : '') +
  `Task: distill every checkable requirement into a numbered checklist. ` +
  `Each requirement must be independently verifiable by a code auditor. ` +
  `Group into categories (e.g. "auth", "api", "data"). ` +
  `Return structured JSON.`,
  { label: 'contract', model: 'sonnet', phase: 'Contract', schema: CHECKLIST_SCHEMA }
)

if (!contract) {
  return { halted: true, reason: 'Contract phase failed', unauditedSurfaces: [], confirmedFindings: [], synthesis: null }
}

log(`Contract: ${contract.requirements.length} requirements extracted`)

// ── phase 2: baseline ─────────────────────────────────────────────────────────

phase('Baseline')

const baseline = await countedAgent(
  TARGET_BLOCK +
  `Review git log, existing TODO/FIXME comments, and any known-issues docs. ` +
  `Return: (1) a list of already-known issues so auditors don't re-report them, ` +
  `(2) suggested surface names for auditing this codebase (max ${cfg.maxSurfaces}). ` +
  `Return structured JSON.`,
  { label: 'baseline', model: 'sonnet', phase: 'Baseline', schema: BASELINE_SCHEMA }
)

const suggestedSurfaces = baseline?.surfaces ?? []
const knownIssues       = baseline?.knownIssues ?? []
const knownTitles       = new Set(knownIssues.map(i => i.title.toLowerCase()))

log(`Baseline: ${knownIssues.length} known issues; ${suggestedSurfaces.length} surfaces suggested`)

// surfaces: explicit from args, or suggested, or fallback
const rawSurfaces = (args?.surfaces ?? suggestedSurfaces).slice(0, cfg.maxSurfaces)
const surfaces    = rawSurfaces.length > 0 ? rawSurfaces : ['general']

if (surfaces.length < rawSurfaces.length) {
  log(`Surfaces capped at ${cfg.maxSurfaces} (dropped ${rawSurfaces.length - surfaces.length})`)
}

// ── phases 3+4: audit → batched verify in waves ───────────────────────────────

phase('Audit')

const requirementSummary = contract.requirements
  .map(r => `[${r.id}] ${r.requirement}`)
  .join('\n')

const knownSummary = knownIssues.length > 0
  ? 'Already-known issues (do NOT report these):\n' + knownIssues.map(i => `- ${i.title}: ${i.description}`).join('\n')
  : 'No pre-existing known issues.'

const confirmedFindings = []
const unauditedSurfaces = []
const unverifiedOverflow = []

// process surfaces in waves
for (let i = 0; i < surfaces.length; i += cfg.waveSize) {
  const wave       = surfaces.slice(i, i + cfg.waveSize)
  const waveNum    = Math.floor(i / cfg.waveSize) + 1
  const totalWaves = Math.ceil(surfaces.length / cfg.waveSize)

  log(`Wave ${waveNum}/${totalWaves}: surfaces [${wave.join(', ')}]`)

  // usage gate before each wave
  const pct = await checkUsage()
  if (pct >= cfg.blockPct) {
    log(`Usage at ${pct}% (≥${cfg.blockPct}%). Halting before wave ${waveNum}.`)
    unauditedSurfaces.push(...surfaces.slice(i))
    return {
      halted:              true,
      reason:              `Usage cap at ${pct}%`,
      unauditedSurfaces,
      unverifiedFindings:  unverifiedOverflow,
      confirmedFindings,
      synthesis:           null,
    }
  }

  // audit + verify each surface in this wave via pipeline
  const waveResults = await pipeline(
    wave,

    // stage 1: audit (one sonnet agent per surface)
    async (surface, _orig, idx) => {
      return countedAgent(
        TARGET_BLOCK + `Surface: "${surface}"\n\n` +
        `Requirements checklist:\n${requirementSummary}\n\n` +
        `${knownSummary}\n\n` +
        `Audit the "${surface}" surface of the target against the checklist. ` +
        `Report only genuine spec-vs-implementation gaps or correctness bugs. ` +
        `Cite file:line for every finding. Include all severities (high/medium/low). ` +
        `Do NOT filter findings at this stage — report everything; filtering happens in verification. ` +
        `Return structured JSON.`,
        { label: `audit:${surface}`, model: 'sonnet', phase: 'Audit', schema: FINDINGS_SCHEMA }
      )
    },

    // stage 2: batched verify (ONE agent for all findings on this surface)
    async (auditResult, surface) => {
      if (!auditResult) return null
      if (auditResult.findings.length === 0) {
        log(`${surface}: 0 findings — skipping verify`)
        return { surface, verdicts: [] }
      }

      // cap findings going into verify
      const toVerify  = auditResult.findings.slice(0, cfg.maxFindingsPerSurface)
      const overflow  = auditResult.findings.slice(cfg.maxFindingsPerSurface)
      if (overflow.length > 0) {
        log(`${surface}: ${overflow.length} findings over cap — dropped from verify`)
        unverifiedOverflow.push(...overflow.map(f => ({ ...f, surface })))
      }

      const findingsList = toVerify
        .map((f, i) => `[${i+1}] "${f.title}" (${f.file}:${f.line ?? '?'}) — ${f.rationale} [contract: ${f.contract_ref}]`)
        .join('\n')

      return countedAgent(
        TARGET_BLOCK + `Surface: "${surface}"\n\n` +
        `Verify these findings from the audit of "${surface}":\n${findingsList}\n\n` +
        `For each finding, argue the KEEP case (why this finding might be wrong or not worth fixing). ` +
        `Then decide: is it real? If real, what action: delete (code/feature removal), collapse (simplify/merge), rewrite (substantial fix), note (low-priority)? ` +
        `Check git history for WHY the code was written before marking something for deletion. ` +
        `Return structured JSON.`,
        { label: `verify:${surface}`, model: 'sonnet', phase: 'Verify', schema: VERDICT_SCHEMA }
      )
    }
  )

  // collect confirmed findings from this wave
  for (const verdictResult of waveResults.filter(Boolean)) {
    for (const verdict of (verdictResult.verdicts ?? [])) {
      if (verdict.isReal) {
        confirmedFindings.push({ ...verdict, surface: verdictResult.surface })
      }
    }
  }
}

log(`Audit+Verify complete. ${confirmedFindings.length} confirmed findings.`)

// ── phase 5: synthesis ────────────────────────────────────────────────────────

phase('Synthesis')

const usageBeforeSynth = await checkUsage()
if (usageBeforeSynth >= cfg.blockPct) {
  log(`Usage at ${usageBeforeSynth}% before synthesis. Returning partial state.`)
  return {
    halted:             true,
    reason:             `Usage cap at ${usageBeforeSynth}% before synthesis`,
    unauditedSurfaces:  [],
    unverifiedFindings: unverifiedOverflow,
    confirmedFindings,
    synthesis:          null,
  }
}

const findingsSummary = confirmedFindings
  .map((f, i) => `[${i+1}] surface=${f.surface} title="${f.finding_title}" action=${f.action} confidence=${f.confidence ?? '?'}`)
  .join('\n')

const synthesis = await countedAgent(
  `You are synthesizing the results of a spec-drift review.\n\n` +
  `Confirmed findings (${confirmedFindings.length} total):\n${findingsSummary}\n\n` +
  (unverifiedOverflow.length > 0
    ? `Unverified overflow (${unverifiedOverflow.length} findings hit the per-surface cap — not adversarially verified):\n` +
      unverifiedOverflow.map(f => `- [${f.surface}] ${f.title}`).join('\n') + '\n\n'
    : '') +
  (unauditedSurfaces.length > 0
    ? `Unaudited surfaces (run was halted before auditing these): ${unauditedSurfaces.join(', ')}\n\n`
    : '') +
  `Produce a ranked, actionable report. Structure:\n` +
  `1. DELETE — findings where the code/feature should simply be removed\n` +
  `2. COLLAPSE — findings where code should be merged, simplified, or de-duplicated\n` +
  `3. REWRITE — findings requiring substantial rework\n` +
  `4. NOTES — real but low-confidence or low-priority findings\n\n` +
  `For each item include: title, surface, file:line, a one-sentence recommended action, and an impact×ease score (1–5 each). ` +
  `Sort each section by impact×ease descending. ` +
  `End with a summary line: N confirmed, M dropped (not real), P unverified overflow, Q unaudited surfaces.`,
  { label: 'synthesis', model: 'sonnet', phase: 'Synthesis', schema: SYNTHESIS_SCHEMA }
)

log(`Synthesis complete. ${synthesis?.totalConfirmed ?? '?'} confirmed, ${synthesis?.totalDropped ?? '?'} dropped.`)

return {
  halted:             false,
  unauditedSurfaces:  [],
  unverifiedFindings: unverifiedOverflow,
  confirmedFindings,
  synthesis:          synthesis?.report ?? '(synthesis failed)',
}
