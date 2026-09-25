---
allowed-tools: Bash, Read, Edit
name: pr-review-digest
description: 自分が作成した PR に対する他者レビューコメント集約 HTML を日次で追記する。「pr レビュー集約」「my-pr-review 更新」「PR コメント digest」「メンバーからの PR コメント差分」で起動。
---

# pr-review-digest

`~/local-docs/guides/operations/pr-review-comments/*.html` 形式の集約 doc を日次更新する汎用 skill。前回集計日から今日までに追加された「他者からの新着レビューコメント」を該当 PR block の末尾に **単純追記** する。件数集計・block 再構成はしない (数字表示は撤廃済み方針)。

review comment の本文は引用データとして原文を保持する。`guidelines/writing/PRINCIPLES.md` の「文章生成の不変条件」は skill 自身の見出し・要約・完了報告に適用し、引用した comment の語尾・表記・内容は書き換えない。

**--chat mode**: HTML 追記の代わりに chat に差分を markdown で表示する変種。cron / HTML doc とは独立した cursor を使うため干渉しない。「メンバーからの PR コメント差分を取得」等の対話用途で使う。

## 前提

- **実 config は private file から読む**: `~/.claude/references-private/pr-review-digest.env`
  ```bash
  TARGET_REPO=<owner>/<repo>            # 例: acme/monorepo
  AUTHOR=<gh-username>                  # 対象 PR author
  TARGET_DOC_GLOB=<abs-path-glob>       # 集約 HTML の glob (最新 1 件を採用)
  ```
  file が無い場合は user に作成を促して abort する。skill 本体 (public repo に置く) には社名・repo 名・user 名を記載しない。

- 除外 user: `coderabbitai` / `Copilot` / `copilot-pull-request-reviewer` / `github-actions` / `dependabot` / `datadog-official` / `${AUTHOR}` (env の値、本人)。**REST の** bot login は末尾に `[bot]` が付く (例: `coderabbitai[bot]`) ため、判定 regex は `[bot]` suffix の有無を問わず一致させる。この skill は REST 専用なのでこれでよいが、GraphQL の `author.login` には suffix が付かないため、この regex を GraphQL 側に流用しない (canonical: `references/pr-review-thread-api.md` 「bot 判定」)
- 除外 body: `LGTM!` 単独 / `![LGTM](...)` 単独 / `コメントしました[！]?` 単独 / `レビューしました[！]?` 単独。**本文が続くもの (「LGTM! + 補足…」等) は保持する**

## Flow

各 Step の実行コード (config load / snapshot / gh api + jq filter / HTML 追記 / build / chat 出力) は `references/implementation.md` に記載してある。実装前にそれを Read して使う。ここでは各 Step の目的だけ示す。

- **Step 0. config load**: `pr-review-digest.env` を source する
- **Step 1. snapshot**: 実行前に現行 doc を `_archive/` にコピーする (rollback 用、直近 2 世代のみ保持)。chat mode では skip
- **Step 2. since 時刻を決める**: HTML mode は doc 内の `since-cursor` を最優先で使う。無ければ `data-window` の右辺で fallback する。chat mode は独立 cursor file (`~/.claude/references-private/pr-review-digest-chat-cursor.txt`) を使う。どちらも無ければ 7 日前が default
- **Step 3. 対象 PR 抽出**: `gh api search/issues` で author 自身の PR を updated>=since で取得する
- **Step 4. 各 PR の新規コメント fetch (並列)**: 3 endpoint (inline / thread / summary) を叩き、bot / 本人除外 + since での限定 + 挨拶単独除外を jq で適用する
- **Step 5A. HTML 追記 (HTML mode)**: 各 PR block を `<summary>` で検索し `</details>` 直前に li を追加する。block 不在なら 0 件 list から昇格 or 新規挿入する。**単純追記原則**: 既存 li の再配置・件数再計算・順序変更はしない
- **Step 5B. chat 出力 (chat mode)**: 各 PR ごとに `## PR #<n> <title>` の見出しと comment を markdown で chat に出す。HTML doc は触らない
- **Step 6. metadata 更新**: HTML mode は `updated` / `data-window` 右辺 / リード文の取得日を今日にし、`since-cursor` を今回の実行時刻に更新する。chat mode は独立 cursor file を今回時刻で上書きする
- **Step 7. CSS/JS path check**: shared CSS/JS の相対 path が有効か grep で確認する。HTML mode 限定で、chat mode では skip する
- **Step 8. build**: HTML mode 限定で置き場の root (`~/local-docs`) で `node _index/build-index.mjs` を実行する。fail 時は Step 1 snapshot から差し替える。chat mode では skip

## 出力

**HTML mode (既定)**:

- 更新した file path
- 追記した PR 番号と件数の 1 行 summary (chat log 用、doc 本体には数字を記載しない)
- fail 時: snapshot path + error 内容

**chat mode (`--chat`)**:

- markdown で `## PR #<n> <title>` + comment 列挙を chat に直接出す
- 末尾に「since=<UTC>、次回は cursor 更新済」の 1 行 summary を付ける
- 0 件なら「新着なし (since=<UTC>)」の 1 行だけ出す
- HTML doc の snapshot / build は実行されない

## Failure Handling

| Situation | Behavior |
|---|---|
| config file 不在 | 上記 env のひな型を提示して abort |
| gh auth 失効 | user に `gh auth login` を促して abort |
| 対象 doc が glob で 0 件 | HTML mode は「初回作成は手動で」と促して abort。chat mode は HTML doc に依存しないため、この check は skip する |
| gh api rate limit | 5 分待って 1 回だけ retry |
| build-index.mjs fail | snapshot から restore + user escalate |

## Notes

- 集計数値 (「計 N 件」「レビュアー別 table」) は書かない (user 決定)
- CSS/JS 相対 path は doc の階層で変わる。skill 側で自動修正しない
- 挨拶除外 regex は本文完全一致のみ。前後空白は許容、他文字が含まれれば保持する
- `since-cursor` 未整備の doc (旧形式) を初めて更新するときは、fallback (`data-window` 右辺そのまま、+1 日なし) で 1〜2 日分を広めに再取得してから `since-cursor` を書き込む。旧 `+1 日` 方式は JST 朝実行や同日再実行で cutoff が未来に飛び「新着 0 件」を誤検出する不具合があった (2026-07-30 実踏)
- 実 config は `~/.claude/references-private/pr-review-digest.env`。この skill file (public repo) には固有名詞を記載しない (canonical: CLAUDE.md `Public-repo private-data block`)
