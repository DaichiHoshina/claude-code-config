# Writing check protocol (canonical)

外向き text を permanent store (file / PR / issue / Notion / commit / MR) に書き出す前に実行する self-check の共通仕様を集約する。文体指標より `guidelines/writing/PRINCIPLES.md` の「文章生成の不変条件」を優先する。

## 参照元 (7 command)

以下の command が本 protocol を参照する。各 command 側には check 対象の doc 種別のみ記載する。

- `commands/sdd-design.md` (Step 8.5)
- `commands/prd.md` (Phase 4.5)
- `commands/post-comment.md` (Step 2.5)
- `commands/git-push.md` (Step 2 / Step 5.5)
- `commands/diagnose.md` (長文 Notion/md 出力前)
- `commands/retrospective.md` (Notion/md 向け prose 出力前)

## 共通仕様

- **Check 対象**:
  - Structure gate: `guidelines/writing/PRINCIPLES.md` の「文書全体の読みやすさ」
  - NG dict: `guidelines/writing/NG-DICTIONARY.md` (AI 定型語 / 要根拠語 / 難読漢語 / 非日常英語)
  - Writing axis: `guidelines/writing/PRINCIPLES.md` (体言止め / 助詞省略 / 主語省略 / 1 文長 / 抽象語放置 等)
- **Check 順序**: structure gate (`文書全体の読みやすさ`) → 媒体別 / type 別差分 → 語彙・局所。文や単語を修正する前に、見出しと各段落の主張だけを読む。問題が複数 section にまたがる場合は、意味を保ったまま構成変更や文書分割まで行ってから局所的な書き直しへ進む。
- **Severity 判定**: 事実の創作、意味・時制・因果関係の変化、宛先を誤る表現、必須形式の破損だけを Critical とする。文長・段落長・語尾・構造の偏りは、前後を読んで支障がある場合だけ Warning とする。
- **Rewrite 発動条件**: 確認済みの Critical、または実際に読み違えの原因になる Warning がある場合だけ書き換える。Warning の件数や lint の比率だけでは発動しない。
- **Loop 上限**: rewrite → re-check を max 2 loops まで実施する。2 loop 後も残存すれば user に残存違反と loop limit reason (info gap / decision pending 等) を提示して続行確認する。
- **File 永続化時**: `Read` で書き出した内容を再取得し、`Edit` で該当箇所のみ差分修正する (全文書き直ししない)。
- **Chat / stdin draft 時**: 生成 text を直接 self-check し、rewrite 済 draft を出力に反映する。
- **意味保持**: rewrite 前後の事実・時制・因果関係・主体・評価を比較する。入力にない数値・事例・理由を補わない。
- **出力**: user が文体説明を求めていない限り、check 結果や loop の工程を本文へ含めない。最終稿と必要な注意点だけを返す。

## Override 規約

各 command が override してよいのは「**check 対象の doc 種別**」1 点のみ (例: design doc / Notion doc / PRD / issue comment / commit message / PR body)。判定条件・loop 上限・check 対象 canonical (NG dict / PRINCIPLES) の変更はこの file で一元管理し、command 側で上書きしない。

## 関連

- `guidelines/writing/PRINCIPLES.md` — 文体規範 canonical
- `guidelines/writing/NG-DICTIONARY.md` — 語彙 block canonical
- `skills/comprehensive-review/SKILL.md` — writing axis NG table (PRINCIPLES 実装補助)
