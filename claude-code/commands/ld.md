---
allowed-tools: Bash
argument-hint: "<type> <topic> [--project N] [--dir path]"
description: local-docs の HTML doc をクイック作成する (規範 Read と Polish を省き、template コピーと build を script に任せる 3 手フロー)
model: sonnet
effort: low
---

## 目的

この command の turn は frontmatter の `model: sonnet` + `effort: low` で生成 model が Sonnet の低 effort に切り替わる (user 決定 2026-09-03。調査 / 判断は session の model のまま、本文生成だけ速い model へ下げる。次の prompt から元に戻る)。

`/local-docs` の full flow (section 単位の規範 Read → outline → Edit → jp-fix → textlint → build) は 1 doc に十数回の tool 往復がかかる。この command は **3 手 (判定 → 本文 → script) で終える** 軽量版で、**新規 doc 作成の既定 flow** (user 決定 2026-09-03。skill `local-docs` の `new` も本 flow に委ねる)。精度が必要な外向き doc (decision / postmortem の共有版) だけ `/local-docs new --full` を使う。

## 禁止 (skill `local-docs` と同じ hard rule)

- `Write` / `Edit` で HTML を直書きしない。作成は必ず `_index/new-doc.mjs` 経由 (template の style / script を script が保持する)。本文用の一時 file も作らず stdin で渡す
- `.md` で新規 doc を作らない
- CLAUDE.md / STRUCTURE.md / writing 規範を section Read しない (下の表で足りる。迷う項目だけ `grep -n` で 1 箇所探す)

## Step 1: type と置き場を即決 (Read なし)

| type | 使う場面 | 追加 metadata |
|---|---|---|
| `spec` | 仕様の現状記述 (this code does X) | なし |
| `decision` | 案の比較 + 採用理由 | なし |
| `report` | 観測 / 検証結果の報告 | `--data-window YYYY-MM-DD/YYYY-MM-DD` (単日は同日) |
| `investigation` | 原因究明 / 調査記録 (旧 rca) | `--event-date YYYY-MM-DD` (障害なら発生日、他は着手日) |
| `postmortem` | incident 振り返り (組織向け) | `--event-date` |
| `runbook` | 運用手順 | なし |
| `log` | 監視 / 試験の実行ログ | `--observed-at YYYY-MM-DD` |
| `plan` | 未実施の段取り | なし |
| `guide` | ツール / 運用ガイド | なし |

置き場は上から順に最初に当たった先: PJ に対応するもの → `projects/{issue番号}-{topic}/` / ツールの使い方 → `tool-guides/{tool}/` / 横断ドメイン仕様 → `domain-specs/{domain}/` / 設定変更の判断に使う観測 → `monitoring/{領域}/` / 状態把握の調査 → `operations/{topic}/` / 迷う → `inbox/`。PJ dir の解決は script の `--project` に任せる (事前の `ls` は不要)。`--dir` 指定があれば `--out` に dir ごと書く。

file 名は `kebab-case.html`、タイトルは目的を先頭にした短い名詞句で、dir 名にある PJ 名 / 番号を繰り返さない。

## Step 2 + 3: 本文を Markdown で書き、script で起こす (1 Bash call)

本文は Markdown を heredoc で stdin に渡す。h1 / lead / style / script は script が付けるので書かない。骨格は template と同じ番号付き `##` + 末尾 `## 関連` を基本にし、不要な見出しは落とす。箇条書き / 表 / グラフ優先 (地の文は結論 1 文 + 前置きまで)。

```bash
LD=$(ls -d <ghq-root>/github.com/*/local-docs | head -1)
node $LD/_index/new-doc.mjs --type <type> --project <issue番号> --out <name> \
  --title "<title>" --lead "<1 行リード>" \
  [--event-date ... | --data-window ... | --observed-at ...] [--slug <topic>] --md - <<'EOF'
## 1. 目的
- 結論は **こう**。状態は [[ok:完了]] / [[warn:要対応]]
| 項目 | 件数 |
|---|---|
| foo | 12 |
::: verify
- 確認項目
:::
## 関連
- [issue](https://...)
EOF
```

- `--project` は `projects/<番号>-*` を解決する。dir が無い新規 PJ は `--slug <topic>` を添える。PJ に対応しない doc は `--project` を省き `--out tool-guides/{tool}/<name>` のように dir ごと書く
- Markdown 方言: `##` / `###` / `####` (h2 / h3 / h4、入れ子を積極的に使う)、`-` と `1.` (2 space 字下げで入れ子)、`| |` 表 (数値セルは自動で右寄せ)、``` code、`> ` 引用、`::: verify|nonscope|timeline` ブロック、`**強調**` / `` `code` `` / `==核心==` / `[t](url)`、`[[ok|warn|skip|new|mod:text]]` pill。正本は script 冒頭の comment
- `.arch` / `.chart` のような Markdown に無い装飾が必要なときだけ `--body <file>` に HTML fragment を渡す
- script が metadata (`created` / `updated` = 現在時刻) を刻印し `build.mjs` まで実行する。`placeholder 残 N` が発生したら `{...}` が残存しているので修正する

## 完了報告

doc 名 + 1 行要約だけ返す。閲覧手順 / path / build の成功結果 / 検証工程は返さない (`rules/no-local-path-in-shared-docs.md`)。失敗と未解決だけ具体的に記載する。

## Related

- skill `local-docs` — full flow (規範 Read + jp-fix + textlint)。既存 doc の update は skill 側の `update {path}` を使う
- local-docs repo の `CLAUDE.md` 「Templates」 / 「コンポーネント活用マップ」 (上表の正本)
