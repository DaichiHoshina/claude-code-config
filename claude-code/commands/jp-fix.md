---
allowed-tools: Read, Glob, Grep, Bash, Edit, Write, mcp__serena__*
description: 読み手向け文章の品質 mode (JP 規範統合)
argument-hint: "[file or text]"
---

## /jp-fix - Writing Quality Command

Improve human-facing prose (PR body, Design Doc body, Notion, blog, Slack, email) **readability, visibility, clarity**.

Code body, code comments, docstrings out of scope.

> **Responsibility split**:
> - `/design-doc` = assemble design decision document
> - `/jp-fix` = **prose quality itself** (vocab, sentence flow, paragraph coherence, signal)

## JP 執筆規範 (write/rewrite 時に必須適用)

文体・構成・推敲観点の本文は `guidelines/writing/` が正本。この command は工程と Read 指示のみ扱う。

- 共通原則・推敲5観点: `guidelines/writing/PRINCIPLES.md`
- code comment の略し方・fail-safe 説明: `guidelines/writing/code-comment.md` 「「変に略さない」原則」（この command の prose 対象外。comment 作業時のみ）
- NG 辞書: user が NG 語・AI 臭さ・用語統一の監査を明示した場合だけ `guidelines/writing/NG-DICTIONARY.md` の `jp-fix 固有 NG (skill-only)` を参照する。通常の読みやすさ修正では辞書を load せず、語尾や単語の文字列一致を修正契機にしない
- PR body / 長い WHY: `guidelines/writing/pr-description.md`、10 行超の WHY の 3 階層分散は `references/writing-patterns.md`

## Subcommand

| sub | purpose | input | output |
|-----|---------|-------|--------|
| `write` (default) | write from scratch | goal/reader/topic | draft |
| `rewrite` | rewrite existing | file or paste | file は更新結果、paste は書き直した本文 |
| `review` | proofread (no edit) | file or paste | 5-axis check + finding list |
| `outline` | structure only | goal/reader/topic | heading hierarchy + intent per section |

no arg or `write` → write mode. First token vs subcommand match; no match → treat whole arg as write topic.

## 対象解決 (target resolution)

`review` / `rewrite` では user に聞き返さず、優先順で対象を自動決定する: (1) ARGUMENTS が existing file path → 該当 file / (2) paste block (3 行以上 / 引用記号付) → 該当 text / (3) write topic (subcommand 不一致 + 短文) → `write` mode 新規執筆 / (4) ARGUMENTS 空 + subcommand なし → 直前 assistant 出力を `review` 対象 / (5) `review` / `rewrite` 単独 → 直前 assistant 出力。`write` / `outline` で本文の意味が変わる前提だけが不明な場合は、下の 4-Question Checkpoint に従う。

## Pre-execution (required order)

**文体**: write/rewrite body・outline・review finding・progress のすべてを plain JP (`guidelines/writing/PRINCIPLES.md` 「plain JP の文体」。chat へ出す progress は敬体、文書本文は常体) で書く。

### 1. 4-Question Checkpoint (`write` / `outline` のみ)

詳細: `guidelines/writing/PRINCIPLES.md` "書く前の4問" 参照。`write` / `outline` で、回答によって本文の意味が変わる前提が不明な場合だけ **top 1 を質問**する (reader > judgment > action > evidence)。それ以外は入力から分かる範囲で進める。`review` / `rewrite` では質問しない。

### 1.5. Structure gate (outline / write / review / rewrite, mandatory)

`guidelines/writing/PRINCIPLES.md` の「文書全体の読みやすさ」を局所確認より先に適用する。`outline` / `write` では見出し設計 (各見出しは「見出し — 役割 — 所有する主張」) を本文より先に決める。`review` / `rewrite` では skeleton pass のあと局所修正へ進む。

### 2. Load Resources

`write` / `outline` の着手前は、種別が分かった時点で `skills/writing-knowledge/SKILL.md` の判定表に従い該当 1〜2 file を Read する (本表 Dynamic Load と種別対応を一致させる)。`review` / `rewrite` は下の Dynamic Load を優先する。

`guidelines/writing/PRINCIPLES.md` はコア層 (冒頭 index table の「check / rewrite 実行」行に列挙した section) のみ load する。詳細層 (AI臭を消す4変換 / 避けるパターン / Web 可読性詳細) と全文 load は深い書き直し (`rewrite` mode) 時のみ。深い書き直しでは、複数 section にまたがる構造上の問題を先に直してから局所的な文章を整える。詳細 pattern は `references/writing-patterns.md` on demand。媒体別 file は下の Dynamic Load から 1 件だけ選び、`PRINCIPLES.md` と合わせて最大 2 file にする。

### 3. Dynamic Load by Type

