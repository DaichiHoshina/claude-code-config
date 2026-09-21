# 長文ドキュメント執筆 (DesignDoc / PRD / RCA / Notionページ)

共通原則は [PRINCIPLES.md](PRINCIPLES.md) 参照。

> **原則**: ドキュメントは記憶ダンプではなく、読み手の判断と行動を助ける道具。書くたびに「誰のどの判断を助けるか」から逆算する。

本文は全種別 (DesignDoc / PRD / RCA / local-docs HTML / Notion) で **開いた文章 (plain JP) + 簡潔ミニマル** を守る。箇条書きも意味が伝わる形にし、名詞句で十分な項目名や結果を無理に動詞文へ変えない。該当しない template section は見出しごと削除する (canonical: `guidelines/writing/PRINCIPLES.md`)。

## Writing Contextブロック (任意、draft冒頭)

書き出し時に思考を散らさないため、4問の答えをコメントブロックでdraft冒頭に置く:

```markdown
<!-- Writing Context (4 問・最終削除任意)
読み手: <人物像>
読後アクション: <approve / 実装 / 質問 等>
確認済みの根拠: <数字・事例・code・log。無ければ未測定と記す>
なぜこれが必要: <問題 or PRD 接続>
-->
```

抽象語で埋めても無意味。確認済みの人物像・根拠・問題を記載する。未確認の数字や事例は作らない。

### AI hallucination 防止 (起動時の補足)

長文 doc を AI と書く場合、推測で書いて hallucination を埋め込む事故が多い。下記 3 つを起動時に必ず守る。

- **新 library / API method を直書きする前に、`context7` skill または WebFetch で最新 docs を確認**する。記憶を信用しない (CLAUDE.md `## Library API Live Doc Required` と整合)
- **検証していない数値・log・metric を含めない**。「不明」「未測定」と記してレビュー時に補完する方が事故が少ない
- **「分からない場合は答えない」を貫く**。空欄や `TBD` にしておく方が、もっともらしい誤情報より安全

### AI 臭の確認 (draft 完成後)

通常は本文を通読し、論点の飛躍、意味の重複、翻訳調を文脈で確認する。文長・段落長・語彙の統計は取らない。user が文体指標の測定を明示した場合だけ `references/on-demand-rules/natural-japanese-lint.md` を診断用に使う。

## 文書種別の判定 (Diátaxis、draft 前)

