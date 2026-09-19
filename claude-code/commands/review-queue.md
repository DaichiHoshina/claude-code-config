---
allowed-tools: Read, Glob, Grep, Bash, Write, mcp__serena__*
description: 他者の open PR を待ちが長い順に並べ、1 件ずつ diff を読んで指摘の draft を file に書く (投稿は user)。毎朝の review 時間の入口。「レビューする PR ある?」「review queue」「今日のレビュー」で起動
argument-hint: "[--pr <n>] [--limit <n>] [--include-mine-requested-only]"
---

# /review-queue - 他者 PR の review を始める

> **Goal**: 自分が review すべき PR を待ちが長い順に出し、採用した 1 件について diff と repo 規範を突き合わせた指摘 draft を file に記載する。投稿は user が行う。

## When to use (棲み分け)

| Command / skill | Use |
|---|---|
| `/review-queue` | **他者の PR** を review する入口 (この command)。候補の列挙 → 1 件の指摘 draft |
| `/review` | **自分の diff** を review する |
| `review-member` skill | 自分の PR に、team メンバーの review 傾向を lens として当てる (pre-PR) |
| `review-reply-draft` skill | 自分の PR に付いた他者 comment への返信 draft |
| `/post-comment` | draft を PR に投稿する (user が発火) |

計測 (2026-09-06、直近 90 日) で、貢献度上位との差が最も大きかったのは他者 PR への review 量 (上位は週 7〜21 件、中央値 4 件) だった。review を「探す → 読む → 書く」の 3 手にして毎朝 30 分で始められるようにする。

## Step 1: 候補の列挙

1. 自分に依頼のある PR は `gh pr list --state open --search "review-requested:@me sort:created-asc" --json number,author,createdAt,isDraft,title,body,files,reviews` で取る。依頼のない PR は `gh pr list --state open --limit 100 --search "sort:created-asc" --json ...` で **作成日の古い順** に取る (既定の新しい順で `--limit` 件に限定すると、待ちが一番長い PR が表から外れる。2026-09-06 に実踏)。どちらも JSON を file (`/tmp/review-queue-<repo>.json` 等) へ保存してから `jq` にかける (`--jq` に複数行の式を渡すと gh が引数として解釈して失敗する)
2. file の JSON から次を除く: 自分が author、draft、自分の review が既に付いている、bot が author。次の表で待ちが長い順に並べて出す (既定 5 件、`--limit` で変更)。実効行は `files` の追加 + 削除から test と生成物 (`_test.go` / `testdata` / `fixtures` / `mock` / `swagger` / `*.gen.*` / lock / `api-docs`) を除いた値
3. PR 本文の `## レビュー観点` と `## 影響範囲` から、確認してほしい点と挙動の変化を表に転記する (`guidelines/writing/pr-description.md` 「節への配置」)。repo template が無く該当節が見当たらない PR は「(本文にレビュー観点なし)」と書く

```
| # | author | 待ち (日) | 実効行 | 既存挙動 | 確認点 | 自分に依頼 |
```

- `--pr <n>` があれば列挙を省いてその PR に進む。無ければ、自分に依頼のある PR の中で待ちが最長のものを採用し、依頼が無ければ表の 1 件目を採用する。採用した番号を 1 行宣言する
- 表の「確認点」が全件「(本文にレビュー観点なし)」なら、その事実を 1 行添える (repo template の活用度の観測になる)

## Step 2: 読む

1. `gh pr diff <n>` と `gh pr view <n> --json body,files` を取り、確認点の行があればその範囲から読む。無ければ変更 file を層 (migration / data / usecase / adapter / 画面) で分け、内側から読む
2. `~/.claude/scripts/resolve-repo-rules.sh <変更 file>...` で当たる repo rule を引き (exit 3 なら skip)、命名 / 型 / 層 / error / test の制約を lens にする。`review-member` skill の lens (33 観点) は、その PR の author が過去に受けた指摘の傾向が memory にあるときだけ追加する
3. 実物照合 (指摘前に必須): 指摘の根拠になる既存 code は `gh pr checkout` せず `git show origin/<base>:<path>` か Serena `find_symbol` で読み、行番号を確かめる。「たぶんこうなっている」で指摘を記載しない (`/review --fable` の実在確認と同じ)
4. 既存挙動が「変わらない」とある PR は、その主張が diff と一致するか (新規 symbol の production 参照が 0 件か、I/F 変更だけか) を先に確かめ、一致していれば確認点の範囲外は読まない

## Step 3: 指摘 draft を file に記載する

`~/.claude/plans/review-drafts/<repo>-<PR 番号>.md` に次の形で書く。投稿はしない。

```markdown
# review draft: <repo> #<n> <title>

確認した範囲: <確認点の行 or 読んだ層>
既存挙動の主張との一致: 一致 / 不一致 (<何が>)

## 変更が必要 (must)
- `<path>:<line>` <指摘 1 文> — 根拠: <rule file 名 or 既存 code の path:line>

## 提案 (nit)
- `<path>:<line>` <提案 1 文> — 理由: <1 文>

## approve できるか
- できる / must を修正すればできる / 判断できない (<足りない情報>)
```

- 指摘は「変更が必要」と「提案」に分け、根拠の無い指摘は書かない (`references/on-demand-rules/review-noise-discard.md`)
- 文体は `guidelines/writing/pr-description.md` 「レビュー応答」 と同じ (敬体、指摘 1 文 + 根拠 1 文)。曖昧な汎用動詞と比喩は NG 辞書に従う
- draft の path を chat に出し、次の一手を 1 行添える: `/post-comment gh-pr-comment <n>` で投稿、または次の PR へ `/review-queue`

## Guard

- PR への投稿、approve、request changes、label や assignee の変更をしない (投稿は user が `/post-comment` で行う。CLAUDE.md 「Git / GitHub 自発操作の禁止」)
- `gh pr checkout` で作業 worktree を切り替えない (読むだけなら `git show` で足りる)
- draft は 1 回の起動で 1 PR。複数を並べて書かない (1 件を実物照合まで通す方が、3 件の浅い指摘より author の往復を減らす)

## Related

- `commands/review.md` — 自分の diff の review
- `skills/review-member/SKILL.md` — team メンバーの lens
- `commands/post-comment.md` — 投稿
- `references/on-demand-rules/review-noise-discard.md` — 指摘の取捨
