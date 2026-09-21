---
allowed-tools: Bash, Read, Write
description: issue / PR / Jira / Notion / Slack への短文投稿 — draft (結論先頭、内容に合う構造) → self-check → 表示。投稿は user 確認後
argument-hint: "<target> [topic-or-context]"
---

# /post-comment - Short-form post draft + self-check

Generate a draft from confirmed facts, check it internally, and display the candidate text. Follow `guidelines/writing/PRINCIPLES.md` 「文章生成の不変条件」. **Post execution not here** (user runs via gh/mcp).

## Arguments

```
/post-comment [target] [topic or context]
```

| Target | Description |
|--------|-------------|
| `gh-issue` | GitHub issue creation (title + body) |
| `gh-issue-comment` | comment on GitHub issue |
| `gh-pr` | GitHub PR creation (title + body) |
| `gh-pr-comment` | comment on GitHub PR |
| `gh-pr-review` | GitHub PR review comment |
| `jira` | Jira ticket creation (summary + description) |
| `notion` | Notion page (short note/notification) |
| `slack` | Slack notification |

if target omitted, ask user.

## Flow

### Step 0: Writing memory pre-check (mandatory)

draft 生成前に `mcp__serena__list_memories` または `~/.claude/projects/${PROJECT_SLUG}/memory/MEMORY.md` (`PROJECT_SLUG=$(pwd | sed 's|/|-|g')`、`commands/reload.md` と同方式) を確認、`writing_failure_*` で関連ありそうなら read。target が gh-issue / gh-pr 系なら `writing_failure_link_overdose` / `writing_failure_compound_noun_stack` 必読相当。

### Step 1: draft generation

結論・理由・次の行動から、その投稿に必要な要素だけを記載する。短い返信に `Conclusion` / `Rationale` / `Next Action` 見出しを付けず、自然な本文にする。入力や確認済み資料にない担当者・期限・影響・原因を補わない。

For `gh-issue` / `gh-pr` / `jira`: generate title/summary (≤80 chars) separately.
Detailed logs, stack traces → `<details>` folding.

### Step 2: self-check

| # | Item | Pass? |
|---|------|-------|
| 1 | First line says "what should reader decide/do?" | ✓/✗ |
| 2 | structure scannable? (headings / bullets let reader skim; no wall of text) | ✓/✗ |
| 3 | conclusion / rationale / next action all present? | ✓/✗ |
| 4 | evaluative words (appropriate/critical/required) backed by 1-line rationale? | ✓/✗ |

判定は内部で行う。未確認事項が主張を変える場合だけ user に 1 点確認し、項目数や点数を満たすための書き直しはしない。

### Step 2.5: writing check (NG 語チェック)

writing check: `references/writing-check-protocol.md` 参照 (対象: issue / PR comment draft、channel 共通強度)。target に issue/PR URL を含む場合は記載する前に `gh issue view` / `gh pr view` で番号実在と title 一致を検証する (`references/on-demand-rules/ai-output.md`)。

### Step 3: Display as post candidate

title が必要な target は title と本文を出し、comment / Slack は本文だけを出す。self-check の点数、適用規則、文字数、書き直し工程は表示しない。post command は user が求めた場合だけ添える。user が "post this" と言えば AI が実行する。

### Step 3.5: PR-scoped memory update (`gh-pr-review` のみ)

target が `gh-pr-review` かつ `$MEM/pr_<repo>_<number>_review.md` (`MEM=$(bash ~/.claude/scripts/memory-save-helper.sh resolve-dir)`。命名規約・template: `commands/review.md` `## PR-scoped Memory (read → append)`) が存在する場合、**実際に post した後**に該当観点の行を更新する (draft 表示時点では更新しない、post 未確定の状態を先取りしない)。更新内容: status 列 (例: `対応中` → `check済`)、comment link 列に実際に post した URL、更新日。対応する観点が memory 側に無ければ新規行を追加する。

## Options

| Arg | Behavior |
|-----|----------|
| `--dry-run` | draft + self-check only, don't show post command |

## Fallback

意味を保ったまま修正できない問題が残存する場合は、不足している事実を 1 点だけ確認する。文体上の warning だけで投稿可否の選択を迫らない。

## Guards

- **no auto-execution of post command**
- long docs (Design Doc / PRD / Notion-scale) → use `/spec-design` (prevent misuse)
- API limits enforced by caller (GitHub: 65k chars, Slack: 4k, Jira description: 32k)

## Related

- rules: `~/.claude/references/on-demand-rules/ai-output.md` "issue/ticket/comment post rules"
- long form: `~/.claude/guidelines/writing/long-form-doc.md`
- built-in: `/git-push --pr`
