# Workflow templates (JS code examples)

> canonical: split out of `commands/workflow.md`. See that file for each template's name, summary, and args.

## 0. Null-guard helper (required in every template)

`agent()` returns null and drops silently on rate limit or kill. Count them and warn before discarding, and put `dropped` on the return. A null from a checker or gate aborts fail-closed (canonical: `commands/workflow.md` 「Null-guard」).

```javascript
const dropped = (arr, label) => {
  const n = arr.filter(x => x == null).length
  if (n > 0) log(`WARN: ${label} dropped ${n}/${arr.length} agents (suspected rate limit / kill)`)
  return n
}
// A null verdict from a checker or gate is never treated as accept (fail-closed)
const verdict = await agent('Gate check: ...', { schema: VERDICT_SCHEMA })
if (verdict == null) { log('WARN: checker null — abort (fail-closed)'); return { aborted: true } }
```

## Self-routing policy

Self-routing — Claude rewriting the graph itself each time (always-on dynamic workflow = ultracode) — is **not adopted** for now. The SoT is: parent picks one of the 7 templates in this file. See the corresponding entry in `references/CLAUDE-CODE-OPPORTUNITIES.md` for the rationale and the conditions for re-evaluation.

## Router pattern (agent classification + code branching)

To split the downstream path at runtime, classify with an agent and then pick the edge with a JS `if / switch` (do not leave the branching logic to the agent). Same pattern as Task type detection in `/flow`.

```javascript
const { severity } = await agent(`Classify diff risk:\n${diff}`,
  { schema: { type: 'object', properties: { severity: { enum: ['low', 'high'] } }, required: ['severity'] } })
const review = severity === 'high'
  ? await parallel(FILES.map(f => () => agent(`Audit ${f}`)))
  : await agent(`Quick review of ${diff}`)
```

## 1. review

dimensions → find → adversarially verify pipeline. pipeline default (no barrier); verify fires per finding.

```javascript
export const meta = {
  name: 'review-changes',
  description: 'Review changed files across dimensions, verify each finding',
  phases: [{ title: 'Review' }, { title: 'Verify' }],
}
const DIMS = [
  { key: 'bugs', prompt: '...' },
  { key: 'perf', prompt: '...' },
  { key: 'security', prompt: '...' },
]
const results = await pipeline(DIMS,
  d => agent(d.prompt, { phase: 'Review', schema: FINDINGS_SCHEMA }),
  rev => parallel(rev.findings.map(f => () =>
    agent(`Adversarially verify: ${f.title}`, { phase: 'Verify', schema: VERDICT_SCHEMA })
      .then(v => ({ ...f, verdict: v }))
  ))
)
const flat = results.flat()
return { confirmed: flat.filter(Boolean).filter(f => f.verdict?.isReal), dropped: dropped(flat, 'Verify') }
```

## 2. migrate (worktree isolation required)

discover sites → transform each → verify. Parallel edits to same file require worktree isolation to prevent conflicts.

```javascript
phase('Discover')
const sites = await agent('Find all <pattern> usage sites', { schema: SITES_SCHEMA })
phase('Transform')
const fixed = await parallel(sites.items.map(s => () =>
  agent(`Migrate ${s.file}:${s.line} from X to Y`, { isolation: 'worktree' })
))
return { migrated: fixed.filter(Boolean).length, dropped: dropped(fixed, 'Transform') }
```

## 3. research (multi-modal sweep)

Parallel fan-out across different search angles → deep-read → synthesize. Covers failure modes missed in a single sweep.

```javascript
const ANGLES = ['by-container', 'by-content', 'by-entity', 'by-time']
const hits = (await parallel(ANGLES.map(a => () =>
  agent(`Search ${args.topic} via ${a}`, { schema: HITS_SCHEMA })))).filter(Boolean)
const deep = await parallel(hits.flatMap(h => h.urls.slice(0, 3)).map(u => () =>
  agent(`Deep read: ${u}`, { schema: SUMMARY_SCHEMA })))
return await agent(`Synthesize cited report from: ${JSON.stringify(deep)}`, { schema: REPORT_SCHEMA })
```

## 4. understand (subsystem map)

Read multiple subsystems in parallel to get a structured map. Lighter codebase comprehension than `/flow`.

```javascript
const SUBSYS = ['auth', 'api', 'db', 'ui']
const maps = await parallel(SUBSYS.map(s => () =>
  agent(`Map ${s} subsystem: entry points / dependencies / data flow`, { schema: MAP_SCHEMA })))
return { systems: maps.filter(Boolean) }
```

## 5. judge-panel (N independent approaches + majority vote)

Generate 3-5 design approaches independently → judge agent scoring → adopt winner + graft best runner-up ideas.

