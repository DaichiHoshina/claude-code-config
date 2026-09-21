# References Index

On-demand index from CLAUDE.md.

**Not listed** (`ls references/` to find):
- `*-template.md` (exception: `performance-issue-template.md` included as operational procedure)
- `*-OPPORTUNITIES.md` (feature backlog tracker, unsuitable for index)
- `*-detailed.md` (CLAUDE.md から直接参照される detail 系: `auto-delegation-detailed.md` / `editing-rule-detailed.md` / `session-efficiency-detailed.md` / `memory-clean-detail.md`)
- `review-pr-memory.md` — `/review` が PR 対象のときだけ読む per-angle status の read → append 手順
- `pr-review-thread-api.md` — `/self-review-fix` と `review-reply-draft` が共有する review thread の取得 / bot 判定 / reply / resolve の手順
- `retrospectives/` / `on-demand-rules/` (reference dir directly)
- `INDEX.md` (this file)

## Model Selection / Session Management

| Topic | File |
|-------|------|
| Model selection / effort | `model-selection.md` |
| Opus 5 移行時の prompt 見直し作業指示 | `opus5-prompt-migration.md` |
| Session management | `session-management.md` |
| Checkpoint / Rewind | `checkpoint-rewind.md` |
| `claude -p` fan-out | `fanout-recipes.md` |
| Agent cost measurements | `performance-insights.md` |

## Triggers / Commands

| Topic | File |
|-------|------|
| Command / skill 全体見取り図 (幹 + 3 根の tree) | `command-tree.md` |
| Full natural language trigger list | `natural-language-triggers.md` |
| /explain 後に使う読者レベル別 1 枚 HTML 図解の prompt template (手動運用、flag 昇格前) | `explain-audience.md` |
| Review command usage guide | `review-commands.md` |
| Review mode details (deep / multi aggregation) | `review-modes-advanced.md` |
| Command × resource map | `command-resource-map.md` |
| Guideline auto-trigger list | `guideline-triggers.md` |
| Loop engineering (14-step roadmap, 4-condition test, Ralph Wiggum guard) | `loop-engineering.md` |

## Workflows

| Topic | File |
|-------|------|
| Design phase transitions / 規模で分かれる 3 track (極小 / 小さい開発 / 大きい開発) の選択 | `design-phase-flow.md` |
| `/spec-plan` の目的と実装の対応 (表だけで記載する理由と書き方) | `purpose-traceability.md` |
| 設計駆動フローの Why (大きい開発の spec 系 4 本で、段階の境界がそこにある理由) | `ai-design-driven-flow.md` |
| Compounding Engineering | `compounding-engineering-cycle.md` |
| Parallel execution patterns (worktree decisions) | `PARALLEL-PATTERNS.md` |
| /flow 詳細 orchestration 仕様 (pre-delegation / 3 Gate 詳細) | `flow-orchestration.md` |
| Orchestrate mode (parent-led delegation supplement) | `orchestrate-mode.md` |
| Parallel self-review (Gate C 12-lens) | `parallel-self-review.md` |
| Workflow tool templates (fan-out / pipeline / 多数決) | `workflow-templates.md` |
| Agent Team interface schema (canonical) | `agent-team-contract.md` |
| Agent output schema (status / confidence trailer) | `agent-output-schema.md` |
| Developer agent delegation prompt (canonical) | `developer-agent-delegation-prompt.md` |
| bats editing canonical rules (for Developer agents) | `bats-test-writing.md` |
| Hook event payload map | `hook-payload-map.md` |
| Work output routing (報告先の振り分け) | `work-output-routing.md` |
| Investigation → implementation session 分離 contract | `investigation-session-contract.md` |

## Thinking Frameworks

| Topic | File |
|-------|------|
| AI thinking essentials | `AI-THINKING-ESSENTIALS.md` |
| Design decision quality checklist | `decision-quality-checklist.md` |

## Architecture & Design Patterns

| Topic | File |
|-------|------|
| Clean Architecture (layer / dependency direction) | `../guidelines/design/clean-architecture.md` |
| Domain-Driven Design (aggregate / bounded context) | `../guidelines/design/domain-driven-design.md` |
| CQRS (read/write split / sync strategies / maturity levels) | `../guidelines/design/cqrs.md` |
| Async job patterns (queue selection / fan-out) | `../guidelines/design/async-job-patterns.md` |

## Documentation Writing

| Topic | File |
|-------|------|
| DesignDoc writing and granularity | `../guidelines/writing/design-doc-protocol.md` |
| DesignDoc spec 型 template (`/spec-design` 既定) | `design-doc-spec-template.md` |
| Writing self-check protocol (閾値 / loop 上限 canonical) | `writing-check-protocol.md` |
| Performance improvement issues | `performance-issue-template.md` |
| Universal review patterns | `review-patterns-universal.md` |
| Document rewrite phases | `document-iteration-patterns.md` |
| Writing common principles | `../guidelines/writing/PRINCIPLES.md` |
| Writing supplement patterns (rewrite phases / textlint) | `writing-patterns.md` |
| Writing sentence-level rules (文長 / ひらく漢字 / 漢数字 等 detail) | `writing-sentence-rules.md` |

## Serena / MCP

| Topic | File |
|-------|------|
| Serena tool 用途マップ (per-agent canonical) + 事故防止ルール | `serena-tool-map.md` |

## Other

| Topic | File |
|-------|------|
| 機体固有 local file の一覧と点検 (新 machine 移行時に必ず見る) | `local-files-setup.md` |
| Cron / launchd job catalog (常駐 job SoT) | `cron-jobs.md` |
| sleep cron 仕様書 (夜間 mine → 朝 triage 一式の canonical) | `sleep-cron-spec.md` |
| Memory usage guide | `memory-usage.md` |
| Memory relocation pattern (auto-memory → project-scoped path) | `memory-relocation-pattern.md` |
| Boris 流開発スタイル対応表 | `boris-style-mapping.md` |
| Claude Code official best practices (JA) | https://code.claude.com/docs/ja/best-practices |
