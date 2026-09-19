---
allowed-tools: Read, Glob, Grep, Bash, Edit
argument-hint: "<doc paths...> [--review]"
description: "jp-quality hook と同じ辞書検査を既存文書へ後追い適用して修正する。「NG 語検査して」「jp-quality 当てて」で起動"
---

# /jp-lint — jp-quality 検査の既存文書への後追い適用

hook (pre-tool-use / stop) は書き込み時の live 経路で、既に書かれた文書には働かない。この command は同じ辞書 (`guidelines/writing/NG-DICTIONARY.md`) と判定関数 (`lib/jp-quality/`) を `~/.claude/scripts/jp-quality-lint.sh` 経由で既存 file へ当て、hit を文脈判定してから最小 diff で修正する。判定 logic の SoT は `lib/jp-quality/` で、この command は工程のみを扱う。

## 実行 mode

inline 固定 (iteration 前提)。対象が repo 管理下なら所在 repo の worktree / gate 規約に従う。

## 引数

| 入力 | 解決 |
|---|---|
| doc paths | 対象 (glob 可)。省略時は直前の会話で扱った doc を対象にする |
| `--review` | findings 報告のみで修正しない (Flow 3-4 を skip)。「検査だけ」「見てほしい」の発話はこの mode で受ける |

## Flow

1. **実測**: 下の 2 つから採用して実行し、file / category ごとの hit を chat に出す。hit なしの file は「該当なし」で閉じ、以降触らない

   ```bash
   # 既定 (hook と同じ key 集合)
   ~/.claude/scripts/jp-quality-lint.sh <files>

   # 荒い比喩語 (死んだ / 死ぬ / 残骸 / ゴミ / 腐る / 食われる) と
   # 無理やりの短縮 (「確認済」で切る / 「要確認」/ 連用形否定) も見る
   ~/.claude/scripts/jp-quality-lint.sh --strict <files>
   ```

   **この 2 類型を検査するなら `--strict` が必須で、付け忘れると既定 mode は `hit なし` を返して検出しない**。hook が口語 chat への誤爆を避けて自動 block しない類型なので、当たる経路は `--strict` だけだ (canonical: `guidelines/writing/PRINCIPLES.md` 「自然な話し言葉の日本語」 / 「文章生成の不変条件」)
2. **文脈判定**: hit ごとに前後を Read して adopt / 見送りを決め、見送りには理由を 1 行付ける (例: code 識別子・固有名詞への部分一致 / 引用文 / 別概念を意図した用語)。件数は hit の列挙と一致させる
3. **修正**: adopt 分だけ Edit で最小 diff にする。置換先は script 出力の置換候補 (辞書 「置換候補」) を優先し、無い語は category の修正方針 (削除 / 平易化 / 短縮) に従う。文書に無い事実・数値・理由を書き足さない
4. **gate**: script を再実行し、block 残 hit が見送り分のみであることを確認する。warn (断定語 / 英語jargon / 構造) は文脈判定で見送った残置を許す
5. **報告**: category 別に「adopt N / 見送り N + 理由 / 該当なし」だけ返す。修正工程の列挙や触らなかった箇所の説明はしない

## Forbidden

- NG 語 list のこの command への複製 (辞書 SoT は NG-DICTIONARY.md、既存 key rename 禁止)
- 文脈判定を省略した hit の一括機械置換 (部分一致誤爆を書き換えない)
- warn 系 hit の無差別書き換え (断定語・jargon は文意が変わりうる。迷ったら保持する)
- 検査 scope 外の一般推敲の混入 (意味・構成の推敲は `/jp-fix` へ)

## 関連

- `/jp-fix` — 推敲 5 観点 (意味・構成)。辞書の機械検査はこの command が担う
- `/norm-apply` — 規範差分の checklist retrofit (辞書以外の writing 規範を当てるとき)
- `hooks/pre-tool-use.sh` / `hooks/stop.sh` — live 経路 (発火仕様の canonical)
