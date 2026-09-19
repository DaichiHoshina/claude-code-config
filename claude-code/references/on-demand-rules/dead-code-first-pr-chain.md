# 既存挙動を変えない PR を先に main へ入れる chain (dead code first)

大機能を複数 PR に割るとき、**呼び出し元のない実装を「既存挙動が変わらない PR」として先に main へ merge し、挙動を変える PR を最後の 1〜2 本に限定する**。review 待ちが発生するのはその 1〜2 本だけになり、release branch にためる必要がなくなる。

出所: 2026-09-06 に <product-repo> の直近 90 日 (merged PR 1,732 件) を計測し、上位 3 名の chain (POS 連携 約 30 本、購入モジュール移行 約 45 本、画像検索同期 8 本) を抽象化した。上位は 1 PR の中央値が 133〜209 行、merge 待ち中央値 0.3〜1.6 日で、release branch にためた側 (中央値 326 行、待ち 18.5 日) と対照的だった。

## 原則 5 つ

1. **dead code を先に merge する**: 呼び出し元がない code (model / repository / usecase / 公開関数) は既存挙動を変えないので、title に「既存挙動を変えない」印 (repo の慣習では `[確認不要]` 等) を付けて即 merge する。配線 PR は最後に別で出す
2. **内側から外側へ 1 層 1 PR**: 依存の向きに沿って、interface と入出力型 → ドメインモデル → repository / gateway 実装 → usecase → 公開関数と DI → API adapter / worker / batch → 画面、の順で積む。各 PR は直前の PR だけに依存する
3. **切替は flag に閉じ込め、3 本に分ける**: 「配線 (flag OFF)」「統合テストを新経路に差し替え」「有効化 (flag を true にする 1 行、QA 完了の証拠を title か本文に)」を別 PR にする。flag は code 定数型 (Go の const / map) を既定にし、infra (terraform 等) を変更する環境変数型は使わない
4. **I/F 変更だけの PR を先に切る**: 引数追加や rename は呼び出し側を全部触るが挙動は変えない。単独 PR にして機械的に確認できるようにし、中身の変更を後続に分ける
5. **準備と後始末は本流に含めない**: migration だけ、lint 抑制だけ、log level だけ、置き換え前の code と flag の削除だけ、不具合修正だけ、を各 1 本にする。削除 PR は有効化後 2〜4 週間の安定を確認してから出し、有効化 PR の本文に撤去予定日を記載する

## chain の雛形 (10 段)

| 順 | 内容 | 既存挙動 | review 待ち |
|---|---|---|---|
| 1 | migration / 設定 / interface 定義 (数十行) | 変わらない | 発生しない |
| 2 | ドメインモデルと単体テスト | 変わらない | 発生しない |
| 3 | repository / gateway / query 実装 | 変わらない | 発生しない |
| 4 | usecase 実装と入出力 | 変わらない | 発生しない |
| 5 | 公開関数と DI 配線 (呼び出し元なし) | 変わらない | 発生しない |
| 6 | 配線 PR (flag OFF または dead code のまま) | 変わらない | 発生しない |
| 7 | 統合テストを新経路に差し替え | 変わらない | 発生しない |
| 8 | 有効化 (flag を true にする 1 行) | 変わる | 発生する |
| 9 | 画面 (表示条件が flag か商品ごとの対象化 flag で閉じていれば「変わらない」) | 場合による | 場合による |
| 10 | 置き換え前の code と flag の削除 | 変わらない | 発生しない |

- 1 PR は 300 行以下 (test 抜き)。超えるなら I/F 変更かテストを先に切る
- base は常に main。前の PR に依存するときだけ前の branch を base にし、merge されたら main に付け替える (release branch にためない)。`pr-release-order.md` の base-first と同じで、chain の深さは 2 段以下
- 「既存挙動が変わる PR」は chain 全体で 2 本以下 (有効化と、flag で隠せない画面) を目安にする。3 本以上になるなら flag の置き場所を見直す

## PR 本文で伝える 3 点

節構成は repo の PR template に従う (canonical: `guidelines/writing/pr-description.md` 「節構成は repo の PR template に従う」)。この chain 設計で特に必要なのは次の 3 点で、それぞれ template の該当節へ記載する。

| 伝えたいこと | 記載例 | 配置先 |
|---|---|---|
| この PR で確認してほしいこと | `- [ ] writer の SQL と test。呼び出し元はまだ無い` | `## レビュー観点` |
| 本番の挙動が変わるか | `- アプリの挙動は変わらない (呼び出し元がまだ無い)` / `- <flag 名> を ON にしたときだけ変わる` | `## 影響範囲` |
| 連続する PR の何本目か | `8 本のうち 3 本目` | `## 背景` か `## 備考` |

## 出す前の checklist

- [ ] この PR は 1 層だけか。2 層入っているなら分ける
- [ ] 300 行以下か。超えるなら I/F 変更かテストを先に切る
- [ ] 既存挙動が変わらないか。変わらないなら印を付け、変わるなら flag で守れないか
- [ ] 本文の節が repo の PR template と揃っているか。レビュー観点・影響範囲・PR の順番を記載したか (label に「chain」を記載しない)
- [ ] base は main か。前 PR 依存なら merge 後に付け替える予定を本文に記載したか
- [ ] 生成物 (mock、swagger 等) を同じ PR に含めたか (別 PR にすると CI で失敗する)

## 縦切りとの関係

`commands/spec-plan.md` Step 3 は repo の慣習を測ってから縦切りか層切りかを決める。慣習が「層切り + main へ直接 merge + 既存挙動不変の印」ならこの rule の雛形を既定にし、層切りの回数制限 (1 機能 1 回) は適用しない。制限が守ろうとしていた「接続されない途中 PR が発生する」危険は、dead code が main に入っても挙動が変わらないことと、削除 PR の期限で受ける。stacked (前 PR を base にしたまま並ぶ) のときだけ従来の制限を使う。

## 適用範囲

- main merge = 本番反映の repo で、3 PR 以上に割る機能
- flag の機構 (code 定数型) が repo にあるか、1 file で足せる repo

## 参照

- `references/on-demand-rules/pr-release-order.md` (merge 順 = 本番反映順、base-first)
- `references/on-demand-rules/feature-flag-deploy-order.md` (flag ON と deploy の 2 コンポーネント)
- `guidelines/writing/stacked-pr-chain.md` (stacked にせざるを得ないときの運用)
