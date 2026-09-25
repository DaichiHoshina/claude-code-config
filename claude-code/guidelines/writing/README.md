# writing/ — チーム外向け文章ガイドライン

PR・Issueコメント・Slack・Notion・DesignDoc等、**他者が読む文章**を執筆するときの汎用原則を集約する。プロジェクト固有のテンプレ・宛先・添字規約は各プロジェクトの `CLAUDE.md` に記載する。

## 窓口と知識の論理ツリー

**契約**: 執筆規範の本文は `guidelines/writing/`（と必要時の `references/`）だけに置く。`skills/` / `commands/` は判定・工程・Read 指示の窓口であり、規範本文を含めない。

```
窓口
├── writing-knowledge … 着手前の種別 → file 判定（知識なし）
├── jp-fix command/skill … 推敲工程（規範本文なし、Read のみ）
├── jp-lint command … NG 辞書の機械検査を既存文書へ後追い適用（判定 SoT は lib/jp-quality/）
├── norm-apply command … 規範差分の checklist retrofit（辞書以外の規範を当てるとき）
├── local-docs … HTML 保存工程（本文規範は long-form へ）
└── sdd-design / prd / docs … 成果物工程（writing は Read 指示のみ）

知識 SoT  guidelines/writing/
├── 共通 … PRINCIPLES / NG-DICTIONARY / PRINCIPLES-word-replace / allowed-en-terms
├── 媒体 … slide-doc / long-form-doc / external-post / narrative-writing
└── 用途 … design-doc-protocol / pr-description / gh-issue / commit-message / code-comment / …

補足  references/writing-* … 書出前 protocol・詳細 pattern
```

- 着手前の種別判定の正: `skills/writing-knowledge` の判定表
- 推敲時の Dynamic Load: `commands/jp-fix.md`（判定表と種別対応を同期する。二重定義は許容）

## 責務マップ — 「どこに何を記載するか」

| 層 | 責務 | 文体 | 行数目安 |
|---|---|---|---|
| `rules/` | **強制ルール** (機械可読、grep高速) | 短文・表中心 | < 70 (短いほど良い) |
| `guidelines/writing/` | **原則・手順** (中粒度、汎用化済) | 表 + 箇条書き | 30-300 |
| `references/` | **補足事例・パターン詳細** (必要時のみload) | 段落 + 詳細例 | 100-600 |

迷ったときは rules で禁止リストを、guidelines/writing/ で原則と適用先を確認し、references/ で詳細パターンを参照する。着手前の「どの writing file を Read するか」は `skills/writing-knowledge` の判定表を使う。

**機械検出**: 通常の執筆・推敲では文長や段落長の統計を取らない。user が文体指標の測定を明示した場合だけ `scripts/jp-textlint.sh <file>` を診断用に使い、結果を読みやすさの合否や書き直し条件にしない。script の分担: `jp-textlint.sh` = 文構造統計の詳細診断 (NG 語判定は内部で jp-quality-lint.sh へ委譲) / `jp-quality-lint.sh` = hook と同一判定の NG 辞書検査 (`/jp-lint` の実測部、exit code あり)。NG辞書 canonical: [NG-DICTIONARY.md](NG-DICTIONARY.md) (「置換候補」 (頻出) は hook / script が機械参照する 1 行 key)、人が読む詳細置換表: [PRINCIPLES-word-replace.md](PRINCIPLES-word-replace.md)。

## 主要知見の所在

- スライド: assertion-evidence (文の主張見出し + 図の根拠) / Mayer 3 原則 / 3 秒テスト / 文字数値目安 → [slide-doc.md](slide-doc.md)
- 長文: 構造シート (主眼 + 要素・順番・軽重、完読基準) / Diátaxis / 濃淡設計 / ピラミッド原則 → [long-form-doc.md](long-form-doc.md)
- 文単位: 一文一義 / JTF 表記 / 漢字をひらく / 閉じてない文章の禁止 → [PRINCIPLES.md](PRINCIPLES.md)
- 作図: 既定は Mermaid (doc / issue / PR 共通、ASCII 罫線図は使わない) → [PRINCIPLES.md](PRINCIPLES.md) 「図は Mermaid で描く」
- 推敲観点: 推敲5観点 ([A]–[E]) → [PRINCIPLES.md](PRINCIPLES.md) 「推敲5観点」。短文の投稿前採点は [external-post.md](external-post.md) が同節へ対応づける

