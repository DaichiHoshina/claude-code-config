---
allowed-tools: Bash, Read, Edit
name: local-docs
description: local-docs 配下 HTML doc 作成・更新 skill。「postmortem」「報告資料」「検証レポート」「RCA」「調査ログ」で起動。
---

# Completion response hard gate

既存 doc の update では、内部で `textlint` / build / layout を検証しても、それらの成功結果や実行工程を最終応答へ出さない。本文を変更した場合は、文書全体に及ぶ変更の要点を 1 文だけ返す。変更しなかった場合は「読み違いにつながる問題は見つからなかった」とだけ返す。個々の変更箇所、変更理由、触らなかった箇所、skeleton / style / script、warning、全体評価、次の改善案は返さない。失敗や未解決の問題だけは具体的に返す。この gate は下記の authoring / validation 手順より優先する。

# local-docs

`local-docs/` 配下に HTML doc を作成 / 更新する専用 skill (repo の実体 path は機体ごとに異なる。`commands/ld.md` の探索候補 list を正本とし、ghq 配下前提で固定しない)。type enum / 集約呼称 / placement は local-docs の `CLAUDE.md` と `STRUCTURE.md` から section 単位で毎回 Read する (別 session の記憶を使わない、詳細は Prerequisites)。

## 禁止 rule (違反 = 即 abort)
以下は過去 incident 起因の hard rule。1 つでも踏むと共有 CSS / index build / decorate が破綻する。

| Rule | 理由 |
|---|---|
| skill 起動なしで `local-docs/` 配下に HTML を作成する | 過去 incident: inline `<style>` で共有 CSS 破壊 |
| `Write` で HTML 直書き | skeleton / `<style>` / `<script>` を上書きして壊す |
| `.md` で新規 doc 作成 | 全 doc は `_templates/{type}.html` 起点。起こすのは `_index/new-doc.mjs` に任せる |
| `<style id="local-docs-style">` / `<script id="local-docs-script">` の変更 | 共有 infrastructure、decorate / TOC / hero / num badge が破綻 |
| skill file (この file) 自体に社名 / product 名を記載する | public repo 制約。proprietary 情報は local-docs 側 `CLAUDE.md` に置く |

## infrastructure の正本 (template / 共有 CSS / 生成 script)

置き場は git 管理外のため、正本は skill 配下 `assets/` が持つ (`templates/*.html` / `style.css` / `index/*.mjs`)。置き場側を直接編集しない (次の反映で上書きされる)。

| 操作 | command |
|---|---|
| 正本を置き場へ配る (既存 doc の共有 CSS も更新) | `~/.claude/scripts/local-docs-sync-assets.sh` |
| 差分の有無だけ見る | `~/.claude/scripts/local-docs-sync-assets.sh --check` |

見た目や生成の挙動を変えるときは `assets/` 側 (`style.css` / `templates/{type}.html` / `index/*.mjs`) を修正して、上の反映 command を回す。

## auto activation trigger
skill は明示 invoke なしでも auto activate する (以下 3 分類のいずれかで起動)。

| 種別 | trigger |
|---|---|
| user 発話 | 「local-docs」「ナレッジ」「runbook」「RCA」「postmortem」「報告資料」「検証レポート」「spec」「調査ログ」「監視結果」「post-release」「dashboard 確認」「5xx 分析」「インシデント記録」「試験結果」「session をまたぐ作業」「試行錯誤メモ」 |
| 出力先 path | `~/local-docs/{guides,notes,archive}/` 配下 |
| 拡張子 | 上記 path 下の `.html` |

## Subcommand
- `/local-docs new {type} {topic}`: 新規作成 (**既定は quick**。`/ld` と同じ 3 手で `_index/new-doc.mjs` から起こす)
- `/local-docs new {type} {topic} --full`: 規範 Read + outline + jp-fix / textlint を成功させる従来 flow (共有前提の decision / postmortem 向け)
- `/local-docs update {path}`: 既存 doc の追記 / 書き直し
- `/local-docs update {path} --reformat`: skeleton を最新 template に整合
- (省略時): 文脈から `new` / `update` を推定する

