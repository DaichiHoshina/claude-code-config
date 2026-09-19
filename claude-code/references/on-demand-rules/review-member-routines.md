# review-member 差分外 routine 詳細手順

`skills/review-member/SKILL.md` の Step 2.5「差分外 routine」表にある「配置の慣習」「変更波及」の具体手順。該当 routine を実行するときのみ Read する。

## 配置の慣習の手順 (新 package / 新 dir / 新 type を作成した場合)

- 上位 dir を `ls` し、同種の置き場所と type 名の prefix を数件見て合わせる
- BC 横断の分布だけで済ませず、同じ BC 配下の既存 dir 階層とも `find` で並べる (既存 handler が 1 階層、新規 package が 2 階層のように同 BC 内で深さが割れていれば指摘する)
- 同じ dir 配下の package の file 構成 (`errors.go` / `export_test.go` / `input.go` 等) も `ls` で比べ、無い file があれば理由を問う
- `pkg/config` への env 追加は infra 側の登録手順を PR body で確かめる
- 論理削除 / nullable / 固定値による状態表現のような保存方式の新設は lens 9 の手順で同種 column の先例 migration を開く

## 変更波及の手順

- 共有 default / 共通定数 / props の呼び出し元を grep で数える
- 既存 query / method の条件を限定した変更 (WHERE 条件の追加等) は、呼び出し元ごとに除外した分を別途取る必要がないかを見る
- 波及を挙げるときは同 package に別の判定入口 (helper 関数) が無いかも grep し、呼び出し側で helper を使えば共有物を変更せずに済むかを代案として添える
