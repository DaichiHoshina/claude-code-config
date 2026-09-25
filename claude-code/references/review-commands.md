# Review Command Guide

| Command | Purpose |
|---------|---------|
| `/review` | Daily review (comprehensive-review skill, 11 perspectives + confidence-80 filter) |
| `/review --codex` | Second opinion (comprehensive + codex plugin parallel, shared findings → Critical) |
| `/review --adversarial` | codex adversarial-review delegation (design decisions / tradeoffs / failure modes) |
| `/review --panel` | 3-lens parallel fan-out (style/security/test-coverage)。旧 `--deep` は 2026-07-23 disable 済で代替は `--panel` + `--codex` |
| `/review --multi <PR>` | 4 methods parallel + auto PR comment post (pre-release, max token cost) |
| `/code-review ultra` | Cloud parallel multi-agent (**user explicit trigger only**, separate billing。built-in slash command。`/ultrareview` は deprecated alias) |

Details: [`commands/review.md`](../commands/review.md)

## Natural language activation

Can launch from natural language: "レビュー", "設計レビュー", "深掘りレビュー" etc. (see `natural-language-triggers.md`). On `/review` standalone launch, **mode is auto-detected** (diff size / PR presence / change type) → heavy modes require user confirmation. Details: [`commands/review.md`](../commands/review.md) Step 0.

## Selection guide

| Situation | Recommended |
|-----------|------------|
| Small–medium (1–3 files) daily | `/review` |
| Strict error handling / type design | `/review --panel --codex` |
| Design decisions / architecture validity | `/review --adversarial` |
| Pre-merge / pre-release / security patch | `/review --multi <PR>` |
| Large branch overall | `/code-review ultra` (user instruction, built-in slash command) |
| PR comment post only | `/code-review:code-review <PR>` direct call |

## Auto review (on PR creation, opt-in)

`/git-push --pr --auto-review` launches `code-review:code-review` + `coderabbit:code-review` in parallel. Details and failure behavior: [`commands/git-push.md`](../commands/git-push.md)

## Full guideline load (`/review --full`)

diff が設計方針に関わるとき (依存方向 / 集約境界 / read-write 分離) に guideline を全部読んでから review する。

1. `/load-guidelines full` を実行する (common 3 本 + 検出言語 + infra)
2. design 系 2 本を明示 Read する (`load-guidelines` は sub-topic 扱いで自動では読まない):
   `guidelines/design/clean-architecture.md` / `guidelines/design/domain-driven-design.md`
3. `guidelines/design/cqrs.md` は diff が query / command の分離境界や read model の同期 (replica / event / cache) に関わるときだけ追加する。採用判断と移行手順が大半で diff review の根拠にならず、「Command は id しか返さない」原則は Output を併返する実装と衝突して誤検知源になる (2026-08-28)
4. backend 系 (`guidelines/backend/`) は diff に該当 keyword (cache / transaction / tenant 等) があるときだけ 1〜2 本追加する。bulk load は `load-guidelines` と同じく禁止する
5. 読んだ file 名を 1 行で報告する (本文の要約は出さない)
6. reviewer-agent への delegation prompt に「読んだ guideline の観点を finding の根拠に使う」を 1 行添える

repo rule (`resolve-repo-rules.sh`) の解決と Read は `/review` 本体が常時行うので、ここでは重複させない。

## 領域 memory の引き当て

diff の対象領域 (ディレクトリ名や table 名から取る。例: `oripa` / `payment` / `shipment`) を語にして memory index を grep し、hit した file を Read する。既知の trade-off と実装世代の地図がここにあり、読まずに review すると、user が判断済みの未修正箇所を指摘として再提出する。

```bash
grep -niE '<領域語>' "$(bash ~/.claude/scripts/memory-save-helper.sh resolve-dir)/MEMORY.md"
```

- org 配下の repo では index が repo ごとの sub dir にある (例: `<ghq-root>/github.com/<org>/memory/<repo>/MEMORY.md`)。resolve-dir が返す dir に `MEMORY.md` が無ければ 1 つ上の階層の index を確認する
- hit 行の description で採否を決めず、本文を開く。description は要約なので、判断済みかどうかまでは書かれていない
- 読む上限は 3 file。4 件以上 hit したら `**地図**` や `**入口**` の印が付いた行を優先する
- hit した file の絶対 path を reviewer-agent への delegation prompt に記載する (auto-load は subagent に届かない)

## Related

- [`review-modes-advanced.md`](review-modes-advanced.md) — Deep / Multi mode execution details and aggregation policy
- [`review-patterns-universal.md`](review-patterns-universal.md) — Common review finding patterns for design decisions and SQL dialects
