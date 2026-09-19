---
allowed-tools: Read, Glob, Grep, Bash, Task, Skill, Agent, AskUserQuestion, mcp__serena__*
description: project に必要な guideline (言語 full + design 系 DDD / CA、条件付きで CQRS) を全部読んでから /review を実行する
argument-hint: "[scope] [/review の option]"
---

# /review-full - guideline 全載せ review

> `/review` の前段で guideline を全部読み込む薄い wrapper。review 本体の logic は持たず `/review` に委譲する。
> 「観点全部で」「ガイドライン全載せでレビュー」「DDD / CA 観点も含めてレビュー」で発火する。

## Flow

### Step 1: guideline 全載せ

1. `/load-guidelines full` を実行する (common 3 本 + 検出言語 + infra)
2. design 系 2 本も明示 Read する (`load-guidelines` は sub-topic 扱いで自動では読まない):
   - `~/.claude/guidelines/design/clean-architecture.md`
   - `~/.claude/guidelines/design/domain-driven-design.md`
   - `~/.claude/guidelines/design/cqrs.md` は diff が query / command の分離境界や read model の同期 (replica / event / cache) に関わるときだけ追加する。採用判断と移行手順が大半で diff review の根拠にならず、「Command は id しか返さない」原則は Output を併返する実装と衝突して誤検知源になる (2026-08-28)
3. repo rule (`resolve-repo-rules.sh` の `--review-docs` と `<変更 file>...` の両方) の解決と Read は `/review` 本体が常時行う (`commands/review.md` 「Review Policy & Scope」)。ここでは重複して実行しない
4. 領域 memory を引き当てる (下記「領域 memory の引き当て」)。hit した file を Read し、reviewer-agent への delegation prompt に絶対 path を記載する (auto-load は subagent に届かない)
5. 読んだ file 名を 1 行で報告する (本文の要約は出さない)

### 領域 memory の引き当て

diff の対象領域 (ディレクトリ名や table 名から取る。例: `oripa` / `payment` / `shipment`) を語にして memory index を grep し、hit した file を Read する。既知の trade-off と実装世代の地図がここにあり、読まずに review すると、user が判断済みの未修正箇所を指摘として再提出する。

```bash
grep -niE '<領域語>' "$(bash ~/.claude/scripts/memory-save-helper.sh resolve-dir)/MEMORY.md"
```

- org 配下の repo では index が repo ごとの sub dir にある (例: `<ghq-root>/github.com/<org>/memory/<repo>/MEMORY.md`)。resolve-dir が返す dir に `MEMORY.md` が無ければ 1 つ上の階層の index を確認する
- hit 行の description で採否を決めず、本文を開く。description は要約なので、判断済みかどうかまでは書かれていない
- 読む上限は 3 file。4 件以上 hit したら `**地図**` や `**入口**` の印が付いた行を優先する

### Step 2: `/review` へ委譲

引数をそのまま渡して `/review $ARGUMENTS` を実行する。`--panel` / `--codex` / `--adversarial` 等の option も透過する。reviewer-agent への delegation prompt には「Step 1 で読んだ guideline の観点 (依存方向 / 集約境界 / read-write 分離) を finding の根拠に使う」を 1 行添える。repo rule の path 一覧は `/review` 側の delegation prompt (`repo_rules=`) が渡す。

## Guard

- `/review` の 2 段 self-review (Stage A / B) と PR-scoped memory は `/review` 側の仕様に従う。この command で上書きしない
- guideline の追加読み込みは Step 1 の design 2 本 + 条件付き `cqrs.md` まで。backend 系 (`guidelines/backend/`) は diff に該当 keyword (cache / transaction / tenant 等) があるときだけ 1〜2 本追加する (bulk load 禁止は `load-guidelines` と同じ)
- repo rule も glob が当たった分だけを読む。rule dir 全件の bulk load は禁止する (rule が 50 本を超える repo があり、全載せは guideline 側の bulk load 禁止と矛盾する)

## Related

- `commands/review.md` — review 本体 (行数上限に近いため option 追加でなく wrapper にした)
- `skills/load-guidelines/SKILL.md` — `full` mode と sub-topic の扱い
- `skills/comprehensive-review/SKILL.md` — `requires-guidelines` (common / clean-architecture / ddd)
