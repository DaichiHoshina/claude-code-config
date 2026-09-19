---
allowed-tools: Read, Glob, Grep, Bash, Edit, Write
name: jp-fix
description: "Japanese output readability check & rewrite (PRINCIPLES.md canonical). Used when /jp-fix is invoked."
---

# Completion response hard gate

file rewrite の最終応答は成果だけにする。変更した場合は文書全体に関わる要点を 1 文だけ返し、変更しなかった場合は「読み違いにつながる問題は見つからなかった」とだけ返す。個々の変更箇所・変更理由・触らなかった箇所・検証工程・全体評価・「他は〜」という列挙・今後の改善案は返さない。失敗や未解決の問題だけは具体的に返す。この gate は下記の review / rewrite 手順より優先する。

# jp-fix — 日本語の可読性チェック & リライト

Goal: reduce cognitive load without changing the writer's meaning. Preserve facts, tense, causality, and stance before adjusting vocabulary, sentence structure, or layout. Follow `guidelines/writing/PRINCIPLES.md` 「文章生成の不変条件」; all evaluation criteria come from that canonical file (no list literals inside this skill).

## Startup behavior

On `/jp-fix` or a natural-language readability request, apply all self-checks below to the target text in the current conversation. Do not launch a forked skill context; it loses the natural-language target when no explicit arguments are passed. Output form depends on submode.

- `write` / `rewrite`: 書き直した本文をまとめて出す
- `review`: Findings のみで書き直し文は出さない (`commands/jp-fix.md` 「Output Format」 `review` 行と 「Forbidden」 の `Edit/Write in review submode` が該当箇所)
- `outline`: 見出し階層だけを出す。各見出しは「見出し — 役割 — 所有する主張」形式にする

Target priority (`review` / `rewrite` never ask back):

1. Current user request has a file path / pasted text → use it
2. Explicit ARGUMENTS has a file path / pasted text → use it
3. User explicitly refers to the previous assistant output → use that output
4. None of the above → write new text on the requested topic

`review` / `rewrite` では "What should I check?" と聞かず、上の優先順で対象を決める。`write` / `outline` で本文の意味が変わる前提が不明な場合だけ、`commands/jp-fix.md` の 4-Question Checkpoint に従って 1 問質問できる。評価前に code block (` ``` ` / `` ` ``) を除外する。

## Determine medium first

媒体の目的と読み手を先に決める (canonical: PRINCIPLES.md `## 媒体別構造` / `## Web 可読性`)。技術文書は判断根拠と前提、web / 短文は走査しやすさ、chat は自然な対話を優先する。文は、字数ではなく読み違えが起きる境界で分ける。

## Structure gate (outline / write / review / rewrite 共通)

`outline` / `write` / `review` / `rewrite` のいずれでも、局所的な文や語彙より先に `guidelines/writing/PRINCIPLES.md` の「文書全体の読みやすさ」を適用する。執筆 (`outline` / `write`) は見出し設計 → 本文、推敲 (`review` / `rewrite`) は skeleton pass → 局所修正。

## self-check

**評価軸 canonical**: `guidelines/writing/PRINCIPLES.md` 「推敲5観点」 ([A]-[E])。適用順は `commands/jp-fix.md` Section 5-Axis Check。

- PRINCIPLES.md はコア層 (冒頭 index table「check / rewrite 実行」行の section) のみ load する
- outline / write / review / rewrite では、同 file の「文書全体の読みやすさ」を A→E より先に適用する
- 問題が複数 section にまたがる場合は、局所的な言い換えで済ませず、重複の集約や構成変更まで行う
- PRINCIPLES.md の全文 load は深い書き直し時のみ

見出しがある文書、または `outline` / `write` で見出しを設計する文書では、局所的な文を修正する前 (執筆時は本文を作成する前) に次の **skeleton pass** (見出し階層と各 section の主張だけを抜き出して構造の破綻を先に見る作業) を内部で行う。各見出しは「見出し — 役割 — 所有する主張」として抽出する。

1. リードと各見出し、各段落の先頭文から、読み手の行動と section ごとの役割・所有する主張を 1 文ずつ抽出する
2. 結論と理由を所有する section を特定し、概要・比較・推奨・残課題などに同じ主張が分散していないか確認する
3. decision では、各案が同じ問いに答えるか、調査過程や訂正文が判断根拠に紛れていないか確認する。`guidelines/writing/long-form-doc.md` の「分離 / 統合の判断軸」と「decision と investigation の境界」も読む
4. 各 section が読後の判断や行動を変えない場合は、削除、統合、詳細への移動、別文書への分離を検討する

