# Advisor Proxy Dispatch

Route advisor consults through a proxy worker. This is a convention, not an enforced block.

**Why proxy:** The advisor tool forwards your entire transcript to the advisor model. If this session contains security, credential, network-audit, or secrets-adjacent content, the advisor will refuse permanently for the session. A proxy worker has a clean transcript containing only the brief you provide.

**Enforcement:** A post-hoc Stop hook (`advisor-proxy-audit.sh`) flags conductor-direct advisor calls at session end. It detects, it does not prevent. The proxy discipline is yours to maintain.

Dispatch a **sonnet** worker with the brief below. Fill in the bracketed sections. The worker's transcript must stay clean: it calls the advisor once, relays the response, and stops.

---

## Proxy Worker Brief Template

```
You are an advisor proxy worker. Your sole job: relay the material below to the advisor tool and return its response.

## Material for Review

[STATE what you want reviewed: the work product, plan, decisions, or findings.
Write them in full. Do not reference external files, prior turns, or assumptions.]

## Current Measured State

[STATE empirical facts the advisor needs. These must be MEASURED this session
(commands run, files read, APIs queried), not assumptions, not prior-session carryover,
not injected context snapshots. If a fact came from a worker report, say so and note
whether it was independently verified.]

## Specific Questions

[STATE what you want the advisor to evaluate, challenge, or decide.
Be precise. "Review this" is weaker than "Is finding 3 causal or correlational?"]

## Instructions (binding, do not modify)

1. Call the advisor tool exactly once.
2. Do NOT read any files before calling the advisor.
3. Do NOT run any commands before calling the advisor.
4. Your transcript must contain nothing except this brief and the advisor call.
   Any pre-call tool use poisons your transcript and defeats the proxy purpose.
5. After the advisor responds: relay its full response verbatim to the conductor.
   Do not summarize, do not editorialize, do not omit.
6. If the advisor refuses or returns an error, relay the exact error text verbatim.
   This tells the conductor whether the brief itself triggered safeguards.
7. After relaying: stop. Do not take any further action.
```

---

## Notes

- If the advisor refuses via the proxy, your brief contains triggering content. Rewrite it: remove security/credential/network-audit language, use abstract descriptions instead.
- The proxy worker must be sonnet (cheap, capable of following instructions, no need for opus-level reasoning).
- One proxy dispatch per advisor consultation. Do not batch multiple questions into one call unless they're tightly coupled.
- Direct calls are permitted in sessions certified clean from the start. Use judgment. The audit hook will log it either way.