## Prerequisites (`--full` と `update` のみ。script 1 call でまとめて取る)

規範は `~/.claude/scripts/local-docs-context.sh` が 1 回の実行で出す。**個別 Read で再度読まない** (同じ内容を 6 回前後の Read に割っていたのを畳んだ)。

```bash
~/.claude/scripts/local-docs-context.sh                  # 規範一式 (new / update / reformat で共通)
~/.claude/scripts/local-docs-context.sh --type decision  # type 固有の規範を足す
~/.claude/scripts/local-docs-context.sh --root           # 置き場の絶対 path だけ
```

出力は 2 つを束ねたものになる。置き場側の規約 (`~/local-docs` は `README.html`、`CLAUDE.md` を持つ置き場ならその該当 section) と、writing 規範の 文書全体の読みやすさ / 構造ゲート適用 / 品質検証タイミング。`--type` が decision / postmortem / report / plan のときは type 別の本文品質が、decision ではさらに専用 hard checklist が加わる。出し分けは `--type` だけで、new / update / reformat の区別は無い (2026-09-21 に廃止。現在の置き場は規約が README 1 本のため、出力が変わらなかった)。script が出さない section が要るときだけ個別 Read に降りる。

## Flow: `new {type} {topic}` (既定 = quick、user 決定 2026-09-03)

`--full` が無ければ `commands/ld.md` の 3 手で終える: (1) type / 置き場を command 内の表で即決 (Prerequisites の section Read はしない) → (2) `<h2>` から始まる本文 fragment を scratchpad に記載する → (3) `node _index/new-doc.mjs --type ... --out ... --title ... --lead ... --body ...` で起こす (metadata 刻印と build を script が行う)。完了報告は doc 名 + 1 行要約のみ。以下の Step 1〜7 は `--full` 指定時だけ実行する。

## Flow: `new {type} {topic} --full`

### Step 1. Type / Placement 決定
topic から type を判定し、variant は `CLAUDE.md` mapping で canonical 化する (canonical type enum 内か確認)。`STRUCTURE.md` placement flow に従い出力 dir を決定する (無ければ `mkdir`)。

### Step 1.5. Outline pass (本文前・必須)

本文の書き方知見はこの skill に格納しない (6 点は `PRINCIPLES.md` が正本で、ここでは再掲しない)。

- **参照先**: Prerequisites の script 出力に含まれる `PRINCIPLES.md`「文書全体の読みやすさ」と `long-form-doc.md`「構造ゲート適用」を Read する (script が出すので個別 Read は要らない)。種別固有の知見が要るときだけ `skills/writing-knowledge` 判定表で 1 file を追加 Read する
- **読む内容**: 読む目的 / 結論の所有 section / 用語 / 不要 h2 の削除
- **実行順**: 上記の規範で outline を内部で決めてから本文へ進む (user への工程報告は不要)

`type: decision` は script 出力の「decision 専用 hard checklist」に必ず従う (1 つでも満たさなければ本文を作成しない / 書き換える)。
ローカルリンクされた関連文書がある場合は、リンク先の metadata・タイトル・冒頭・見出し・正本表記を読み、`long-form-doc.md`「文書セット設計」の所有マップ (論点の重複所有 / 正本表記の矛盾 / 文書種別を越えた内容) を本文前に確認する。

### Step 2-6. 本文を書いて 1 call で起こす (Write / cp + Edit 禁止)

quick と同じ `_index/new-doc.mjs` を使う。`--full` との違いは前段 (規範と outline) と後段 (Step 7) にあり、file の起こし方は同じにする。**`cp` してから placeholder を Edit で 1 個ずつ埋める旧手順は使わない** (decision template は placeholder が 30 個あり、そのぶん往復が伸びる)。

```bash
LD=$(~/.claude/scripts/local-docs-context.sh --root)
node "$LD"/_index/new-doc.mjs --type <type> --out <name> \
  --title "<title>" --lead "<1 行リード>" \
  [--event-date ... | --data-window ... | --observed-at ...] --md - <<'EOF'
## <見出し>   # 番号は書かない (badge と目次の番号は script が付ける)
EOF
```

