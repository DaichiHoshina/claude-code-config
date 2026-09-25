---
allowed-tools: Read, Glob, Grep, Write, Bash, Task, AskUserQuestion, mcp__serena__*, mcp__context7__*
argument-hint: "[--go] <task-or-scope>"
description: 設計と planning — PO Agent 経由で戦略を組み立てる (read-only、`--go` は investigation を含まない plan だけ implementation まで連結する)
---

## Boundary w/ `/sdd-design`

`/sdd-design` = team-shared design decisions (12-section md / input: PRD or NL / direct Edit) vs `/plan` = impl phase breakdown decision (Phase 1/2/... + worktree / input: Design Doc or settled design / PO Agent). 大きい開発は `/sdd-design` → `/sdd-plan` を使い、`/plan` は極小と小さい開発で使う。Detail: `references/design-phase-flow.md` 「Route selection (3 track)」.

## Step 0: Auto-load guidelines (required)

Design + language (auto-detect) + project type guidelines. Detail: `references/command-resource-map.md`.

## Step 1: Scope intake (required)

**Question-suppression default** (`rules/minimize-questions.md` canonical) — prefer immediate recommendation; ask only in exceptions.

1. **File count**: obtain file count and line count via Glob / wc -l
2. **Undecided points**: enumerate edit scope / delete target / decision forks
3. **Immediate decision (default)**: for each undecided point, pick one recommendation from context (CLAUDE.md / memory / repo convention), attach a 1-line basis, and proceed to Step 2
4. **Sub question (exception only)**: AskUserQuestion (**max 1**, plan-specific narrowing; the overall canonical is max 2 = `rules/minimize-questions.md`) fires only when scope input is entirely missing / two recommendations are equally viable / destructive operation or clear conflict with existing policy
5. **Skip condition (→ direct to Step 2)**: typo / 1 symbol rename / 1-2 file edit / explicit instruction / single recommendation confirmed → no question

## Step 2: Execution mode judgment (required)

Overall map (position of every command / skill on the tree): `references/command-tree.md`.

Choose from these options: `inline` / `/dev` / `/workflow <template>` (7 template: review / migrate / research / understand / judge-panel / scan / loop-until-dry) / `/flow N=<n>` / `/flow --auto` / `/goal "<stop>"` / `/loop`. `/goal` is orthogonal (iterative objective-gate tasks only; maker is fixed to `Task(developer-agent)`, see `goal.md`). `/loop` covers cadence / unattended / >5-iteration variants of the same objective-gate tasks (external headless loop).

| Condition | Mode | Why |
|------|---------|------|
| 1 file / 1 symbol / few lines | **inline** (parent Edit direct) | no agent overhead |
| 1-2 files / single task / cross-file coupling | **`/dev`** (1 developer-agent) | delegate only, no parallel |
| N-lens parallel review (diff lens split / adversarial verify) | **`/workflow review`** | dimensions → find → verify pipeline |
| Bulk migrate across N files (pattern → replacement) | **`/workflow migrate <pattern> <replacement>`** | discover → transform (worktree isolation) → verify |
| research (fan out a topic across N angles + synthesize with citations) | **`/workflow research <topic>`** | angles → deep-read top hits → cited report |
| Bulk understanding of N subsystems (entry / deps / data flow map) | **`/workflow understand`** | parallel map, structured return |
| Design majority-vote (N drafts → judge score → winner + graft) | **`/workflow judge-panel`** | independent N drafts, majority vote |
| repo-scale rule sweep (static rule → triage per file:line:rule-id) | **`/workflow scan`** | deterministic rule engine + agent triage |
| Discovery (unknown count) — bug sweep / issue discovery / full edge-case enumeration | **`/workflow loop-until-dry <task>`** | seen set dedupe + K-round dry stop (`references/loop-engineering.md` 「dedupe vs seen」) |
| 3-5 files / high independence / ≥30 lines each / feature impl | **`/flow` N=3-5** | PO/Manager/Dev + 3 Gates, parallel benefit > overhead (60s+) |
| 6+ files / fully independent / feature impl | **`/flow` N=min(file count, 8)** | cap at 8 (session limit) |
| above /flow conditions + fully auto (through PR) | **`/flow --auto`** | AskUserQuestion auto-adopt, auto PR, auto lint-test fix 1× |
| 3+ files / strong cross-file coupling or order dependency | **`/dev` sequential** | parallelism causes conflict |
| 3+ files / only few lines each | **inline consecutive Edit** | overhead unrecoverable |
| iterative + objective gate (test / lint / build exit code) for done | **`/goal "<stop>"`** | maker-checker separation + iteration, Ralph Wiggum guard |
| cadence / unattended / >5 iter + objective gate | **`/loop`** (external headless loop) | fresh context per iteration, no context rot / goal drift |

