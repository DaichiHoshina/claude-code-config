---
allowed-tools: Read, Glob, Grep, Bash, Edit, Write
argument-hint: "<doc paths...> [--norms <guideline file / 節>] [--since <days|commit>]"
description: "writing 規範を checklist 化して既存 doc 群へ実測適用する retrofit。「規範を当てて」「修正した観点で直して」で起動"
---

# /norm-apply — 規範 checklist の実測適用 (retrofit)

規範 (guidelines/writing/ ほか) の指定節を checklist 化し、既存 doc 群へ実測 → 文脈判定 → 意味保持修正 → gate の順で当てる。知識 SoT は guidelines/ で、この command は工程のみを扱う (規範本文を複製しない)。

## 実行 mode

inline 固定 (iteration 前提、CLAUDE.md Auto-Delegation table)。修正対象が repo 管理下なら所在 repo の worktree / gate 規約に従う。

## 引数解決

| 入力 | 解決 |
|---|---|
| doc paths | 適用対象 (glob 可)。省略時は直前の会話で扱った doc 群を対象にする |
| `--norms <file / 節>` | checklist の源。省略時は `git log` で guidelines/writing/ の直近変更 (--since 起点) から変更節を抽出する |
| `--since <days\|commit>` | 規範差分の起点。default 7 days |
| `--norms all` | 差分でなく規範全域 (構造ゲート / 文書セット所有 / type 別品質 / 初読者基準 / 表記) から checklist を作る fresh review |
| `--review` | findings 報告のみで修正しない (Flow 4-5 を skip)。「改善点を探して」「見直して」の発話はこの mode で受ける |

## Flow

1. **checklist 化**: 規範 file の該当節を Read し、「観点 / 検出方法 (grep pattern か目視) / 修正方針」の表を chat に出してから着手する。機械検出できない観点は「目視」と明記する
2. **実測**: 観点ごとに grep で hit 件数を出す。hit 0 の観点は「該当なし」で閉じ、以降触らない
3. **文脈判定**: hit ごとに前後の文脈を読み、adopt / 見送りを決める。見送りには理由を 1 行付ける (例: 参照網の破壊 / doc に無い事実の創作になる / 意図的な例外)。件数は対象集合の列挙と一致させる
4. **修正**: 機械置換できる観点は script 一括で行う (逐次の手書き換えによる意味変化を防ぐ)。文脈依存の箇所だけ Edit で最小 diff にする。doc に無い事実・数値・理由を書き足さない
   - **同時編集 guard**: 着手時に対象 file の mtime を控え、書込直前に再確認する。外部更新 (user の手作業での編集 / 別 session) を検出したら書き込まず、差分の状況を user へ報告して指示を待つ
5. **gate**: 対象 repo の lint (local-docs は textlint 直叩き) を通し、置換後の残 hit 0 を grep で確かめる
6. **報告**: 観点別に「adopt N 件 / 見送り N 件 + 理由 / 該当なし」だけ返す。修正工程の列挙や触らなかった箇所の説明はしない

## Forbidden

- 規範本文・NG list のこの command への複製 (窓口契約違反。checklist は毎回 guidelines から作る)
- hit 件数だけでの書き換え (文脈判定を省略しない)
- 参照網 (節番号 / anchor / 呼称) を壊す構成変更の無確認実行 → user 確認に切り替える
- checklist に無い改善の混入 (scope は指定観点のみ。一般推敲は `/jp-fix` へ)

## 関連

- `guidelines/writing/README.md` — 規範一覧 / `skills/writing-knowledge` — 種別 → file 判定
- `/jp-fix` — 推敲 5 観点での一般推敲 (規範差分でなく文章品質を見るときはこちら)
- `/jp-lint` — NG 辞書の機械検査・修正 (辞書観点は checklist を組まずこちらへ委譲する)
- `/brushup` — 定義 file 自体の自己レビュー反復 (対象が doc でなく規範側のときはこちら)