Markdown 方言の正本は `_index/new-doc.mjs` 冒頭の comment、置き場と file 名の決め方は `commands/ld.md` の表にある。文体・本文品質は Step 1.5 で読んだ規範 (`long-form-doc.md` + `PRINCIPLES.md`「文章生成の不変条件」) に従い、この skill では規定しない。script は次を自動で行うので、別 step に分けない。

- metadata 刻印 (`type` / `status` / `created` / `updated` + type 別の日付)。`--event-date` 等が欠けていれば error で止まる
- 出力先の解決 (`--out` に dir が無ければ `guides/`)
- 構造 self-check (metadata 先頭 / `<style id="local-docs-style">` / `<script id="local-docs-script">` の保持) と placeholder 残数の報告
- `build-index.mjs` 実行 (置き場の `index.html` を再生成する)

self-check NG か placeholder 残が 1 以上なら、その場で本文を修正して `--force` で再生成する。

### Step 7. Polish & Verify (skip 禁止)
| 手順 | 内容 |
|---|---|
| 7-1 | 完成稿で「見出し — 役割 — 所有する主張 — 本流/付録」の skeleton 表を内部で作る。今回の outline (new は Step 1.5、update / reformat は本文編集前の outline pass) と突合し、`PRINCIPLES.md` の「文書全体の読みやすさ」を再適用する。decision では `long-form-doc.md` の decision 専用 hard checklist に 1 つでも反したら、局所 jp / 類義語置換の前に構成を修正する（「読み違い 1 文だけ」で打ち切らない）。意味が成立する単語の類義語置換は行わない。ローカルリンクされた関連文書がある場合は 「文書セット設計」で最終確認する (重複所有 / 正本表記の矛盾 / 種別越境 / `status: approved` の未決表現)。横断確認は本文のみで、CSS / JavaScript は対象にしない |
| 7-2 | `jp-fix` skill を実行 (skill 本体を起動) |
| 7-3 | 意味・事実・必須形式を損なう Critical、または文脈上の読み違えの原因になる Warning があれば書き換える。件数だけでは発動しない。再点検のたびに新しい変更を作る必要はない |
| 7-4 | lint と build を 1 call で回す: `cd "$LD" && ./scripts/textlint-html.sh <file>; node _index/build-index.mjs` (2 つに分けない。`new` は生成時に build 済みなので、本文を修正していなければ省く) |
| 7-5 | user に browser で layout 確認を依頼 |

合格ライン: `guidelines/writing/long-form-doc.md` 「品質検証タイミング」

## Flow: `update {path}`

| 条件 | Mode |
|---|---|
| `--reformat` 明示 | reformat |
| legacy 構造検出 (manual toc / tldr / decorate 欠落 / 旧 inline style) | reformat (user 提案) |
| 上記なし | default (content-update) |

default: Prerequisites の script と既存 doc の Read を同じ message で並べて取る → Step 1.5 相当の outline pass (今回の読む目的・結論所有・用語を決める) → body 追記 / 書き直し (skeleton / style / script 触らない。`<!-- updated: -->` を今日の日付にする) → Step 7 通す。
reformat: skeleton を最新 template に整合 → Step 1.5 相当で不要 h2 を再選定 → legacy 削除 → body 保持 → metadata 修正 → Step 7 通す。

Step 7-1 の outline 比較は、new では Step 1.5、update / reformat では当該編集の outline pass を使う。

## Related

- local-docs `CLAUDE.md` / `STRUCTURE.md`: canonical type / aggregation mapping / Title Rules / Metadata / placement flow / html 形式 (primary source)
- `guidelines/writing/long-form-doc.md`: 本文書き出し前の必須 guideline + 文体規範 + 「type 別の本文品質」(postmortem 時系列 / report 出典 / plan / decision)。この skill は保存方法と形式 (type enum / placement / template / metadata / build) のみ扱う
