---
allowed-tools: Read, Glob, Grep, Edit, MultiEdit, Write, Bash, Task, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, TaskGet, mcp__serena__*, mcp__context7__*
argument-hint: "[--inline|--quick|--plan <file> [--phase <n>]|--handoff <path>] <task-description>"
description: 既定は developer-agent 委譲。1 symbol の修正のみ inline。flag の詳細は本文の Default delegation table を参照する
---

## /dev - Implementation mode

> When to use: `/dev` = impl phase only, no Agent Team (Team hierarchy **only via `/flow`**) / `/flow` = auto task-type + PO→Manager→Dev×N hierarchy. When uncertain → `/flow`.

## Step -1: Mode auto-check (skip on `--plan` / `--handoff` / `--quick` / `--parallel`)

Apply `commands/plan.md` Step 2 の条件表 to the current task scope before Step 0, and re-fire as `/flow` when the scope is large.

1. Measure scope via Glob (file count) and task independence. If it lands in a `/flow` row (3+ files fully independent, or 3-5 files high independence ≥30 lines each, or 6+ files), re-fire the same task text as `/flow <task>` and stop without asking (`rules/minimize-questions.md` の推奨即決 default); output the judgment basis as 1 line in chat first
2. Otherwise (1-2 files / single task), proceed to Execution flow as-is

## Default delegation

On `/dev` launch, delegate to `Task(developer-agent)` by default (model canonical: `agents/developer-agent.md` frontmatter + `references/model-selection.md`).

| Flag | Behavior |
|---|---|
| (none) | `developer-agent` delegation (default) |
| `--inline` | parent inline execution (1-symbol fix only) |
| `--quick` | low-cost model delegation, token-saving priority (short prompt) |

## Options

```bash
/dev --quick <task>      # Fast mode (token-saving, 1-2 files)
/dev --parallel <task>   # Worktree parallel (no PO/Manager, developer-agent ×N)
/dev <task>              # Normal (developer-agent delegation)
/dev --plan <file> [--phase <n>]  # plan / 作業計画書 intake, Phase n only (skip re-analysis & confirm)
/dev --handoff <path>    # Fresh-session investigation handoff intake
```

## Investigation handoff intake (`--handoff`)

`--handoff <absolute-path>` is accepted only in a fresh implementation session, separate from the investigation source session. Follow `references/investigation-session-contract.md` (`Validator command rule`, mode = `implementation`) before implementation.

- Accept only `READY_FOR_IMPLEMENTATION`; do not re-investigate `PREFLIGHT` / `INVESTIGATING` / `UNRESOLVED_BLOCKER` (report and stop)
- After validation succeeds, adopt the artifact's decisions/scope/verification method as SoT; do not re-scope, re-diagnose, or re-judge the mode. If code drift breaks the premise even within the explicit scope, stop as a mismatch rather than returning to investigation
- `/compact` may compress context within the implementation phase only; it is not a substitute for the fresh-session validation

## Plan intake (`--plan` / auto-detect)

Take the output of `/plan` as input, skip scope re-analysis and pre-run confirmation, and enter implementation directly.

| Input | Behavior |
|---|---|
| `--plan <file>` | Read the plan and adopt Requirements/Phase/mode-selection rationale/worktree decision as-is. Skip Execution flow 2-4 (re-analysis/re-planning/user confirm), implement **Phase 1 only** |
| `--plan <file> --phase <n>` | Implement only Phase n (default n=1). See steps below |
| No flag + `/plan` already run in the same session | Adopt that plan the same way (latest matching file in plansDirectory) |
| No plan | Normal flow (Execution flow 1-6) |

### `--phase <n>` steps

1. Register only that Phase's 対象 with TaskCreate
2. Scope guard: stop and report before touching a file listed in the Phase's 対象外, or a file outside 対象 that the plan did not anticipate (do not widen the scope)
3. Completion check: when the Phase has 完了条件 written as commands, run them and finish only when all pass (otherwise fall back to Execution flow 7). Self-contradiction (a task names a 対象外 file): finish the other in-scope tasks, run 完了条件, then stop without marking the Phase done and ask to fix the plan and re-run the same `--phase`
4. Otherwise, at the end of the Phase, stop and print `Next: /explain` (user reads the diff first, then fires `/sdd-implement <path> --phase <n+1>` or `/dev --plan <file> --phase <n+1>`; print "all Phases done" when none remain) — never continue into the next Phase in the same run

Treat the plan as SoT and do not re-judge the mode. `/sdd-plan` (作業計画書) plans are accepted the same way (`/sdd-implement <path> --phase <n>` wraps this intake); Phase heading + 対象 / 対象外 / 完了条件 are the scope.

