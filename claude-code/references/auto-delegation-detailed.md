# Auto-Delegation — Detailed Spec

Detail for CLAUDE.md `## Auto-Delegation`. CLAUDE.md keeps default declaration + cross-ref only. All thresholds / trigger table / inline exceptions are canonical here.

---

## Decision principle (top priority)

Delegate on uncertainty. Under-delegation risk > over-delegation cost. Parent handles orchestration / judgment only; all actual work (write / refactor / commit) goes to subagents (each agent's frontmatter is canonical for the model it delegates to; see `references/model-selection.md`). "If told to do it, the subagent does it" principle (per user direction 2026-05-22). Verification: parent inline default (build / typecheck required for compiled language projects goes to subagent; details: `references/developer-agent-delegation-prompt.md`).

## Time-first (top priority)

Fastest makespan wins for all routing. Always fire in parallel except physical constraints (same-file edit / result dependency). Cap default 8 (parent + Dev×8 = 9 concurrent). Adopt if makespan improvement ≥5%. When in doubt: parallel + delegate (under-parallel risk > over-parallel cost). Details: `references/PARALLEL-PATTERNS.md`

**Do not prematurely conclude that multiple independent edits to the same file cannot run in parallel.** Serializing different regions of one file across multiple agents is slow. Have agents **generate patches (old_string/new_string pairs) in parallel in read-only mode**, then **let the parent apply them sequentially and verify once** to parallelize without write conflicts. Worktree separation is unnecessary (worktrees are only for concurrently mutating disjoint file sets). If the parent hesitates, hand off to `/flow` and let the Manager decide parallelism, split, and whether a worktree is needed.

## Bundle prohibition (split obligation)

Never bundle 2+ domains (different file groups / root causes / verify systems) in 1 prompt. Fire per-domain as multiple Agent tool_use in a single message. Bundling causes sequential processing inside subagent, cumulating makespan.

### Per-agent scope cap (no single-Task overload)

Scope cap per Task prompt is 3-5 files / 1-2 lenses (values from CLAUDE.md). Beyond that, split into N Agents and fire in parallel in a single message. Overloading causes context overflow that degrades later files, summarizes output, collapses lens orthogonality, and inflates retry cost on failure. Even in a serial chain (PO→Manager→Dev), fan out within a step when it contains multiple files / lenses (do not mistake serial for a single monolithic hand-off). Pre-fire self-check: (1) Can an agent write this prompt in one pass? — If No, split. (2) Are there 2+ splittable units within this step? — If yes, fan out within the step.

### "Speed-first" axis check

When the user specifies "speed / fastest / fast / quick", pin down at the outset which axis they mean: implementation speed (time-to-merge), effect speed (KPI improvement lead time), or response speed (1-turn latency). If context makes it obvious, skip the confirmation and proceed with "chose X for implementation speed" explicit. Delegation carries agent startup overhead (tens of seconds to minutes), and on the implementation-speed axis a single-file micro-fix is fastest inline. Misreading the axis leads to plan rework.

## Parallel fire format (mandatory)

For N independent tasks: **place N `Agent` tool_use calls in a single assistant message**. Repeating 1-message-1-Agent over N messages serializes on previous agent's STOP, reducing peak concurrency to 1 (formula PASS / cap 8 does not guarantee simultaneity). **The act of bundling tool_use in 1 message IS the parallelization**; cap/formula only sets the upper limit on fire count. Verify: `scripts/flow-baseline.sh --summary` `peak_concurrency distribution` — heavy 1s indicates serialization.

### Upfront decomposition (before the FIRST Task fire)

Enumerate ALL independent tasks **before firing the first developer-agent**, and include every independent task in the first bundle message. The fire-one-read-result-fire-next loop drops peak concurrency to 1 (30d measured: 10 of 22 flow runs at peak=1). Hook injects `[bundle-pre-check]` on the first dev fire as a reminder — at that point the parallelization decision for the current turn is already made, so enumeration must happen at planning time, not after.

#### `scope: i/N` declaration

- Format: write `scope: i/N` (example `scope: 2/3`) near the top of each Task prompt
- N = count of independent tasks enumerated above, i = this task's 1-based position
- N=1 (single task, no fan-out) may omit the declaration
- A false `scope: 1/1` used to hide an independent task from the bundle is forbidden
- Same abuse class as `serial_reason` misuse below
- A fire declares N≥2 but the actual bundle that turn was solo (size 1)
- The hook then warns `scope_declared_mismatch`
- Logged to `bundle-violation-warn.log` as an audit signal, not a hard block

### serial_reason declaration (dependent sequential fires)

A sequential developer-agent fire that **depends on a previous agent's output** (implement → reviewer reject → re-implement / patch apply → follow-up fix) is legitimate, not a bundle violation. Declare it by writing `serial_reason: <dependency, 1 line>` in the Task prompt. The hook excludes declared fires from the sequential counter (no warn / no hard block) and records `serial_reason_declared` in `bundle-violation-warn.log` for audit.

- Misuse ban: writing serial_reason on an independent task to dodge the counter is forbidden — independent tasks go in the bundle.
- Without the declaration, 3 cumulative sequential fires per session hard-block (PO Gate v2). Legitimate chains hitting the block was the main driver of "delegate feels slower than inline" (2026-07-04/05: 3 sessions blocked).

## Parent pre-delegation obligation

Pre-delegation steps: see `references/orchestrate-mode.md` 「Pre-delegation」.

### Target Anchor Gate before Explore fan-out

Before choosing the Explore fan-out count, the parent must verify the shared target: absolute worktree root, expected branch or an explicit detached-readonly reason, full HEAD, and 1-3 representative existing file/symbol anchors. Repo-wide investigation remains valid when the prompt records an explicit override reason plus representative root-level evidence. Only after this gate passes may the parent select up to 4 Explore agents, matching the defined `explore1`-`explore4` specializations.

Every Explore prompt must carry the same `run_id`, a unique `scope_id`, `expected_count`, worktree path/branch/HEAD, anchor evidence, bounded scope paths/questions/excludes/`stop_when`, and a budget class. Budget classes bound the number of questions, findings, evidence references, and stopping conditions; they must not impose fixed token limits.

If the shared worktree identity or anchor evidence fails in any scope, stop the run. Re-run parent preflight and fresh-launch only the scopes still required against the corrected target; do not resume every agent with corrected target data.

## Agent fire self-review (required before Task tool)

Self-check parallelization before firing Task tool. Checklist canonical: `references/PARALLEL-PATTERNS.md` (do not duplicate in CLAUDE.md). Hook auto-injects self-review reminder as additionalContext on Task fire.

## Inline exceptions (no delegation)

Q&A / already-read file check (file already Read in same session, no additional Read needed; additional Read required → count toward throttle) / dry-run / **1 symbol inside body replace** / **1 section edit** / **same-file 1 config value change** / **expected LLM execution <20s** / **read-only command 1 item** (`git status` / `ls` / `cat` / `wc -l` / etc)

**Grey zone (20–60s expected):** delegate launch floor is 22s startup (`performance-insights.md`). So a task that finishes inline in 20–60s often costs more if delegated. Rule: default inline when it is a single-file / single-symbol edit AND no commit. Delegate only when 2+ files are touched. Above 60s: delegate is clearly better.

## Inline exception throttle

2 consecutive inline exceptions in same session → next edit-class op is **mandatory** developer-agent delegation (reset counter after delegation). Investigation phase (Q&A / dry-run excluded; Read/Bash for investigation only): cumulative ≥5 → switch to `explore-agent`.

Read-only local queries (`git status` / `ls` / single `grep` / `find_symbol`) do NOT count toward this throttle. They are the cheapest, highest-frequency path, so counting them would push an `explore-agent` launch too early and add cost instead of saving it.

Note: **impl** = logic addition / new file / multi-symbol edit; **edit** = any of 2+ files, 10+ lines, or 2+ symbols; **commit-bearing** → delegate immediately (no inline commit). Violations recorded in feedback memory.

Violation-prone patterns (observed 2026-06-04): (1) self-classifying a new file as "lightweight housekeeping" and writing it inline (2) counting a single bash that touches 2+ files (`git mv A B && git mv C D` / `find ... -delete` etc.) as one inline op (3) forgetting to reset the counter after hitting 2 consecutive and continuing inline. Delegate new files and 2+ file operations even when you could write the content yourself. Count "inline cumulative N/2" right after each inline op, and force delegation for edit-class ops once N reaches 2. Colloquially triggered housekeeping like "do it all" or "fix it" carries strong self-judgment bias and produces most of the violations.

Scope boundary: tasks matching the CLAUDE.md Auto-Delegation table row "iteration-based (CI fail / fixture / test chain / review feedback) → inline-fixed" are exempt from this throttle (inline-fixed takes precedence). The throttle applies only to sequences of one-off housekeeping / scattered edits.

## Auto-launch trigger table

| Trigger | Auto-launch |
|---|---|
| **All impl / edit / commit outside exceptions above** | `developer-agent` auto (`Task` tool) |
| broad search (3+ query / 3+ domain) | `explore-agent` parallel auto |
| review request / PR check | `reviewer-agent` auto (or `/review`) |
| unknown bug cause / recurring bug | `Skill(root-cause)` (5 Why、`commands/diagnose.md`) |
| design decision / large plan / multi-phase | `po-agent` auto (or `/plan`) |
| multi-stage task (investigate→design→impl→verify) | `/flow` hierarchy (PO→Manager→Dev→Reviewer) |
| 10+ file bulk processing | `claude -p` fan-out (`references/fanout-recipes.md`) |
| **bulk / exhaustive / large-scale readonly** | `explore-agent` (read-only) or `developer-agent` (edit) — mandatory Sonnet delegate, parent sample reduction prohibited |

**Auto-launch は Skill tool 呼び出しで行う (文章による再現で代替しない)**: `commands/*.md` (`/dev` / `/flow` / `/mode` / `/spec-plan` 等) は Skill tool の available skills 一覧にも同時登録されている。上表の判定を「記憶している判定表を思い出してなぞる」で済ませず、実際に `Skill(skill="mode", args="<task>")` のように呼び出す。user が `/name` を明示しない実装依頼でも同様で、command 名の明示有無は発火経路を変えない (2026-09-17 実踏: 「/dev や /flow を指定しない使い方にしたい」という要望に対し、command 定義が既に skill としても呼べることを確認した)。

## Model default switch history (2026-06-29)

- Before switch: Opus 4.7 default
- After switch: Sonnet 4.6 default
- From 2026-07: session default = Fable 5 (`references/model-selection.md` canonical). Delegation-target model is canonical in each agent frontmatter
- Purpose: cost reduction (Opus cache_read $1.50/M → Sonnet $0.30/M, 1/5)
- Tasks that should use Opus 4.7:
  - deep design (architecture decisions / trade-off analysis)
  - cross-file review (10+ files)
  - `/flow` PO/Manager orchestration (judgment hierarchy)
  - cases requiring Manager hallucination prevention
- Switch method: `/model opus` at session scope (agent frontmatter stays fixed at sonnet; manager-agent hallucination mitigation is already covered by forced literal echo)
- Current state (2026-07-19): the Opus 4.7 use cases above have migrated to Fable 5 (session default) and `/fable` delegation. This section remains as history log (canonical: `references/model-selection.md`)

## Subagent silent-fail guard details

Tool constraints in subagent context:

- `AskUserQuestion` is not usable (parent context only)
- Permission-prompt tools (Edit / Write / parts of Bash) auto-deny and **silent fail**
  - No error, appears as status success, but nothing is actually written
  - Source: [claudefa.st sub-agent-best-practices (web search 2026-06-24)](https://claudefa.st/blog/guide/agents/sub-agent-best-practices)

### Handling

- Escalate approval-gated edits / decision forks to the parent
- Escalate format: `status: blocked` + `issues_blocking[]` (concrete block reason / required user judgment)
- Subagent-side canonical: `agents/developer-agent.md` 「Silent-fail guard」

## killed / stopped notice does not guarantee agent stop

Even when a Task tool `status: killed` or "stopped by user" arrives, the agent may keep running in the background and finish through commit.

**Why**: real case 2026-07-19. `npm run test:bats:unit` output buffering made it look unresponsive, but the agent was alive. Trusting the notice and handing off caused a separate completion notice to arrive later, nearly producing duplicate work.

**How to apply**:

- Do not immediately re-fire or hand off on receiving a stop notice
- First check the actual change/commit state with `git status` / `git log`
- If a completion notice arrives after hand-off, verify content match with `git diff <before> <after>` before integrating
