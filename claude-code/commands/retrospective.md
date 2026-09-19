---
allowed-tools: Read, Write, Glob, Grep, Bash, mcp__serena__*
description: retrospective - 過去 session を分析し、skill / config の改善案を自動で提示する
---

# /retrospective - Session Review & Self-improvement

Analyze past session history and work records; auto-generate improvement proposals.

## Headless 実行 (cron `com.claude.retrospective`)

`claude -p` では AskUserQuestion が使えないため、headless 時は Phase ごとに次の挙動になる。headless での書込先は staging file と pending-improvements の 2 つだけとする。

| Phase | headless 時の挙動 |
|---|---|
| 0 | 質問せず `private` に固定 |
| 3 | developer-agent delegation と実装 (skill 新設・CLAUDE.md 追記・hook 変更) は行わず、提案文面の生成に留める |
| 4 | 実行せず、提案を `<repo-root>/memory/sleep-proposals-<date>-retrospective.md` へ sleep cron の 5 field schema (`### P<n>:` + Type / Target / Evidence / Change / Risk) で staging して終える (翌朝 `/sleep-review` が triage、canonical: `references/sleep-cron-spec.md`) |
| 5 | staging した旨の 1 行追記に留める |

## Execution Flow

### Phase 0: Save destination (before investigation)

AskUserQuestion で保存先を選ばせる ("retrospective 保存先を決めてください")。1. `private` (default): `~/.claude/references-private/retrospective/YYYY-MM-DD_<slug>.md` 2. `public`: `docs/reports/retrospective/YYYY-MM-DD_<slug>.md`

**Default = private**。`public` を明示選択したときのみ (private data leak 防止): doc 先頭に `rules/public-repo-private-data-block.md` の reference を echo し、保存前に分析対象 session に social-hit term が無いか確認する。

### Phase 1: Data Collection

**history.jsonl** — timestamp filter (last 7 days), then grep churn signals:

```bash
jq 'select(.timestamp > ((now - 604800) * 1000))' ~/.claude/history.jsonl \
  | grep -E '再度|もう一度|やり直|違う|stop|cancel|wrong'
```

> command 実行回数は `/xxx` prefix 一致で数える (会話本文の言及も grep に含まれ、2026-07-20 pending E では約 2 倍に膨れた)。retry は「同 session かつ 10 分以内の再実行」で数える。

**Serena memory** — `mcp__serena__list_memories` (name + description only); full body loaded on-demand in Phase 2.

**Additional sources** (skip with 1-line note if missing):

| Source             | Command                                                                                                        |
| ------------------ | -------------------------------------------------------------------------------------------------------------- |
| 貢献度 (四半期、手動) | GitHub の merged PR と review から PR/週・実効行の中央値・受コメント/PR・review/週・merge 待ちを計測し前回との差分を Success / Problem Patterns に転記する。script の置き場と手順は project の memory。行動目標 (review 週 N 件、1 PR の行数上限) の達成度を Phase 4 で判定する。cron には登録しない |
| usage stats        | `ccusage daily --since 7` (未 install なら `npm install -g ccusage` を user へ案内、AI は auto install しない)     |
| JP quality blocks  | `tail -n 50 ~/.claude/logs/jp-quality-block.log`  |
| session split logs | `tail -n 20 ~/.claude/logs/session-split-warn.log`                                                             |
| guard block logs | `for f in ~/.claude/logs/*-block.log; do echo "== $f"; tail -n 20 "$f"; done` (全 guard の block 履歴。特定 guard に偏るなら誤爆を疑い、誘導文言と受理形式が一致しているか実物で確かめる) |
| /flow baseline TSV | `~/.claude/scripts/flow-baseline.sh --since 7d` (generates `~/.claude/logs/flow-baseline-$(date +%Y%m%d).tsv`) |
| sleep harvest digest | `<repo-root>/claude-code/scripts/sleep-harvest.sh --days 7` (churn / logs / skill-eval を一括集計する。上記個別 command の代替に使ってよい) |
| sleep proposals | `Glob <repo-root>/memory/sleep-proposals-*.md` — staged は `/sleep-review` へ誘導し、`.rejected.md` は reject 理由を signal として読む |
| hook block 集計 | 対象 session transcript (`~/.claude/projects/<slug>/*.jsonl`) の tool_result text を `禁止\|block\|hook error` で grep → 種別ごとに件数化し、上位は tool_use_id で元 command を取得して実物分類する。user 発話に出ない AI 側の自傷摩擦 (自作 gate が委譲や command を拒否する損失) はこの経路でしか見えない (2026-08-23 に explore contract block 週 39 件を初可視化)。block 件数の多さ = gate の誤りではないので、分類してから修正を判断する |