構造ゲートの前に、読み手の状態から文書の種別を 1 つ採用する ([Diátaxis](https://diataxis.fr/) の 4 分類)。「読む目的を 1 つにする」(PRINCIPLES.md 構造ゲート 1 点目) の判定基準として使う。

| 種別 | 読み手の状態 | 書き方 | この repo での対応物 |
|---|---|---|---|
| **tutorial** | 学習中。手を動かして身につけたい | 成功体験を保証する一本道。選択肢や背景説明を入れない | onboarding 手順 / 入門 doc |
| **how-to** | 作業中。特定の目的を達成したい | 目的 1 つに対する手順列。前提条件を冒頭に明示 | runbook / 手順書 |
| **reference** | 作業中。正確な仕様を引きたい | 網羅・正確・引きやすさ優先。物語にしない | API 仕様 / config 一覧 / template |
| **explanation** | 学習中。背景と理由を理解したい | なぜその設計かを説明。手順を含めない | DesignDoc 背景節 / ADR / RCA 分析 / local-docs decision |

1 文書 1 種別を原則にする。tutorial に reference の網羅性を含める、how-to に explanation の背景論を入れる、が読みにくさの典型源になる。別種別の内容が必要なら link で分離する。DesignDoc / PRD のような複合文書は、section 単位でどの種別かを意識して書き分ける。

**local-docs `type: decision`**: 本流は問い・比較・採用 / 捨てるものに限る（explanation）。調査過程・実装手順・file 一覧は本流に置かず、investigation / plan / 付録へ移動する。詳細の正本はこの file 「decision 専用 hard checklist」（local-docs skill は Read 指示のみ）。

## 手順書 / runbook (how-to) の書き方

Diátaxis の how-to に当たる手順書は、作業中の読み手が途中の step からでも読める形にする。

- 前提条件 (権限 / 環境 / 開始状態) は手順より前に 1 block でまとめる。手順の途中で前提を後出ししない
- 手順は 1 step 1 操作の番号付き list で書き、各 step に「実行する操作」と「成功を確かめる観測点 (出力・画面・状態)」を対で書く
- 失敗時の戻し方 (中断・rollback の手順) を手順本体と同じ粒度で書く。「問題があれば戻す」だけの記述にしない
- 背景説明や設計理由 (explanation) を手順列に入れない。必要なら冒頭 1-2 文に留めるか、設計文書への link にする
- 環境差・条件差の分岐は IF-THEN で明文化し、「適宜」「状況に応じて」を使わない (PRINCIPLES.md 「chatとdocumentで文体を分ける」 の document 基本ルール)

## 図解の型 (参照)

長文 doc で数値・関係・流れを図で渡すときの型選択は [slide-doc.md](slide-doc.md) 「図解の選択」 を共用する。mermaid の型固定と構文の注意点は [design-doc-protocol.md](design-doc-protocol.md) 「図表の型を固定する」 / 「Mermaid 構文の注意点」 を参照する。グラフには「何を読み取ってほしいか」の注釈と、数値の出典・計測条件を添える。

## 構造シート (draft 前の準備、ナタリー式)

書き始める前に、主眼 (この文書で言いたいこと 1 つ) と骨子を書き出してから本文に入る (唐木元『新しい文章力の教室』の構造シート)。骨子は 3 要素で決める。

- **要素**: 入れる事実・論点を列挙する
- **順番**: どの順で出すか (結論先出しと整合させる)
- **軽重**: どれを厚く、どれを薄く書くか (下の「濃淡設計」と同じ判断)

品質基準は「完読」— 読み手が途中で離脱せず最後まで読み切れること。迷ったら「この 1 文は完読を助けるか」で削る。

## 構造ゲート適用 (draft 前)

本文を執筆する前に、`PRINCIPLES.md` の「文書全体の読みやすさ」を適用する。見出し設計 → 本文の順で、読む目的、結論の所有 section、比較可能な選択肢、現在の状態、用語、因果の追いやすさを先に決める。6 点の再掲はしない。適用例は上の「文書種別の判定」と下の「濃淡設計」「分離 / 統合の判断軸」「decision と investigation の境界」。

## 品質検証タイミング

各 command の self-check 発動タイミングと loop 上限は `references/writing-check-protocol.md` を canonical とする (`/spec-design` Step 8.5 / `/prd` Phase 4.5 / `/post-comment` Step 2.5 / `/git-push` Step 2・5.5 / `/retrospective` `/diagnose` 長文出力前)。draft 前の構造ゲートはこの file「構造ゲート適用」と `PRINCIPLES.md`「文書全体の読みやすさ」を参照する。

**Web 出力 (Notion / GitHub / Confluence) 時は追加チェック 4 項目**: 長文の分割 / 内容を示す heading / 1 段落 1 主張 / 必要な箇所の強調 — 詳細 `PRINCIPLES.md` `## Web 可読性`。

## 1 文 1 行format (sentence-per-line)

DesignDoc / PRD / RCA など Git 管理長文 md に適用する規約。詳細: `guidelines/writing/PRINCIPLES.md` 「markdown 長文 doc」 参照。Notion など WYSIWYG 系本文には適用しない (改行が段落分割として描画されるため)。

## 分量目安

長さ・分割の基準は `PRINCIPLES.md` の「### 長文 (Design Doc / PRD / RCA / Notionページ)」を参照。

## 濃淡設計 (全節同厚の禁止)

構造ゲートの適用例。全 section を同じ厚みで書くと、それ自体が「整いすぎた不自然さ」= AI 臭になる。重要な節を厚く、軽い節は正直に 1〜2 文で書く。書くことがない section はテンプレにあっても空埋めや「特になし」の埋め草で埋めず、削るか「該当なし」1 行にする。全節同厚の検出は見出しと各段落先頭文だけを抽出して通読するスケルトンレビューで行う。

長文 blog / 記事系では、素材に失敗談・つまずいた箇所・感想がある場合だけ記載する。人間らしさを作る目的で経験や感情を追加しない。技術規範 doc (RCA / DD / PRD) は事実だけを記載する。

## 分離 / 統合の判断軸

構造ゲートのうち「読む目的を 1 つにする」「同じ問いへの選択肢を比べる」の適用例。複数 doc / 1 doc 内 cell 構成の判断:

| 状況 | 推奨 |
|---|---|
| 役割境界明確 (計画 SoT vs 当日 runbook) | 分離維持 |
| scroll 長すぎ / 編集競合多発 / 開く目的混在 | 分離 |
| 調べた事実・仮説と、採用する案・不採用理由が同じ流れに混在 | investigation と decision に分離 |
| 1 つの案に独立した複数の判断が束ねられている | 判断対象ごとに分離 |
| 1 cellに詰め込みすぎで section 境界見えず | cell 分割 |
| cell 数を増やしても見やすくならない | 凝縮 (cell 数より論理単位) |

**統合の誤りやすい点**: 当日 runbookに Phase 表 / 指標定義が入ると視認性悪化。

### decision と investigation の境界

構造ゲートのうち「結論の置き場所を 1 つにする」「現在の状態を記載する」の適用例。

- **investigation** は、何が起きたか、どの仮説を確認したか、何が未確認かを記録する
- **decision** は、何を決めるか、同じ問いに対する候補、比較、採用理由、受け入れる不利益を記載する
- decision に必要な調査結果は、判断を変える証拠だけを要約して investigation へリンクする。調査順序や訂正文は移さない
- 採用案が未定でも、候補比較と決定依頼が本文の中心なら decision として扱う。確認した事実・仮説・追加調査が中心なら investigation として扱う

## 文書セット設計 (関連文書間の所有)

ローカルリンクで相互参照する関連文書群 (例: investigation / decision / designdoc / implementation) は、個別 file 単位でなく set 全体で役割と正本を設計する。文書間所有の正本はこの節とする。既存手法の取り込みは軽量に留める: DITA の 1 トピック 1 質問、ADR の 1 記録 1 決定 (下の 「ADRテンプレ」)、Google design doc の scope / non-scope 明示だけを使い、DITA の XML や新しい文書形式は導入しない。

### 所有マップ (本文作成前)

本文を執筆する前に「論点 — 所有文書 — 他文書で許可する要約」の対応を決める。1 論点の結論と根拠を所有する文書は 1 つにする。

| type | 所有する内容 |
|---|---|
| investigation | 事実・原因・仮説・未確認事項 |
| decision | 問い・決定・受け入れる不利益 |
| designdoc | 決定後の設計 |
| implementation / plan | 変更箇所・手順・テスト |

- 他文書が所有する内容は、一文の要約とリンクだけにする。段落単位の再掲や理由の言い換えは重複所有として、単語修正でなく構成から直す
- 同じ論点の正本表記 (「〜の正本はこの file」) は set 内で 1 文書だけに与える。2 文書が同じ論点の正本を主張したら矛盾として解消する
- 各文書は scope / non-scope を定め、所有しない論点は non-scope としてリンクだけ置く

### 呼称の統一 (set 横断)

- set 内で他文書を指す呼称は 1 文書 1 つに固定する (例: 相談資料)。本文の link text も同じ呼称にする
- 関連 / 参照一覧では正式タイトルを書き、呼称を括弧で併記する (例: 「決済が終わらない場合のサイズ選択をどう扱うか (相談資料)」)。呼称だけの旧タイトル表記はクリック先とタイトルが一致せず迷子の原因になる
- 文書を改題したら、set 全体の呼称と link text を同じ変更で更新する
- 自己言及語 (この doc / この file / 本書) は set 内で 1 語に統一する

### status と本文の整合 (set 横断)

- `status: approved` の本文に「推奨」「採った場合」などの未決表現を含めない。決定として言い切る (pending 側の整合は 「decision 専用 hard checklist」)
- 横断確認の対象は本文だけにする。共有 CSS / JavaScript / skeleton は対象外
- 字数・節数・短文化のノルマはこの確認に使わない

## type 別の本文品質 (postmortem / report / plan / decision)

報告系 doc (local-docs 含む) の type 別差分。共通規範はこの file と `PRINCIPLES.md`「文章生成の不変条件」に従う。

| Type | type 別差分ルール |
|---|---|
| postmortem / investigation | 時系列は絶対時刻 HH:MM + 主語 + 観測事実 (相対表現禁止)。影響範囲は定量化 (ユーザ数 / 期間 / 失敗率 / 金額)。symptom と root cause を分離。障害調査は 5 Why で構造要因まで掘る。再発防止は検証可能 action (担当 / 期限 / 完了条件)、「注意する」不可 |
| report | 数値は出典 + 計測条件を添える (link / query / 期間)。事実の節と解釈の節を分ける。推測は「推定」「仮説」と明示。次アクションは誰が何を判断できるかを 1 行で書く |
| plan | 作業フェーズは依存順 + 完了条件付き。リスクは発生確率 + 影響 + 回避策セット |
| decision | 同じ問いに答える選択肢を同一軸で比較し、独立した判断を 1 案に束ねない。採用 / 不採用は trade-off を明示し「何を却下したか」を記載する。判断を変える証拠だけを本文へ要約する (上の 「decision と investigation の境界」) |

### decision 専用 hard checklist

decision type では以下を満たしてから本文を執筆する (1 つでも満たさなければ執筆しない / 書き直す)。

- 今日決める問いを番号で列挙する。既決は 1 行で鎖し、未決だけ本流に記載する
- 結論と理由の所有 section は判断ごとに 1 つ。概要 callout は入口のみとし、理由の再掲は禁止する
- 独立判断が 2 つ以上なら判断単位で section を分けるか別 doc にする。1 案に束ねない
- how-to（実装順・リリース順）と reference（path 一覧）は本流禁止。付録（末尾 / `<details>`）か plan / design へ移動する
- `status: pending` の本文に「確定した」「採用済み」を含めない（metadata と本文の整合必須）
- Diátaxis: decision 本文の主種別は explanation（なぜ採るか）。手順・網羅一覧を含めない

decision の結論と理由は 1 つの section が所有する。リードや概要表は、その section を開かなくても判断の枠を把握できる範囲に留め、理由を言い換えて繰り返さない。

## SoT 階層の正本判定

複数文書 (DesignDoc / 計画 notebook / 実行runbook / loadtest scenario) の整合性チェックで矛盾を発見したとき:

- **DesignDocを正本**として扱う
- 派生文書 (notebook / runbook) がDesignDocに無い項目を独自追加していたら、削除 or 注釈で位置づけを明示
- 試験中観測と本番監視で対象が異なる場合は注釈を入れる (例:「試験中観測のみ、本番監視対象外」)

## 突合観点 (関連 SoT 間の整合性)

複数文書間で下記を表で突合:

- テストデータ (規模・件数・単位)
- 観点 (試験項目・指標・仮説)
- 結論反映先 (未決事項 No.X → 何で処理されるか)

執筆者は上流 SoT と下流文書の対応関係が失われていないか確認する。

## 既存の3層チェック (対話型リライト)

draft完成後の仕上げ。

| Layer | 目的 | 対象 / 発動 | 質問形式 |
|-------|------|-----------|---------|
| 1 Intent | セクション主旨を言語化、主旨外を削除候補 | 主旨の異なる内容が同じ section に混在する場合 | 自由記述「このセクション『<見出し>』で何を伝えたい？」 |
| 2 Understanding | 難解語をユーザーの言葉で再定義し置換 | 対象読者が意味を取れない用語がある場合 (`user_vocabulary.md` 既知語skip) | 自由記述「『<用語>』ここでどういう意味？」 |
| 3 Expression | AI定型・硬い文語・根拠なき評価語除去 | 下記NG辞書ヒット | `AskUserQuestion` [そのまま / 削除 / 根拠追記 / 書換] |

**Layer 2反映**: ユーザー回答文を **AIで言い換えず原文のまま** draftに置換、`user_vocabulary.md`「用語定義」追記。説明できない場合は `AskUserQuestion` で [調べる / 削除 / 曖昧なまま保持する]。

### トリアージルール (質問過多回避)

質問は、回答によって本文の意味や判断が変わるものだけに限定する。

| Layer | 省略条件 |
|-------|---------|
| 1 Intent | 各 section の主旨が本文から明確に読める |
| 2 Understanding | 対象読者に未定義の用語がない |
| 3 Expression | 文脈上の読み違えの原因になる表現がない |

## NG辞書 (長文向け検出)

[NG-DICTIONARY.md](NG-DICTIONARY.md) を canonical とする。Layer 3 の検出 category は同 file の AI 定型語 / 硬い文語 / 評価語に対応する。

## Before/Afterサンプル

抽象→数字 / 難語定義 / 評価語→根拠の基本変換は `PRINCIPLES.md` の `## AI臭を消す4変換` を canonical とする。ここでは長文 doc 固有の 2 観点のみ挙げる。

| 観点 | Before | After |
|------|--------|-------|
| 結論先行 | ドキュメント作成を効率化する仕組みです | Notionへmdを直接投稿できる。手動コピペを無くすのが目的 |
| 箇条書きの関係が不明 | 並列でない項目を同じ階層に置く | 並列・因果・上位下位の関係が分かる構造にする |

## user_vocabulary.md

`~/.claude/projects/{project}/memory/user_vocabulary.md` に蓄積。形式: `用語定義` `セクション主旨` `嫌う表現` `好む言い換え` の4セクション、各 `項目 — 内容 (YYYY-MM-DD)`。

## 文書構造論 — PREP 以外の選択肢

PREP (`PRINCIPLES.md` 既出) は「結論先出し → 理由 → 例 → 結論再確認」で **判断 / 採否を促す** ケースに最適。文書の目的が異なる場合は別構造を採用する。末尾の再掲は、詳細を読んだ後の判断や次の行動を更新する場合だけ配置する。冒頭と同じ結論を言い換えるだけなら削除する。

| 構造 | 適用場面 | 順序 | Why |
|---|---|---|---|
| **PREP** | 採否を促す決定文書 (PR 本文 / 提案 / RCA 結論) | Point → Reason → Example → Point | 結論を先に渡し検討負荷を下げる |
| **SCQA** | 問題提起 / 経営提案 / 投資稟議 | Situation → Complication → Question → Answer | 「なぜこの問いか」を共有してから解を渡す。読み手が当事者意識を抱きやすい |
| **SDS** | 短報告 / メール / Slack 投稿 | Summary → Details → Summary | 冒頭で結論を渡し、末尾では詳細を踏まえた次の行動を示す |
| **ピラミッド原則 (Minto)** | 大型 proposal / 戦略文書 / 多論点 deck | 結論 → (縦: なぜ?) + (横: 他にあるか?) で MECE 分解 | 多論点を MECEで階層化、論証強度が読み手に伝わる |

**判断**: 採否決定 → PREP / 問題提起 → SCQA / 短報告 → SDS / 多論点戦略 → ピラミッド。同一文書内で構造混在はしない (例: SCQAで始めて途中からPREPに切り替えると論証の前提が成り立たなくなる)。

### SCQAテンプレ (架空例)

```
Situation (現状): 自社の通知配信は SES + cron で日次 10 万通を処理している。
Complication (変化): 季節キャンペーンで瞬間 50 万通 / 時の要件が発生、cron では完走 5 時間で SLA 1 時間を満たさない。
Question (問い): どの方式で 50 万通 / 時を達成するか。SES 維持 + 並列化 / SQS + Lambda 化 / マネージドサービス置換 の 3 案。
Answer (解): SQS + Lambda 化を採用。根拠は (1) 既存資産再利用 (2) スループット線形 scale (3) コスト前年比 +15% で許容範囲。
```

### SDSテンプレ (短報告、架空例)

```
Summary: 負荷試験完了、p95=320ms (目標 1s)、deadlock 0 件、本番 GO 判断可。
Details:
  - Phase 1 (60 VU): p95=180ms / success 100%
  - Phase 2 (200 VU): p95=320ms / success 99.97%
  - deadlock 0 件 (全 Phase)
Summary 再: 全 Phase で SLO 充足、deadlock リスクなし、本番 GO で問題ない。
```

## ADRテンプレ (1テーマ1 Decision)

`{topic}` 1テーマ・`Decision` 1つの原則。複数決定を1 ADRに含めない。

```markdown
# ADR: [タイトル]
Status: [proposed | accepted | rejected | deprecated | superseded by ADR-XXX]
Created: YYYY-MM-DD

## Context  — 背景・動機・課題・ステークホルダー
## Discussion  — 代替案と pros/cons（案1/案2…）
## Decision  — 決定事項1つ + 主な理由
## Consequences  — 短期/長期のプラス・マイナス影響
## Compliance  — lint / レビュー / hook 等の担保方法
## Notes (任意)  — 参照資料・関連ADR
```

**注意**: 決定が覆る場合は元ADRを編集せず、新ADRで `Status: superseded by ADR-XXX` とする。

## PRD MoSCoWテンプレ (Must/Should/Could/Won't)

実装着手前にビジネス要件・ユーザーストーリーを固定。

```markdown
# [機能名]: PRD

## 概要 — 全体像3-5行、誰のどんな体験か
## 課題と目的 — 現状問題(箇条) / 達成目的
## ユーザーストーリー (MoSCoW)
- Must: [ユーザー]として[実現したいこと]をしたい。なぜなら[理由]
- Should / Could / Won't
## 機能仕様 — 基この機能・詳細・制約条件
## 非機能要件 — p95レイテンシ / セキュリティ / 可用性
## 技術的考慮事項 — 既存システム制約・他チーム依存
## UX/UI仕様 — 画面遷移・ワイヤー
## テスト計画 — 受け入れ基準・回帰観点
## 成功指標(KPI) — 数値で測れる成功定義
## スケジュール — マイルストーン・依存関係
## 関連ドキュメント
```

**MoSCoW運用**: 「全部Must」は優先順位放棄でNG。Won'tを記載するとスコープ拡大を防げる。

**prototype-first 運用 (Cagan 2024-2025)**: PRD 本文を厚くするより、clickable prototype / wireframe / 画面遷移図の link を本文中で参照する方が discovery を進めやすい。`## UX/UI仕様` には Figma / wireframe link を置くことを推奨する。link が無い PRD は実装に入れない判断基準にするとよい。

## EARS受入基準 (WHEN/IF/WHERE + THEN)

受け入れ基準・バリデーション仕様は **EARS形式**で書く。自然言語の曖昧さを排除し、テストケースが機械的に書ける。

**基本パターン**:

```
WHEN [イベント] THEN システムは [応答]
IF [前提条件] THEN システムは [応答]
WHERE [配置/状態] THEN システムは [応答]
WHILE [継続的状態] THEN システムは [応答]
```

**例**:

```
WHEN ユーザーが「購入」ボタンを押下した場合
THEN システムは決済処理を開始する

IF 在庫数が 0 の場合
THEN システムは「在庫切れ」エラーを返す

WHERE ソート順が NULL の場合
THEN システムは該当アイテムを最後に表示する
```

### バリデーション網羅観点 (必須チェックリスト)

入力項目ごとに以下を全部書く:

- [ ] **データ型**: 整数以外・文字列以外・真偽値以外
- [ ] **範囲**: 最小値未満・最大値超過・文字数超過
- [ ] **必須/任意**: 必須項目が未入力・空文字列・NULL
- [ ] **形式**: メールアドレス・電話番号・URL・日時形式
- [ ] **NULL**: NULL許可項目の動作 / NULL不許可項目のエラー
- [ ] **関連性**: 開始日時 > 終了日時 / 最小値 > 最大値
- [ ] **重複**: 既登録・ユニーク制約違反
- [ ] **存在**: 指定IDが存在しない・削除済み

「正常系のみ書いて出す」がよくあるバグ温床。8観点を機械的にチェック。

## 報告書 / 振り返り構造

報告書・障害報告・1on1 振り返り・sprint reviewは **事実 / 解釈 / 提案** または **KPT / YWT** で分離する。混在禁止。

### 報告書: 事実 / 解釈 / 提案 三層分離

障害報告 / 顧客報告 / 監視結果共有は 3 層を明示的に section 分離する。

| 層 | 内容 | 書き方 |
|---|---|---|
| **事実** | 観測値・log・metric・時系列 | 数値と時刻のみ、評価語ゼロ |
| **解釈** | 原因の推論・影響範囲・関係性 | 「と推定する」「が原因と判断する」根拠併記 |
| **提案** | 次の行動・防止策・調整事項 | 担当 + 期限 + 期待効果 |

**Why**: 事実と解釈の混在は読み手に「記述内容は確定値か推論か」を判断させ、認知負荷が上がる。事実層の数値だけ抽出して別判断したい読者のために 3 層分離する。

**blameless 原則 (postmortem / RCA / incident report)**: 主語を「個人」ではなく「system / process / 仕組み」にする。「A さんが手順を省略した」ではなく「checklist に該当 step がなく、目視確認に依存していた」と書く。再発防止 (提案層) も「個人の注意喚起」ではなく「自動化 / lint / hook / 手順書改訂」で書く。詳細: `local-docs` skill の postmortem 本文ルール。

### KPT (Keep / Problem / Try)

振り返り (1on1 / sprint review / 事後検証) で課題と継続を分離する三分割。

| 項目 | 内容 |
|---|---|
| **Keep** | 続けたい良い習慣・成功した手法 |
| **Problem** | 直面した課題・改善余地のある手順 |
| **Try** | 次に試す改善案・期限 + 担当 |

P (Problem) と T (Try) の対応関係を 1:1で書く (P3 → T3)。Pだけ書いて Tがないと actionにならない、Tだけ書いて Pがないと根拠不明。

### YWT (やった / わかった / 次にやる)

KPTの軽量版。正の学習サイクル中心、短文で書く。

| 項目 | 内容 |
|---|---|
| **やった (Y)** | 今回実施した内容 |
| **わかった (W)** | 学んだ知見 / 失敗 / 制約 |
| **次にやる (T)** | 次回の action |

KPTは課題明示が必須、YWTは継続学習の記録に特化。週次や日次の軽い振り返りは YWT、月次以上の改善には KPTを使う。

### 議事録: 決定 / 検討 / 持ち帰り 三分割

ミーティング議事録は 3 種類を分離することを推奨する。

| 種別 | 書き方 |
|---|---|
| **決定事項** | 担当 + 期限明示。確定したことのみ |
| **検討中** | 次回アジェンダ化。「次回までに Xを調査して持参」 |
| **持ち帰り** | 担当 + 期日。会議外で確認 / 相談する |

3 種類が混在すると参加者間で「決まったこと」の認識がずれる。決定事項だけを section 抽出して Slackへ投稿できる粒度に整える。

## AI prompt の引用記法

長文 doc 内で AI prompt (Claude / GPT 等への指示文) を引用する場合は、地の文と分けて以下の 2 形式で区別する。

| 場面 | 記法 |
|---|---|
| 単一行 prompt | バッククォート inline (`` `次の log を 3 行で要約して` ``) |
| 複数行 prompt | code fence + lang tag (`` ```prompt `` または `` ```text ``) |

```prompt
あなたは SRE です。以下の log から障害の起点 (timestamp + service 名) を 1 行で抽出してください。
回答は JSON 形式 `{ "timestamp": "...", "service": "..." }` のみとし、説明文を付けないでください。
```

地の文に prompt を埋め込まない (`「〜してください」と頼んだ` のような間接話法は再現性が下がる)。doc を読んだ人が同じ prompt を再現できる粒度で書く。

## コマンドとの接続

| コマンド | 適用 |
|---------|------|
| `/spec-design` | Step 3.5 structure gate と骨子 → draft → Step 7.5 writing-check-protocol。書き出し前4問、draft完成後 [DDセルフチェック18](design-doc-protocol.md) |
| `/prd` | Phase 1.9 structure gate → Phase 2 draft → Phase 4.5 writing-check-protocol。MoSCoWテンプレ使用 |
| `/git-push --pr` | PR 本文は [pr-description.md](pr-description.md) canonical。writing-check-protocol (Step 2 / 5.5)。この doc の 4 問は draft 起点として併用 |
| `/diagnose` 長文 / `/retrospective` | 出力前に structure gate を含む writing-check-protocol。箇条書きだけで終わらせない |

## 関連

- [PRINCIPLES.md](PRINCIPLES.md) — 共通原則 (4問 / 9原則 / 4変換 / 媒体別構造 / 文書全体の読みやすさ / 出力前セルフチェック)
- [design-doc-protocol.md](design-doc-protocol.md) — DD 4 Step + 10パターン + アンチパターン + セルフチェック18
- [external-post.md](external-post.md) — 短文向け (PRコメント / Slack / Issue + 5軸採点)
- [strategy.md](strategy.md) — ドキュメント種別・保存先 / 体系原則
- `guidelines/common/notion-writing.md` — Notion固有フォーマット (主語必須・見出し階層)
- `references/writing-patterns.md` — 詳細パターン (書き直しPhase / textlint / フェーズ境界)

衝突時優先順位: Notion固有 > 長文doc原則 > 共通PRINCIPLES。