```javascript
const ANGLES = ['MVP-first', 'risk-first', 'user-first']
const drafts = await parallel(ANGLES.map(a => () =>
  agent(`Design ${args.feature} from ${a} angle`, { schema: DESIGN_SCHEMA })))
const scored = await parallel(drafts.filter(Boolean).map(d => () =>
  agent(`Score this design: ${JSON.stringify(d)}`, { schema: SCORE_SCHEMA })))
const winner = scored.reduce((a, b) => a.score > b.score ? a : b)
return await agent(`Synthesize final from winner + graft top runner-up ideas: ${JSON.stringify(scored)}`,
  { schema: FINAL_SCHEMA })
```

## 6. scan (rule-engine sweep + agent triage, directory-batch fan-out for large codebases)

Deterministic rule-engine sweep per directory batch (agent executes a fixed command, no interpretation) → agent triage confirms true/false positive with file:line:rule-id and severity. pipeline default; triage fans out per raw hit. Batch count scales to Workflow tool's tens-hundreds queue depth; actual concurrency is tool-capped automatically, no manual throttling needed.

```javascript
export const meta = {
  name: 'scan-vulnerabilities',
  description: 'Directory-batch rule-engine sweep (RuleScan) + per-hit agent triage (Triage) for repo-scale vulnerability scanning',
  phases: [{ title: 'RuleScan' }, { title: 'Triage' }],
}
const HITS_SCHEMA = {
  type: 'object',
  properties: { hits: { type: 'array', items: {
    type: 'object',
    properties: {
      file: { type: 'string' }, line: { type: 'integer', minimum: 1 },
      ruleId: { type: 'string' }, snippet: { type: 'string' },
    },
    required: ['file', 'line', 'ruleId'],
  } } },
  required: ['hits'],
}
const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
    verdict: { type: 'string', enum: ['true-positive', 'false-positive', 'needs-review'] },
    fix: { type: 'string' },
  },
  required: ['severity', 'verdict'],
}
// args.batches: [{ dir, ruleCmd }] — directories enumerated by parent (e.g. `git ls-files | xargs -n1 dirname | sort -u`)
// before firing; file-level enumeration stays inside each RuleScan agent so 100k+-file repos never
// materialize a full file list in parent/script context.
const results = await pipeline(args.batches,
  b => agent(`Run exactly: ${b.ruleCmd} scoped to ${b.dir}. Enumerate files yourself; split per-file if any file exceeds ~5k lines. No interpretation — return raw hits only.`,
    { phase: 'RuleScan', schema: HITS_SCHEMA }
  ).then(r => { if (r == null) log(`WARN: RuleScan dropped batch ${b.dir}`); return r }),
  raw => parallel((raw?.hits ?? []).map(h => () =>
    agent(`Triage rule hit ${h.ruleId} at ${h.file}:${h.line} (snippet: ${h.snippet}). Confirm true/false positive, assign severity, 1-line fix.`,
      { phase: 'Triage', schema: VERDICT_SCHEMA }).then(v => v && { ...h, ...v })
  ))
)
const flat = results.flat()
return {
  confirmed: flat.filter(Boolean).filter(f => f.verdict === 'true-positive'),
  needsReview: flat.filter(Boolean).filter(f => f.verdict === 'needs-review'),
  dropped: dropped(flat, 'Triage'),
  batchesScanned: args.batches.length,
}
```

## 7. loop-until-dry (unknown-size discovery)

Use for discovery tasks whose total count is unknown up front (bug sweep, issue discovery, edge-case enumeration). Stop after K consecutive rounds with zero new findings. **Dedupe against the `seen` set, not against confirmed.** Miss this and findings the verifier rejected get rediscovered every round, so the loop never runs dry (details: `references/loop-engineering.md` 「dedupe vs seen」).

```javascript
const seen = new Set(); const confirmed = []; let dry = 0
const key = b => `${b.file}:${b.line}:${b.rule}`

while (dry < 2 && confirmed.length < args.maxFindings) {
  const round = (await parallel(FINDERS.map(f => () =>
    agent(f.prompt, { phase: 'Find', schema: BUGS_SCHEMA }))))
    .filter(Boolean).flatMap(r => r.bugs)
  const fresh = round.filter(b => !seen.has(key(b)))
  if (!fresh.length) { dry++; log(`dry round ${dry}/2`); continue }
  dry = 0
  fresh.forEach(b => seen.add(key(b)))

  const judged = await parallel(fresh.map(b => () =>
    parallel(['correctness', 'security', 'repro'].map(lens => () =>
      agent(`Judge "${b.desc}" via ${lens} — real?`, { phase: 'Verify', schema: VERDICT_SCHEMA })))
      .then(vs => ({ b, real: vs.filter(Boolean).filter(v => v.real).length >= 2 }))))
  confirmed.push(...judged.filter(v => v.real).map(v => v.b))
}
return { confirmed, seenTotal: seen.size, rejectedTotal: seen.size - confirmed.length }
```