## ファイル一覧

### 共通

| ファイル | 用途 | 適用タイミング |
|---|---|---|
| [PRINCIPLES.md](PRINCIPLES.md) | 共通文章原則 (4問 / 9原則 / 4変換 / 媒体別構造 / 文書全体の読みやすさ / 推敲5観点 / 出力前セルフチェック) | 全ヒト向けdoc着手前。draft 前は構造ゲート (6 点) を先に適用 |
| [allowed-en-terms.txt](allowed-en-terms.txt) | 英語のまま許容する術語 list | NG 語判定の許容可否確認時 |
| [NG-DICTIONARY.md](NG-DICTIONARY.md) | NG 語辞書 canonical (機械参照の置換 key) | NG 語の追加・判定時 |
| [PRINCIPLES-word-replace.md](PRINCIPLES-word-replace.md) | 人が読む置換例の一覧 | NG 語の言い換え検討時 |

### 適用先別

| ファイル | 用途 | 適用タイミング |
|---|---|---|
| [commit-message.md](commit-message.md) | コミットメッセージ (抽象化 / NG/OK例) | `git commit` 前 |
| [pr-description.md](pr-description.md) | PR本文 + レビュー応答 (must/imo/nits/q) | PR作成・修正対応時 |
| [stacked-pr-chain.md](stacked-pr-chain.md) | stacked PR chain 運用 (worktree / rename 伝播 / build gate / 分割 audit / 前倒し統一) | 3 本以上の直列 chain PR 運用時 |
| [external-post.md](external-post.md) | 短文 (PRコメント / Slack / Issue / Notion) + 推敲5観点への対応表 | 外部向け投稿前 |
| [gh-issue.md](gh-issue.md) | GitHub issue 本文の書式 | issue 起票・編集時 |
| [narrative-writing.md](narrative-writing.md) | 読み物系 (blog / エッセイ / 取材記事) の構造原則。技術文書は対象外 | 読み物系の執筆時 |
| [long-form-doc.md](long-form-doc.md) | 長文doc (DD / PRD / RCA / Notionページ) + ADR/PRD/EARSテンプレ + Diátaxis 文書種別判定 + 構造ゲート適用 (draft 前) | 長文doc執筆時 |
| [slide-doc.md](slide-doc.md) | スライド・プレゼン資料 (1 スライド 1 メッセージ / 図解の型 / デザイン 4 原則) | スライド・発表資料作成時 |
| [design-doc-protocol.md](design-doc-protocol.md) | DesignDoc 4 Step + 10パターン + アンチパターン + セルフチェック18 | DD着手・レビュー対応時 |
| [strategy.md](strategy.md) | ドキュメント戦略 (6種別役割分担 / 保存先 / 命名規則 / Bounded Context) | 「どこに何を記載するか」判断時 |
| [code-comment.md](code-comment.md) | コード内コメント規約 (WHY / 重要 memo / godoc / 削除カテゴリ / AI marker 禁止 / Comment Traps 回避) | コメント追加・レビュー時 |
| [prompt-engineering.md](prompt-engineering.md) | AI / LLM 向け prompt writing (ヒト向けと目的逆) | Claude / GPT 等への instruction 作成時 |

### 関連 (他層)

| 場所 | ファイル | 用途 |
|---|---|---|
| `references/on-demand-rules/` | `ai-output.md` | AI出力強制ルール (禁止リスト、外向き text 起草時に Read) |
| `rules/` | `markdown.md` | markdown構造ルール |
| `rules/` | `no-local-path-in-shared-docs.md` | DD / PR / issue / Slack 等の共有 doc に `<ghq-root>/...` 等の個人 path を含めない |
| `references/on-demand-rules/` | `screenshot-resize.md` | PR / issue / Slack / Notion / local-docs へのスクショ添付前に必ずリサイズ (幅 1200px / 500KB 目安) |
| `guidelines/common/` | `notion-writing.md` | Notion固有フォーマット仕様 |
| `references/` | `writing-patterns.md` | 詳細パターン (書き直しPhase 1-8 / レビュー3段 / textlint / フェーズ境界) |
| `skills/` | `writing-knowledge` | 着手前に執筆する種別 → writing file 1〜2 件だけ Read する判定表 |
| `references/` | `document-iteration-patterns.md` | 書き直しの動的パターン |
| `references/` | `review-patterns-universal.md` | 汎用レビュー指摘パターン |