| Detect Keyword | Extra Load |
|---------|-----------|
| PR コメント / Slack / Issue コメント / Notion コメント (短文) | `guidelines/writing/external-post.md` (`## 最終チェック` の 5 軸採点も適用する。長文 heuristic・Notion page 行より本行を優先する) |
| Issue 起票 (bug report / feature request) | `guidelines/writing/gh-issue.md` (「起票」「bug report」「feature request」が付くときは Issue コメント行より本行を優先する。長文 heuristic より本行を優先する) |
| Notion / page | `guidelines/common/notion-writing.md` (Notion コメントは上の短文行が優先する) |
| Design Doc | `guidelines/writing/design-doc-protocol.md` |
| 長文 doc 全般 (PRD / ADR / RCA / 手順書ほか。種別 keyword 不一致でも見出し複数 or 1,000 字超なら該当) | `guidelines/writing/long-form-doc.md` を default で load する (結論先出しが正)。読み物系は `narrative-writing.md`、Design Doc は `design-doc-protocol.md`、スライド系は `slide-doc.md`、短文投稿は `external-post.md`、Issue 起票は `gh-issue.md` の行が優先する |
| 読み物系 (blog / エッセイ / 取材記事) | `guidelines/writing/narrative-writing.md` (長文 heuristic より本行を優先する)。keyword が明示されない依頼でも、読後に読み手が判断・行動せず何かを感じ取る文章なら本行を適用する |
| PR / pull request | `guidelines/writing/pr-description.md` |
| スライド / 発表資料 / プレゼン / Marp | `guidelines/writing/slide-doc.md` (メッセージライン通読を skeleton pass として使う。長文 heuristic より本行を優先する) |
| AI / LLM 向け prompt / instruction file (commands / skills / agents 定義や system prompt) | `guidelines/writing/prompt-engineering.md` (ヒト向けと目的が逆のため、ヒト向け原則の機械適用よりこの file を優先する) |
| user が文書全体の再構成や長期レビュー履歴の整理を明示 | `references/document-iteration-patterns.md` + `references/writing-patterns.md` "Rewrite Phases 1-8"。通常の読みやすさ修正では load しない |
| file 対象の write / rewrite | parent が本文を通読して直接更新する。汎用 `developer-agent` は実装タスク用の詳細な完了報告を返すため、文章推敲には委譲しない。意味・事実・論理のつながりを損なう箇所だけを修正する |
| file 対象の review / 委譲不発火時の rewrite | parent が本文を通読し、読み違え、主語と述語の不対応、論点の飛躍、重複を文脈で判断する。字数・文数・段落統計は取得しない |
| paste / chat 対象の review / rewrite | lint CLI が使えないため、`PRINCIPLES.md` 「推敲5観点」の [A] / [E] と 「文単位の品質規約」を目視評価する |
| 文体指標・AI 臭さの採点を user が明示 | `references/on-demand-rules/natural-japanese-lint.md` の lint CLI を診断用に実行できる。測定値は依頼された範囲だけ返し、通常の rewrite や完了判定へ含めない |

## 5-Axis Check (write/review/rewrite required)

観点本文の正本は `guidelines/writing/PRINCIPLES.md` 「推敲5観点」。この節には適用順だけを記載する。

1. 先に `PRINCIPLES.md`「文書全体の読みやすさ」で見出しと各段落の主張を確認する（structure gate Section 1.5）
2. `write` は見出し設計を本文より先に行い、`review` / `rewrite` は構成を修正してから 「推敲5観点」の局所確認へ進む
3. `outline` は structure gate のみで、推敲5観点は適用しない

**機械検出は明示依頼時のみ**: 通常の review / rewrite では lint JSON、文長統計、段落統計、採点を作らない。user が測定を求めた場合も、finding だけで書き直しを確定せず、前後の文脈を読む。書き直し前後の事実・時制・因果関係・書き手の評価が一致することを優先する。

## Output Format

- **write**: draft 本文を返す。読者や前提の推定が内容を左右した場合だけ、その前提を本文の後に短く添える
- **rewrite (file)**: file を更新し、最終応答は成果だけを直接述べる。変更した場合は文書全体に関わる要点を 1 文で返し、変更が不要なら「読み違いにつながる問題は見つからなかった」とだけ返す。「読みやすさチェックが完了した」「内容は明確」「他は修正不要」などの全体評価、個々の言い換え、触らなかった箇所、事実確認の過程、成功した build / lint と無関係な warning、今後の改善案は出さない。検証の失敗や未解決の問題は省かない
- **rewrite (paste / chat)**: 書き直した本文を返す。判断が分かれる変更だけ、本文の後に理由を最大 3 件添える
- **review**: `## Findings (priority order, max 5)` (`[axis] location → fix direction`)。採点を明示された場合だけ各軸の点数を添える
- **outline**: `## Structure` の番号付き `(heading) — 役割 — 所有する主張`。structure gate を満たさない見出しは出力前に直す

変更が不要な場合も、「品質が収束した」「改善点を出し切った」「これ以上は質が上がらない」と文書全体や将来の改善余地まで断定しない。「今回指定された観点では変更不要」と確認範囲を限定する。今回実行していない過去 turn の build / lint 結果を、現在の検証結果として再掲しない。

file 書き換え後の応答を、subagent の作業報告や diff の説明へ変換しない。例えば「やったこと」「判断して触らなかったところ」の見出しで工程を列挙せず、修正結果を短く伝える。

## Forbidden

- AI-smell prose / verbose boilerplate / write without 4-question pass
- full load writing-patterns (PRINCIPLES.md で十分)
- apply to code body/comment/docstring (out of scope)
- **Edit/Write in `review` submode** (findings only, no file change)

## Completion (per sub)

| Condition | write | rewrite | review | outline |
|-----------|:---:|:---:|:---:|:---:|
| 4-question pass | ✓ | ✓ | – | ✓ |
| Structure gate | ✓ | ✓ | ✓ | ✓ |
| 5-axis review | ✓ | ✓ | ✓ | – |
| Relevant pre-output checks | ✓ | ✓ | – | – |
| Meaning preservation | ✓ | ✓ | – | – |

ARGUMENTS: $ARGUMENTS