**Cursor sources** (skip with 1-line note if missing):

| Source | Command |
|--------|---------|
| settings drift | `cd <repo-root>/cursor && ./sync.sh diff` |
| global rules | `Glob <repo-root>/cursor/rules/*.mdc` → Read |
| project memories | `Glob .cursor/memories/*.md` → Read (ai-tools: `<repo-root>/.cursor/memories/`) |
| project rules | `Glob .cursor/rules/*.mdc` (if present) |
| maintenance checklist | Read `<repo-root>/cursor/MAINTENANCE.md` — list items still marked `- [ ]` |


### Phase 2: Signal Extraction (≤500 token output, parent inline only)

| Analysis Target       | Extract                                         |
| --------------------- | ----------------------------------------------- |
| failure patterns      | high-error tasks, retry spikes, dropped tasks   |
| inefficiency patterns | churn keywords hit, each-session config explain |
| success patterns      | efficient workflows, what-worked approaches     |
| Cursor friction       | settings drift (sync diff), rules/memory contradiction, Cursor-only retries |
| Cursor staleness      | old `更新:` dates, dead paths in `.cursor/memories/` |

For each Serena memory name matching a detected signal: `mcp__serena__read_memory(name)` on-demand only.

### Phase 3: Generate Improvements (parallel delegation)

Group signals by domain. ≥2 signals in a domain → `developer-agent` parallel delegation (<2 → skip).

| Domain             | Content                          |
| ------------------ | -------------------------------- |
| new skill          | common patterns → skill-ify      |
| existing skill     | related Qs common → add feature  |
| CLAUDE.md addition | recurring confirms → define once |
| hook automation    | manual repetition → auto-run     |
| cursor config      | settings/rules/memories drift → edit `cursor/` (see `cursor/MAINTENANCE.md`) |
| cursor rule        | recurring Cursor agent behavior → update `ai-tools-agent.mdc` or `.cursor/rules/` |

Delegation rule: 1 domain = 1 agent call (never bundle multiple domains into 1 prompt)。追加系の提案 (new skill / hook / command) は lifecycle gate (摩擦 evidence + cap、`references/on-demand-rules/toolchain-lifecycle.md`) を通過する前提で記載する。

### Phase 3.5: Accumulate Writing Failure Examples (Compounding Engineering)

If writing failures detected (user feedback "hard to read" / "AI-smelling" / "so what?"), accumulate examples to memory for next session's hook reference.

Save to: `<repo-root>/memory/writing_failure_{topic}.md` (frontmatter: `name` / `description` / `metadata.type: writing-failure` / `metadata.date`). Sections: What Happened / Relevant Location / Root Cause / Prevention (cite PRINCIPLES.md axis).

### Phase 4: Adopt & Apply

AskUserQuestion → select proposals → implement (new skill / edit existing / add to CLAUDE.md / save memory)

### Phase 5: pending-improvements memory auto-update

Read then re-write `<repo-root>/memory/pending-improvements.md` via `Write` (Serena `write_memory` forbidden — 2026-06-10 decision、read-modify-write に統一):

- Append today's session results to completed list
- Remove consumed items from pending; record unadopted proposals under "remaining"
- Retain on-hold items (tech barrier / trigger unmet)
- Add today's learnings to knowledge section
- Cursor improvements: tag `[cursor]` in pending; link `cursor/MAINTENANCE.md` item when applicable

## Output Format

```markdown
# Retrospective Report

## Analysis Period: YYYY-MM-DD ~ YYYY-MM-DD (recent N)

## Problem Patterns (frequency: high/mid/low)

## Success Patterns

## Improvement Proposals (new skill / existing / auto-run) each: name, why, priority

## Next Steps
```

## Output Prose

Notion/md 向け prose は canonical `guidelines/writing/long-form-doc.md` に従う (conclusion-first / 数値化 / 推奨 + 理由 / next action)。出力前に `guidelines/writing/PRINCIPLES.md`「文書全体の読みやすさ」と `references/writing-check-protocol.md` を適用する (対象: retrospective report)。

## Failure Handling

| Situation                         | Behavior                                                     |
| --------------------------------- | ------------------------------------------------------------ |
| `~/.claude/history.jsonl` missing | skip, continue with Serena memory alone, warn                |
| `ccusage` not installed           | skip, append "ccusage unavailable" to report                 |
| log path missing                  | skip, append "log path missing: {path}" to report            |
| Serena memory connect fail        | skip, continue with history.jsonl alone, note precision loss |
| recent sessions < 10              | insufficient data, report "accumulating" → done              |
| all data fetch fail               | cannot generate proposals, guide user to manual review       |

## Notes

- History may contain sensitive data. Never send externally
- Always get user approval before applying improvements
- Weekly execution recommended