skeleton pass で構造上の問題が残存する場合は、局所的な文だけを修正して終了しない。`outline` では構造上の問題を解消した見出し階層だけを返す。`write` / `review` / `rewrite` では構造上の問題がないことを確認してから A→E の文・段落単位の確認へ進む。

### No-change hard gate

見出しがある file の review / rewrite で「問題なし」と判断する前に、次の証拠確認を省略しない。確認結果は内部で使い、user が求めない限り工程として報告しない。

- 同じ結論や理由を別 section が言い換えている場合は、所有先へ集約する。判定は全見出しと各 section の先頭文を抽出し、各 section の役割と中心主張を対応づけて行う
- 完成稿では `当初` / `初期の説明` / `訂正` / `追加調査` / `再調査` / `誤りだった` / `不正確だった` を Grep し、現在の判断に必要な証拠か、執筆・調査の経過メモかを各 hit で判定する。後者が 1 つでも該当する場合は変更不要としない
- `<!-- type: decision -->` または decision 文書では、本文を「決定する問い / 判断を変える証拠 / 選択肢 / 比較 / 推奨または決定 / 未決事項」に分類する。調査順序、実装の過程、訂正文、比較を変えない周辺調査は investigation または`<details>` で閉じた詳細へ移動する
- 推奨または決定の中心主張を、リード、背景、現状整理、比較、残課題から探す。新しい判断材料を加えず同じ主張を繰り返す箇所があれば変更不要としない
- 対象 file がローカルリンクで関連文書 (文書セット) を参照する場合、現在の file 単独で「問題なし」と判断しない。リンク先の metadata・タイトル・見出し・**正本表記** (同じ用語・略称を複数文書で 1 通りに統一した表記) を読む

  該当したら単語修正ではなく構成上の問題として扱う (`guidelines/writing/long-form-doc.md` 「文書セット設計」):
    - 重複した結論
    - 同じ論点への異なる正本表記
    - status と本文の不一致 (`status: approved` の未決表現)

  字数・節数・短文化のノルマはこの確認に追加しない

Grep の hit 数や section 数だけでは書き直さない。各 hit の文脈を読み、ADR / RCA に必要な履歴や、別概念を意図した用語は保持する。

通常の review / rewrite では lint JSON や文章統計を作成・受領しない。user が文体指標の測定を明示した場合だけ診断結果を参照し、通常の書き直しや完了判定へ含めない。指標の有無にかかわらず、`PRINCIPLES.md` 「推敲5観点」の [A] / [E] と 「文単位の品質規約」・`### 圧縮文を開く` を目視する。

変更するのは、読み違い、判断の阻害、論理の断絶につながる箇所だけにする。意味が明確な英語用語や類義語を好みで置き換えず、再点検のたびに新しい変更を作らない（`PRINCIPLES.md`「文章生成の不変条件」）。

rewrite 前後を比較し、元にない事実・時制・因果関係・評価を加えていないことを確かめる。表現を変化させる目的で、受益・後悔・継続などの意味を加減しない。既存表現を語尾の文字列だけで置換しない。

## Rewrite output format

`write` / `rewrite` 時のみ適用する (`review` は Findings のみで書き直し文を出さない、Startup behavior 参照)。hit の列挙や文体規則の適用報告で止めず、書き直した本文をまとめて返す。具体的な動作・状態・数値は入力にあるものだけを使い、不足している事実を補わない。

file を更新した場合の結果は、成果だけを直接述べる。変更した場合は文書全体に関わる要点を 1 文で返し、変更が不要なら「読み違いにつながる問題は見つからなかった」とだけ返す。「読みやすさチェックが完了した」「内容は明確」「他は修正不要」などの全体評価、個々の言い換え、触らなかった箇所、事実確認の過程、成功した build / lint、今後の改善案を返さない。失敗や未解決の問題は省かない。

問題が見つからなければ「読み違いにつながる問題は見つからなかった」とだけ返し、採点過程や hit 件数は出さない。

## Hook integration

Hook block / warn behavior and log format are defined in `hooks/pre-tool-use.sh` / `hooks/user-prompt-submit.sh` (canonical). Weekly aggregation: `scripts/analytics-report.py`. Skip all inject: `JP_QUALITY_INJECT_OFF=1`.