## 共通原則 (要約、詳細はPRINCIPLES.md)

- **内容に合う構造**: 並列の事実は箇条書き、因果関係や判断理由は段落で書く
- **構造 (場所) で束ねる**: ファイル / モジュール / レイヤー単位で束ねる。抽象観点 (what/why/how) でsectionを割らない
- **section重複を排除**: 同じ事実は1ヶ所にのみ書く
- **長さは内容に従う**: 自明は数行、設計判断を含む変更は原因や代替案も書く
- **AI臭の禁止**: 「Generated with X」「AIが生成」等の内部用語、過剰絵文字、定型フッターを含めない

## 媒体別quick reference

本表は代表媒体の抜粋で、着手前判定の正は `skills/writing-knowledge` の判定表とする。

| 書く対象 | 主参照 | 補足 |
|---|---|---|
| commit message | commit-message.md | PRINCIPLES.md (AI臭4変換) |
| PR本文 | pr-description.md | PRINCIPLES.md (媒体別構造 / PR description 4セクション) |
| PRコメント / Slack / Issue | external-post.md | PRINCIPLES.md (媒体別構造 / 短文PREP) |
| Design Doc | design-doc-protocol.md | long-form-doc.md (テンプレ) / PRINCIPLES.md |
| PRD | long-form-doc.md (PRD MoSCoWテンプレ) | strategy.md (保存先) |
| ADR | long-form-doc.md (ADRテンプレ) | strategy.md (命名規則) |
| RCA / Notionページ | long-form-doc.md | `common/notion-writing.md` (Notion固有) |
| 受け入れ基準 | long-form-doc.md (EARS) | PRINCIPLES.md |
| スライド・発表資料 | slide-doc.md | long-form-doc.md（[文書構造論](long-form-doc.md#文書構造論--prep-以外の選択肢)のピラミッド原則） |

## 衝突時優先順位

優先順は Notion 固有仕様 > スライド固有 (`slide-doc.md`) > 長文 doc 原則 > 短文向け原則 > 共通 PRINCIPLES の順となる。媒体がスライドのときは長文の結論先出し / 1 文 1 行より `slide-doc.md` を優先する。
プロジェクト固有CLAUDE.md は global guidelines/writing/ より優先する。

## ai-tools Writing Canonical Priority 詳細

`CLAUDE.global.md` `## Writing` の優先順 (1) `guidelines/writing/` canonical → (2) `rules/` → (3) project template をこの file が詳細化する。

### 優先順位 (high → low)

1. `<repo-root>/claude-code/guidelines/writing/` canonical (PR / commit / external-post / long-form-doc / code-comment / PRINCIPLES / NG-DICTIONARY)
2. `<repo-root>/claude-code/rules/` (minimize-questions / public-repo-private-data-block 等) + `references/on-demand-rules/ai-output.md`
3. project 側 template / convention (`.github/pull_request_template.md` / `.gitlab/merge_request_templates/` / `CONTRIBUTING.md` / project CLAUDE.md / project commit hook 等)

### 適用範囲 (ai-tools 優先)

PR / MR body 構成 / commit message format / Issue 投稿 / comment 書式 / Notion / Slack / Design Doc / PRD / RCA / 動作確認 section 構成 / 文体規約 (PRINCIPLES / readability / NG 語)

### project 優先で維持する (ai-tools 介入しない)

- 機械 enforce 系: `.editorconfig` / `.eslintrc` / `.prettierrc` / lint config / format hook / CI workflow / Makefile
- 構造 enforce 系: branch 命名規約 / tag 規約 / file 配置 / directory 構造
- license / copyright header
- 法務 / security 必須 footer (DCO sign-off / CLA 等)

### project template の固有要素の扱い

project template 内に label / checkbox / 自動化 trigger (例: `operation check` label / `- [ ] マニュアルテスト実施可否` / `resolve: <Issue URL>`) があれば ai-tools 7 section の該当 section に転記する。捨てない。

### competing rule の解決

project の CLAUDE.md / writing convention が ai-tools と衝突したら ai-tools 側を採用。project 固有事情 (regulated 業界 / 法務必須 wording) があれば user に escalate して例外 allowlist 化を提案する。
