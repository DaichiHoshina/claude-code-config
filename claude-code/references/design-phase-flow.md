# Design Phase Transitions and Command Roles

Position and transitions of 6 commands from requirements clarification through implementation and knowledge retention.

全体像 (全 command / skill の配置) は `command-tree.md` に集約する。この doc は設計フェーズの遷移条件と track 選択に限定する。

この遷移に登場する slash command は Claude Code 向けで、Cursor の `~/.cursor/commands` には置いていない。

## Transition diagram

```
[Idea / issue / PRD / Slack]
   │
   ├─(0) Sources scattered ──→ /prepare (read-only, R-n / 現状 / 未確定点)
   │                          │
   │                          ▼ (feeds /prd or /spec-design)
   ├─(1) Design unclear ──→ /brainstorm (Superpowers, interactive refinement)
   │                          │
   │                          ▼
   │                (1.5) Proposal fact-check ──→ /fact-check (実物突き合わせ + 改善 + reviewer-agent review)
   │                          │
   │                          ▼
   │                (1.6) Premise grill ──→ /grill (設計案の前提の不足を詰問、read-only)
   │                          │
   ▼                          ▼
[Requirements visible] ←──────┘
   │
   ├─ 極小 (1 file / 1 symbol / typo) ──→ /dev ──→ [Validation / PR]
   │
   └─(2) Requirements clarification ──→ /prd (11-persona review, Q1-Q5)
                         │
                         ▼
                  [PRD confirmed (chat or md)]
                         │
   ┌────────────────────┴─────────────────────┐
   │ 小さい開発                             │ 大きい開発
   ▼                                        ▼
(4) /plan (plan file 1 本)            (3) /spec-design
   │                                        │
   │                                        ▼
   │                                 [Design Doc (docs/design/*.md)]
   │                                        │
   │                                        ▼
   │                        (4) /spec-plan (作業計画書: Phase = PR)
   │                                        │
   │                                        ▼
   │                        (4.5) /spec-detail (単純な Phase は省略)
   │                                        │
   ▼                                        ▼
(5) /dev | /flow                      (5) /spec-dev (Phase 1 つ)
   │                                        │
   │                                        ▼
   │                        (5.5) /explain (read-only, per Phase)
   │                                        │
   └────────────────────┬─────────────────────┘
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
| 1.6 | `/grill` | 確定前の設計案 | chat (前提の不足と未決定点) | Premise check |
| 2 | `/prd` | Requirements | chat or `--out` md | Requirements definition |
| 3 | `/spec-design` | PRD (`--prd`) or natural language | `docs/design/<slug>.md` (spec 型: 受け入れ条件の表 + 決定事項) | Design (spec) |
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
| PRD done, need to create design | `/spec-design --prd <path>` |
| Design done, need phase breakdown (PR 単位の作業計画書) | `/spec-plan <path>` (ai-tools 用 plan file なら `/plan`) |
| 作業計画書 done, Phase n の実装形 (method / SQL 方針 / TX) が未定 | `/spec-detail <path> --phase <n>` |
| 作業計画書 done, implement Phase n | `/spec-dev <path> --phase <n>` (詳細設計があれば入力に取る) |
| Design done, no 作業計画書 (単発の変更、または hierarchy が必要) | `/dev` or `/flow` |
| Phase implemented, understand the diff before PR / next Phase | `/explain` (read-only。`/spec-dev` の Phase 完了報告が Next command に出す) |

## Route selection (3 track)

規模で 3 つの track に分ける。上の track ほど成果物が増え、下の track ほど code へ早く着く。

| Track | 当たる変更 | 遷移 | 成果物 |
|---|---|---|---|
| 極小 | 1 file / 1 symbol / typo / 数行の bug fix | `/dev` (`/plan` Step 2 が `inline` を返すこともある) | code の diff だけ |
| 小さい開発 | 単一 service 内の機能追加 / 数十行の修正 | `/prd` → `/plan` → `/dev` or `/flow` | PRD (chat でよい) + plan file |
| 大きい開発 | 複数 service にまたがる / API / DB / 画面が変わる / 破壊的変更 | `/prd` → `/spec-design` → `/spec-plan` → `/spec-detail` → `/spec-dev` → `/explain` | PRD / Design Doc / 作業計画書 / 詳細設計 |

- 極小では PRD も plan file も作らない。判断の無い変更で成果物を増やさない
- 小さい開発では Design Doc と作業計画書を作らない。spec 系 4 本は大きい開発専用で、command 名の `spec-` 前方一致がその見分けになる
- 小さい開発の `/prd` は chat へ出す形でよく、md にしなくてよい (`commands/prd.md`)
- 実装の進め方 (inline / `/dev` / `/flow` N / `/workflow`) は `commands/plan.md` Step 2 の実行 mode 判定表が canonical で、この表では決めない
- **小さい開発へ下げない変更**: 破壊的変更 / migration / 複数 component にまたがる機能は、規模が小さく見えても大きい開発の track で扱う。判定表と失敗 pattern: `../guidelines/common/spec-driven-development.md`

## Q1-Q5 inheritance

The PRD section `1.5 decision rationale` (Q1-Q5) confirmed in `/prd` is **transcribed without re-evaluation** in `/spec-design --prd <path>`. Append only Qs whose premise changes due to design.

## /plan vs /spec-design boundary

| Aspect | `/spec-design` | `/plan` |
|------|--------------|---------|
| Primary purpose | Communicate **design decisions** to the team | Determine **phase breakdown** for implementation |
| Output | spec 型 md (受け入れ条件の表 / 決定事項。`--type full` で 12-section) | Phase 1/2/... and worktree requirement |
| Input | PRD or natural language | Design Doc or pre-designed premise |
| Audience | Reviewers / PM / future self | Implementers (self or developer-agent) |
| Related agent | None (direct Edit) | PO Agent (for complex cases) |

Both needed for large features. 小さい開発では `/spec-design` を使わず `/plan` だけで進む (「Route selection (3 track)」)。

## Related

- `../guidelines/writing/design-doc-protocol.md` — DesignDoc 4 steps + 10 patterns + anti-patterns + template selection + self-check 18
- `design-doc-spec-template.md` — spec 型 template (`/spec-design` の既定)
- `design-doc-template.md` — Full 12-section template (`--type full`)
- `document-iteration-patterns.md` — Phase progression and revision patterns for rewrites (dynamic supplement)
- `decision-quality-checklist.md` — 5-question decision quality check
- `performance-issue-template.md` — Performance improvement issue: measure → analyze → staged improvement → load test
- `review-patterns-universal.md` — Common review findings for design decisions and SQL dialects
