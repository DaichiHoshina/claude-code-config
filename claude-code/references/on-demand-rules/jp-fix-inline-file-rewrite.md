# jp-fix は現在の会話内で file を書き換える

`jp-fix` skill (`skills/jp-fix/SKILL.md`) は fork せず、現在の会話内で動く。自然文の依頼に含まれる file path や pasted text をそのまま対象として受け取り、Read / Grep / Edit / Write で確認と修正を行う。

file 対象の write / rewrite は、`commands/jp-fix.md` の Dynamic Load by Type 表でも parent の直接更新として定義されている。slash command と自然文からの skill 起動で同じ責務を担う。

fork context は、自然文から自動起動されたときに対象 file を受け取れず、空のタスクとして終了することがある。呼び出し元が対象なしの終了後に処理を引き取ると、直前の会話履歴を手掛かりに古い修正観点を繰り返す。

## 対応

- skill を現在の会話内で読み込み、current user request の対象を最優先する
- 対象 file を通読し、意味・事実・論理のつながりを保って直接更新する
- 最終応答は修正の有無と文書全体に影響する要点だけにする。個々の修正、未変更箇所、成功した検証を列挙しない

## 経緯

`[[2026-08-06]]` の自然文による読みやすさ修正で、fork した skill が「タスクがない」と対象なしで終わった。親は同一 session の過去出力を引き継ぎ、語尾検索を再開した。対象の受け渡しを安定させるため、skill を inline 実行へ変更した。