**`/goal` 4 conditions** (all required; canonical: `commands/goal.md`): iterative task / automated stop-condition (exit code) / token budget absorbs N iter waste / agent holds senior tools (Bash/Edit/Task)

**Anti-patterns**: see canonical `references/auto-delegation-detailed.md`.

### /workflow vs /flow

Comparison table canonical: `commands/workflow.md` 「/workflow vs /flow」.

Decision examples: review **only** → `/workflow review` / review→fix→push auto → `/flow --auto` / migrate N files → `/workflow migrate` / new feature (PO needed) → `/flow` / design majority-vote → `/workflow judge-panel` / discovery (unknown count) → `/workflow loop-until-dry`

N formula (/flow): canonical = `references/PARALLEL-PATTERNS.md#critical-path-reduction-formula`. Refer to the canonical for LPT_makespan + overhead(N) and the 4-tier priority order for T_i estimation. Do not use the legacy shorthand `max(T_i) + 60s`; it is orders of magnitude off from overhead(N).

### `--mode-only` (judgment without design)

`/plan --mode-only <task>` は Step 2 の判定結果だけを 3 行 (Mode / 理由 / 実行) で返して停止する。設計と Phase 分解と plan file の保存は行わない。判定に沿ってそのまま実装へ進むときは `--mode-only` を付けないか `--go` を使う。

## Self-Review (required, 2-stage)

Run before any `/plan` output. Cannot skip. Applies uniformly across PO Agent / Direct / `--update` / `--scope` modes. Stage common definition (including Stage A plan-specific filter + Stage B aggregate view): `commands/review.md` `## Delegation & Self-Review`. Noise discard: `references/on-demand-rules/review-noise-discard.md`.

## Step 3: Handoff to implementation (required)

After saving the plan, always hand off to implementation. Do not leave the chosen execution mode for the user to reassemble by hand.

1. **Always emit a Next command block**: express the Step 2 execution mode as a single copy-pasteable line including the plan file path (e.g., `/dev --plan ~/.claude/plans/2026-07-05_ai-tools_foo.md` / `/flow N=3 --plan <path>` / for `/loop` decisions, two lines `/loop init <name> "<objective>" --gate "<cmd>"` → `/loop run <name>` / for inline decisions, a single line stating "instruct implementation as-is to start inline")
2. **Context to hand off**: keep Requirements / Phase split / mode-decision basis / worktree judgment inside the plan file. The implementation side reads the plan as SoT and does not re-investigate scope or re-decide the mode
3. **`--go` flag**: `/plan --go <task>` without investigation, after emitting and saving the plan, starts implementation directly in the chosen mode (fires the Next command itself, no user confirmation). Only Phases containing destructive operations (delete / migration / force-style) revert to pre-execution confirmation. When investigation occurred, the fresh-session gate below takes precedence and `--go` is disabled in the source session
4. **Also consume pending-improvements**: if the task originates from a Pending entry in `memory/pending-improvements.md`, move that entry to Completed in the turn implementation finishes. Leaving it stale risks re-designing an already-implemented item later (observed 2026-07-20 in pending B)
5. **If retained for cross-check**: to review implementation compliance against the plan, pass the same path to `/review --plan <path>`. The plan is treated as a persistent design document, not a working memo (`references/work-output-routing.md`)

