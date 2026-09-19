# feature flag は「flag ON」と「利用側 deploy」の 2 コンポーネント

feature flag / maintenance flag / config 切替は、**「flag ON」と「利用側の deploy / 再読み込み」の 2 コンポーネントが揃って初めて有効になる**。片方だけでは機能しない。

## 原則

- flag ON だけでは有効化しない。「設定変更 + 利用側 deploy / 再読み込み」の両方を要する
- 新 middleware を含む機能リリースは「**deploy 完了 → flag ON**」順を厳守する
- 「flag ON できた」判定は 2 段で確認する: 状態確認 (Redis / DB / config store の値変化) + 実挙動確認 (実 traffic の応答変化)
- 逆順 (flag ON 後に deploy) は禁止。deploy 失敗時に flag だけ立った中間状態が本番に残り、外形挙動が変わらない中途半端な状態が長時間放置される (過去に 50 分放置の事例あり)

## flag の型で「2 コンポーネント」が 1 つになる

- **code 定数型** (Go の `const` / map に値を書き、有効化は値を true にする 1 行 PR): 有効化 = deploy なので、上の 2 コンポーネントが 1 つになり、順序事故が起きない。履歴が git に残り、QA 完了の証拠を PR 本文に書ける。切り戻しは revert PR と deploy で、rollback と同じ経路。段階リリースの既定にする
- **環境変数型** (`getEnvBool` 等で読む): 値の変更に infra 側 (ECS task definition / terraform 等) の PR と apply が必要で、deploy との順序を人が守る必要がある。deploy なしで切り替えたい理由が具体的にあるときだけ採用し、Design Doc のリリース節に理由を記載する
- どちらも撤去 PR を chain の末尾に予約する (`references/on-demand-rules/dead-code-first-pr-chain.md`)

## 同構造パターン

feature flag + 利用箇所 deploy / config 書換え + 再読み込み / DB schema 変更 + 利用 query 更新 / CDN 設定切替 + キャッシュ purge。すべて「設定変更」と「利用側 deploy / 再読み込み」を独立に扱う。

## 適用範囲

全 repo / 全 stack の feature flag / maintenance flag / config 切替 / DB schema 変更のリリース手順設計時。

## 参照

- `references/on-demand-rules/pr-release-order.md` (release 順の設計)
- CLAUDE.md `## Definition of Done`
