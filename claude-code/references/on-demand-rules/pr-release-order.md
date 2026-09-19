# PR 分割は「merge 順 = 本番反映順」で 1 PR ずつ検証する

`main merge = 本番リリース` を前提にする repo では、大機能を複数 PR に割るとき、**各 PR を「merge する順」に並べ、その PR が merge された瞬間の本番状態が安全か**を 1 つずつ言語化して確かめる。依存グラフだけ書いて満足しない。

## 原則

- PR を **merge 順に一列化**する (依存表でなく時系列)
- 各 PR で「**merge 直後の本番状態**」を 1 文で言う
  - 例: 「API が生えるが画面がないので誰も叩かない」
  - 例: 「画面が表示されて初めて user が操作可能になる」
- 3 パターンで安全判定する:
  - **BE 先行 (画面なし)** = 本番に反映しても見えない、無害。好きな順で merge 可
  - **FE 公開** = ここで初めて user に見える。前提の BE が全部 merge 済か / 中途半端な機能が露出しないかを確認
  - **Contract (旧削除・破壊的変更)** = 公開・安定後に最後。新旧並走 → 旧落ち切り確認 → 削除
- 段階リリースの定石: **Expand-Migrate-Contract** = BE 全部先行 → FE をリリース日に一斉公開 → 旧削除を最後

## 分割のタイミング (base-first merge を default にする)

大機能は「丸ごと実装 → 事後に layer 別 stacked PR へ分割」ではなく、**着手時に単独 merge 可能な最小単位へ縦分解し、1 単位ずつ完成 → merge → 次を main から切る** (base-first)。chain 深さは 2 段以下を上限とする。

- 深い stacked chain は main を取り込む連鎖 merge の原因になる (実測: 3 ヶ月で merge commit が全 commit の 45%、chain 6-7 段)
- 未使用 code の main 混入は Go では無害 (未参照 package)。user 露出の最終段のみ feature flag で隠す (`feature-flag-deploy-order.md`)
- repo 側にある事後 layer 分割 command (split-pr-by-layer 等) は「大きく作ってしまった後」の救済用として使い、新規開発の default 経路にしない (repo 側 file は変更せずこの rule 側で運用を規定する)
- 実測 data・完成条件・レビュアー提案文: `docs/reports/dev-workflow-base-first-improvement-20260810.md`

## Why

機能単位や層単位で割っただけだと「途中まで merge した状態」が考慮から外れる。admin だけ先に公開して user 側がない場合、当選者が操作できない中途半端な画面が本番に露出する事故になる。merge は不可逆 (本番反映) なので、反映される順の検証が必須。

## 防御 flag の活用

`has_size` のような「立てなければ無影響」の flag があれば、admin FE を user FE より先出しできる (運営が立てるまで user 無影響)。

## 破壊的 API 変更の前提確認

破壊的変更を含む場合、対象画面が **WebView (サーバー配信) か native app か**を必ずコードで裏取りする。

- **WebView**: FE/BE 同日リリースで旧 client 残留がなく、新旧両対応が不要になり設計が大幅に単純化する
- **Native**: 旧バージョン落ち切りまで両対応を要する

判定を怠ると mobile 合意ブロッカーを不要に抱える。

## How to apply

- 大機能起票時に「merge 順一列化 → 各 PR の merge 直後本番状態 1 文」を DesignDoc / issue に明記する
- BE / FE / Contract を混在させる PR は分割候補として検討する
- Contract PR は本番安定確認後にのみ merge する

## 適用範囲

- 全 repo (main merge = 本番反映 を前提にする repo)
- 3 PR 以上に割る機能リリース時
- 破壊的 API 変更を含むリリース時

## 参照

- `references/on-demand-rules/feature-flag-deploy-order.md`
- `references/on-demand-rules/dead-code-first-pr-chain.md` (既存挙動を変えない PR を先に main へ入れる chain の雛形)
- `references/on-demand-rules/chain-pr-main-merge.md`
- CLAUDE.md `## Definition of Done`