### Investigation fresh-session gate

When investigation resolves uncertainty about scope / cause / existing behavior, the boundary between plan and implementation is hard regardless of context usage. Step 1's file count, explicit scope confirmation, and light lookup of known patterns are not counted as investigation; keep the simple plan / dev flow.

Steps (canonical: `references/investigation-session-contract.md`):

1. Create the handoff artifact from `~/.claude/templates/investigation-handoff.md.template` at an absolute path. Fill scope / evidence / decisions / verification / repo root / full HEAD / `source_session` (the literal `current_session_id` injected by SessionStart)
2. Resolve blockers and placeholders, set the artifact state to `READY_FOR_IMPLEMENTATION`
3. Run the source-mode validator per the contract's `Validator command rule` (mode = `source`)
4. Emit the artifact's `next_command` (`/dev --handoff <absolute-handoff-path>`) for the fresh session and stop here

In the source session, do not start inline / `/dev` / `/flow`. `--go` cannot cross this gate. `/compact` compresses within the same phase and is not a substitute for a fresh session. Do not mark the artifact ready if it is `PREFLIGHT` / `INVESTIGATING`, contains `UNRESOLVED_BLOCKER`, or fails validation — report the gaps and stop.

## Phase = 1 PR (unit of Implementation plan)

repo が作業計画書の template があるとき (例: `.claude/docs/plans/template.md`) は Phase の並びをその template に合わせ、各 Phase の見出し直下に「対象 / 対象外 / 完了条件」を記載する。完了条件は test 名や lint など command で判定できる形を優先する。

Split Phases at "a unit that can ship as one PR". The split criteria are change purpose / dependencies / reviewability — not reducing file count or PR count. Attach a one-sentence "post-merge production state" to each Phase and order them by merge order (`references/on-demand-rules/pr-release-order.md`). If it becomes a chain of three or more, assume the chain operation in `guidelines/writing/stacked-pr-chain.md`. When multiple split shapes are viable and a single recommendation cannot be chosen, ask the user exactly one question before implementation (`rules/minimize-questions.md` condition 3).

## Output format

```
# Design: [feature name]

## Requirements
- [ ] requirement 1

## Architecture
- Pattern: [selection reason]
- Structure: [directory structure]

## Implementation plan
Phase 1: [task] — PR 1 / merge 直後の本番状態: [1 文]
Phase 2: [task] — PR 2 / merge 直後の本番状態: [1 文]

## Execution mode
- Mode: inline / `/dev` / `/workflow <template>` / `/flow N=<n>` / `/flow --auto` / `/goal "<stop>"` / `/loop`
- Basis: [file count / coupling / T_i / overhead comparison + /workflow vs /flow orthogonal judgment + (if /goal or /loop) 4 conditions and stop-condition cmd in 1 line]
- (if /goal only) Stop-condition: [`bats tests/foo` / `npm run lint` etc. exit code as verdict cmd], Hard stops: max-iter=5 / max-token=100000 / timeout=30m
- (if /loop only) Gate cmd + hard stops: max-iter=10 / cost $5 / 60m (canonical: `commands/loop.md`)

## Worktree
- Needed: Yes/No
- Branch name: [propose]

## Next command
[copy-pasteable single line: `/dev --plan <plan-file>` / `/flow N=<n> --plan <plan-file>` etc.]
```

## Plan storage

Save to `plansDirectory` (default `~/.claude/plans`) as `YYYY-MM-DD_[project]_[feature].md`. Loadable via `/reload`.

## Fail behavior

PO Agent launch fail → direct downgrade + warn (propose requirement split when complex) / Guideline load fail → continue with common only, maintainer decides / Serena MCP fail → grep/Glob fallback + accuracy-drop warn / `plansDirectory` write fail → chat output only + guide manual save

**Read-only** (default) — implementation starts via the Next command in Step 3. Only when `--go` is given without investigation does it continue to implementation directly after the plan is finalized.