- End-of-Phase report: when the Phase lists acceptance criteria (quoted), print one line `満たした条件: <条件の文の引用> / 残り: <同>` (traceable without re-reading the plan), then print `/explain` (user reviews the Phase's diff before the PR and the next Phase)
- Drift detection: if the plan and actual code diverge (file missing / symbol renamed etc.), return to re-analysis and report the drift in one line
- Destructive Phases (deletion / migration / force ops) require pre-run confirmation regardless of the plan

## --parallel spec

Developer×N worktree parallel w/o PO/Manager。並列度評価と worktree proposal は強制、worktree creation は user 確認要。公式・`--auto` の skip 4 conditions・cleanup policy は `references/PARALLEL-PATTERNS.md`。Gate A/B (parallel self-review) は `/dev --parallel` に非適用 (`/flow --parallel` 専用)。

## --quick

用途: 1-2 files typo / 小さな bug / 数行変更。**token 節約 (短 prompt)、Agent Team なし、confirm 最小**。flow: 対象 file 特定 → fix (Serena) → verify (lint/type) → commit 提案。3+ files または設計判断が必要なら通常 `/dev` か `/flow` へ。

## Thinking mode

**Always ultrathink** — 複雑な実装は着手前に深く考える。quick fix を避け、設計意図を掴んでから書く。

## Step 0: Guideline loading (conditional)

**Always-on (cannot skip)**: When adding or editing code comments (`// ` `# ` `-- ` `/* ` `<!-- `), decide from the hook-injected summary and Read the canonical `guidelines/writing/code-comment.md` only when unsure (do not skip even with `--quick`).

**Always-on (cannot skip)**: When naming a new function, variable, or type, follow `guidelines/common/code-quality-design.md` "Naming Criteria" / "Naming Shape" and the target language's `guidelines/languages/<lang>.md` "Naming Conventions". Grep the same layer for names with the same role and use the majority word (do not skip even with `--quick`).

| Scenario | Action |
|----------|--------|
| `--quick` | skip (save tokens; Read only the code-comment canonical) |
| 1-2 files, minor | skip OK (if pattern known; Read only the code-comment canonical) |
| new feature, design decision | `load-guidelines` skill 呼び出し (summary ~2.5K tokens 推奨、detail は `(full)` で ~5.5K tokens。command でなく Skill tool 経由) |

Detailed mapping: `references/command-resource-map.md`.

## Execution flow

1. Load guidelines
2. Validate investigation handoff (when `--handoff`). On success, skip analyze; on failure / `PREFLIGHT` / `INVESTIGATING` / `UNRESOLVED_BLOCKER`, report + stop
3. Analyze code w/ Serena MCP (skip on plan / handoff intake)
4. Plan w/ TaskCreate (on plan intake = the plan's Phase; on handoff intake = register the artifact's implementation scope as-is)
5. Confirm w/ user (skip on plan / handoff intake; treated as already approved)
6. Implement
7. Run lint/test

## Priority

1. Type-safety (any/as forbidden) 2. Guideline compliance 3. Architecture patterns 4. Testability

## Smoke test completion-report template (required)

The completion report must include smoke-test results (CLAUDE.md `## Definition of Done` "1 smoke test required"; prevents "re-check whether everything is done" churn).

| State | Format | Example |
|---|---|---|
| 実行済 | `Smoke test: <cmd> 実行、<結果 1 行>` | `Smoke test: bats tests/unit/foo.bats 実行、12/12 pass` |
| 未実行 | `Smoke test: 未実行 (理由: <1 行>)` | `Smoke test: 未実行 (理由: GUI 起動不能で手動確認要)` |

`未実行` の理由は具体的なものに限る (「時間がない」等の主観理由は不可)。有効な理由: environment unavailable / GUI・TUI は自動 smoke test 不可 / test 対象を特定できない / config-only・doc-only の変更。config-only / doc-only は変更 file 名 + `git diff --stat` 1 行要約で代替する。

## Post-impl quality checks (required)

After completion: `/lint-test` auto-detects lang + runs all checks (lint/typecheck/test/build). 0 errors → report done, else → try auto-fix.

| Scenario | Action |
|----------|--------|
| 2 consecutive same-approach failures | If an objective gate (test / lint exit code) can be defined, propose `/loop` (fresh-context iteration has a higher success rate than retrying in the same context); if not, suggest `/clear` & stop, request replan |
| `--quick` unexpected error | fallback to default model, continue minor fixes |
| Serena MCP fails | degrade to grep/Read, warn |

PushNotification: notify only if task > 3min (`[dev] {task} done`).

## Next actions

```
/dev done
  → /lint-test → /test → /review → /git-push
  → on error: /diagnose
```

## Related commands

| Command | Relation |
|---------|----------|
| `/refactor` | structure improvement w/o behavior change. Can run after `/dev` |
| `/lint-test` | CI-equivalent checks. Recommended after `/dev` |

**Pre-impl user confirmation required (skip on plan / validated handoff intake; confirm only destructive operations). Use Serena MCP for code ops.**
