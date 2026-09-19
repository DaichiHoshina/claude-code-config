# Design Phase Transitions and Command Roles

Position and transitions of 6 commands from requirements clarification through implementation and knowledge retention.

全体像 (全 command / skill の配置) は `command-tree.md` に集約する。この doc は設計フェーズの遷移条件と skip 判断に限定する。

この遷移に登場する slash command は Claude Code 向けで、Cursor の `~/.cursor/commands` には置いていない。

## Transition diagram

```
[Idea / issue / PRD / Slack]
   │
   ├─(0) Sources scattered ──→ /prepare (read-only, R-n / 現状 / 未確定点)
   │                          │
   │                          ▼ (feeds /prd or /design-doc)
   ├─(1) Design unclear ──→ /brainstorm (Superpowers, interactive refinement)
   │                          │
   │                          ▼
   │                (1.5) Proposal fact-check ──→ /fact-check (実物突き合わせ + 改善 + reviewer-agent review)
   │                          │
   ▼                          ▼
[Requirements visible] ←──────┘
   │
   └─(2) Requirements clarification ──→ /prd (11-persona review, Q1-Q5 decisions)
                         │
                         ▼
                  [PRD confirmed (chat or md)]
                         │
   ┌─────────────────────┤
   │                     ▼
   │  (3) Design doc ──→ /design-doc (12-section md for team sharing)
   │                     │
   │                     ▼
   │              [Design Doc (docs/design/*.md)]
   │                     │
   ▼                     │
(4) Impl plan ──→ /spec-plan (作業計画書: Phase = PR, 責務まで, plans/<issue 番号>/) / /plan (ai-tools 用 plan file, ~/.claude/plans/)
                         │
                         ▼
                  (4.5) Detail design ──→ /spec-detail (Phase n の実装形。既存 code 調査 → method / SQL 方針 / TX。単純な Phase は省略)
                         │
                         ▼
                  (5) Implementation ──→ /spec-dev (Phase of a 作業計画書) / /dev / /flow
                                    │
                                    ▼
                  (5.5) Understand the diff ──→ /explain (read-only, per Phase)
                                    │
                                    ▼
                            [Validation / PR]
                                    │
                                    ▼
                  (6) Knowledge retention ──→ /docs (Notion post)
```

## Command responsibilities

| # | Command | Input | Output | Phase |
|---|---------|------|------|---------|
| 0 | `/prepare` | issue / PRD / related docs | chat (`R-n` list, current code state, open points) | Understand the task |
| 1 | `/brainstorm` | Vague problem | chat (refined requirements) | Diverge / dialogue |
| 1.5 | `/fact-check` | Proposal / candidate list | chat (verdict table + review) | Reality check |
| 2 | `/prd` | Requirements | chat or `--out` md | Requirements definition |
| 3 | `/design-doc` | PRD (`--prd`) or natural language | `docs/design/<slug>.md` (spec 型: 受け入れ条件の表 + 決定事項) | Design (spec) |
| 4 | `/spec-plan` `/plan` | Design Doc (受け入れ条件の表) or pre-designed premise | 作業計画書 `plans/<issue 番号>/*.md` (spec 系。責務まで書き実装形は書かない) / `~/.claude/plans/*.md` (ai-tools) | Impl planning |
| 4.5 | `/spec-detail` | 作業計画書 Phase n | 詳細設計 `<SPEC 名>-phase<n>.md` (既存 code 調査 + 実装形)。単純な Phase は省略 | Detail design |
| 5 | `/spec-dev` `/dev` `/flow` | 詳細設計 / 作業計画書 Phase / plan / task | Code changes | Implementation |
| 5.5 | `/explain` | Phase diff (default: working diff) | chat (explanation the user can restate) | Understanding before PR / next Phase |

## Decision axis for command selection

| Situation | Recommended starting point |
|------|---------------|
| Sources scattered across issue / PRD / Slack, need the whole picture first | `/prepare <issue or PRD>` |
| Requirements and design both unclear | `/brainstorm` |
| Requirements exist but not organized | `/prd` |
| PRD done, need to create design | `/design-doc --prd <path>` |
| Design done, need phase breakdown (PR 単位の作業計画書) | `/spec-plan <path>` (ai-tools 用 plan file なら `/plan`) |
| 作業計画書 done, Phase n の実装形 (method / SQL 方針 / TX) が未定 | `/spec-detail <path> --phase <n>` |
| 作業計画書 done, implement Phase n | `/spec-dev <path> --phase <n>` (詳細設計があれば入力に取る) |
| Design done, no 作業計画書 (単発の変更、または hierarchy が必要) | `/dev` or `/flow` |
| Phase implemented, understand the diff before PR / next Phase | `/explain` (read-only。`/spec-dev` の Phase 完了報告が Next command に出す) |

## Skip judgment

- **PRD not needed**: 1-file / dozens-of-lines edits, bug fixes → skip `/prd`, go to `/dev`
- **Design Doc not needed**: Feature addition within a single service → go directly to `/plan`
- **Plan not needed**: Design is simple enough to implement with `/dev` in one pass
- **Never skip**: Destructive changes / migrations / cross-component features → do not skip; write requirements, design, and tasks as separate artifacts before implementing. Judgment table and failure modes: `../guidelines/common/spec-driven-development.md`

## Q1-Q5 inheritance

The PRD section `1.5 decision rationale` (Q1-Q5) confirmed in `/prd` is **transcribed without re-evaluation** in `/design-doc --prd <path>`. Append only Qs whose premise changes due to design.

## /plan vs /design-doc boundary

| Aspect | `/design-doc` | `/plan` |
|------|--------------|---------|
| Primary purpose | Communicate **design decisions** to the team | Determine **phase breakdown** for implementation |
| Output | spec 型 md (受け入れ条件の表 / 決定事項。`--type full` で 12-section) | Phase 1/2/... and worktree requirement |
| Input | PRD or natural language | Design Doc or pre-designed premise |
| Audience | Reviewers / PM / future self | Implementers (self or developer-agent) |
| Related agent | None (direct Edit) | PO Agent (for complex cases) |

Both needed for large features. Small changes: `/plan` alone is usually sufficient.

## Related

- `../guidelines/writing/design-doc-protocol.md` — DesignDoc 4 steps + 10 patterns + anti-patterns + template selection + self-check 18
- `design-doc-spec-template.md` — spec 型 template (`/design-doc` の既定)
- `design-doc-template.md` — Full 12-section template (`--type full`)
- `document-iteration-patterns.md` — Phase progression and revision patterns for rewrites (dynamic supplement)
- `decision-quality-checklist.md` — 5-question decision quality check
- `performance-issue-template.md` — Performance improvement issue: measure → analyze → staged improvement → load test
- `review-patterns-universal.md` — Common review findings for design decisions and SQL dialects
