---
allowed-tools: Read
name: writing-knowledge
description: guidelines/writing の知見を種別判定して 1〜2 file だけ読む。「スライド」「DesignDoc」「PRD」「RCA」「PR 本文」「commit」「Issue」「Slack」「Notion」「文章執筆」の着手前に使う。
---

# writing-knowledge — 文章・スライド知見の読込

外向き文章 / スライドの執筆・推敲前に、`~/.claude/guidelines/writing/` の該当知見だけを読み込む。`PRINCIPLES.md` の必要 section と下表の媒体別 file 1 件に限定し、最大 2 file にする。一覧と窓口契約の canonical は `guidelines/writing/README.md`。

> **責務分担**: この skill = 着手前の種別判定と Read 指示のみ（規範本文は格納しない）。知識 SoT は `guidelines/writing/`。`/jp-fix` = 推敲工程・Dynamic Load。種別 → file 対応は本表を正とし、jp-fix の Dynamic Load と合わせる。

## 判定表 (`PRINCIPLES.md` + 追加 1 file)

| 書くもの | Read する file |
|---|---|
| chat 応答の改善 / 簡潔化 | 追加なし (`PRINCIPLES.md` 「chat 応答の基本形」 + 「plain JP の文体」のみ) |
| スライド (Marp / PowerPoint / Google Slides / Keynote) | `slide-doc.md` |
| DesignDoc | `design-doc-protocol.md` |
| PRD / RCA / 長文 doc / local-docs decision | `long-form-doc.md` (decision は 「文書種別の判定」 + 「decision と investigation の境界」を優先) |
| 手順書 / runbook | `long-form-doc.md` (「手順書 / runbook (how-to) の書き方」を優先) |
| PR body | `pr-description.md` |
| commit message | `commit-message.md` |
| PR / Slack / Issue / Notion コメント (短文) | `external-post.md` |
| Issue 起票 (bug report / feature request) | `gh-issue.md` |
| Notion ページ本体 | `../../guidelines/common/notion-writing.md` |
| 読み物系 (blog / エッセイ / 取材記事) | `narrative-writing.md` (keyword が明示されない依頼でも、読後に読み手が判断・行動せず何かを感じ取る文章なら本行) |
| code comment | `code-comment.md` |
| stacked PR chain 運用 (3 本以上の直列 PR) | `stacked-pr-chain.md` |
| doc の保存先・種別の判断 (どこに何を記載するか) | `strategy.md` |
| AI / LLM 向け prompt / instruction | `prompt-engineering.md` (ヒト向け原則と目的が逆) |
| 深い書き直し / AI 臭除去 | この skill でなく `/jp-fix` を使う |
| 既存文書の NG 語検査・修正 | この skill でなく `/jp-lint` を使う (jp-quality hook と同一辞書判定) |

優先の切り分けは `/jp-fix` Dynamic Load と同じ: 短文コメント > Notion page、Issue 起票 > Issue コメント、スライド / 短文 / 起票 > 長文 heuristic。

## 手順

1. `PRINCIPLES.md` から対象に必要な section だけを Read する
2. 上表から種別を 1 つ判定し、追加 file があれば 1 件だけ Read する
3. 執筆後、`PRINCIPLES.md` の出力前セルフチェック (スライドは `slide-doc.md` のセルフチェック) を適用する
4. 適用した規則名・検査過程は、user が求めない限り報告に出さない
