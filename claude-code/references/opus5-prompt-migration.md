# Opus 5 移行に向けた prompt 設計変更点

## 目的

Opus 5 に切り替えるときに、現行 `<repo-root>/claude-code/` の prompt / rule / config のどこを再検討するかをまとめた作業指示書になる。今 (2026-07-27) は Opus 5 の access を organization 側で未取得のため、切替は保留している。

## 出典

- 記事: 「Opus 5 では今までのプロンプトが逆効果に。『検証して』を消して『簡潔に』と書くべし」
- 著者: little_hands (松岡@Loglass)
- 公開日: 2026-07-26
- URL: https://zenn.dev/little_hand_s/articles/72646a09f49d2a

## 記事要約

Opus 5 は前 model より強力だが、旧 model 向けの prompt 習慣が逆効果になる。方針を「追加する」から「削る」に切り替える必要がある。

### 主張

1. **応答は放っておくと長くなる**。effort は思考量を制御するだけで応答の長さには影響しない。明示的に「簡潔に」と指示する必要がある。
2. **検証指示は削る**。公式 guide が「検証指示を削除せよ」と明言している。Opus 5 は自動で検証・再確認を実行するため、明示指示は過剰検証で token 無駄になる。
3. **effort の起点を下げる**。Opus 4.8 は coding で `xhigh` 開始だったが、Opus 5 は `high` 開始で `low` / `medium` を積極活用する。
4. **subagent 委譲の方向が逆転する**。Opus 4.8 は委譲が少ないので促す指示が必要だったが、Opus 5 は委譲が多すぎるので抑制指示を要する。

### 追加すべき指示例 (記事の原文)

> 応答は焦点を限定し、手短かつ簡潔に。免責事項は短く、本題に注力。

### 削除すべき指示例

- 「検証して」
- 「再確認して」
- 「ダブルチェック」

## 現行 config への影響 map

現行 (Opus 4.7 稼働) で「検証を明示する」方向に振っている記述の一覧になる。Opus 5 に切り替える段階で、下記を「削るか / 条件付きに限定するか / 保持するか」を 1 件ずつ判定する。

### 検証系 (削除 or 条件付き化の検討対象)

| file | 行 | 該当記述 (要旨) | 切替時の判断 |
|---|---|---|---|
| `CLAUDE.global.md` | 128 | `## Verification before completion`。「完了」「動く」「passing」宣言前に検証 command を fresh 実行して照合する。skip 時は「未検証」と明示 | 記事推奨は削除。ただし外向き宣言 (commit / PR) 前の検証は品質担保に役立つため、trigger を (a) commit / push / PR 前だけに限定し、(b) 「実装した」宣言前の自主検証は削る案が現実的 |
| `CLAUDE.global.md` | 73 | `## Collaboration stance` の cross-check。subagent report の数値・file 変更・測定値は最低 1 つ実物と照合 | 記事は「自動で実行する」と主張。ただしこの rule は「subagent の hallucination 対策」で発火経緯が明確 (2026-06-22 `manager-hallucination.md` retrospective 起点)。保留し、Opus 5 で実測して cross-check の不一致率が高ければ削る |
| `rules/thinking-principles.md` | 8 | Section 1「事実と推測を分離する」の「実物で確かめる」全般 | 思考原則は model 非依存を明記しているため保持。ただし「確認済みの事実と推測を区別して書く」は簡潔さと両立するので追記負担が増えないよう再検討する |
| `rules/thinking-principles.md` | 9 | subagent 報告の cross-check | 上と同扱い。実測してから判断 |
| `CLAUDE.global.md` | 124 | `## Definition of Done`。7 項目の DoD。Types 0 / Tests / Lint / Security / Build / smoke test / DB path | change size で scale する記述があるので、Opus 5 でも trigger 側は保持する。宣言強制の文言だけ緩めるか検討 |

### 簡潔さ系 (追加検討)

| file | 行 | 現状 | 切替時の判断 |
|---|---|---|---|
| `guidelines/writing/PRINCIPLES.md` | `## 冗長の禁止` (`rules/plain-jp.md` から移設)。「1 応答の目安は結論 1-3 文 + 根拠数文」 | 既に簡潔指示が入っている。記事の「応答は焦点を限定し簡潔に、免責事項は短く」を反映するなら、本 section 末尾に 1 行「免責 / 前置きは削る」を追記する程度で十分 |
| `CLAUDE.global.md` | 3 | 文体規範の canonical は `guidelines/writing/PRINCIPLES.md` (on-demand、2026-08-06 に auto-load rule を廃止) | PRINCIPLES.md 側で対応すれば top には不要 |

### effort 系 (起点を下げる)

| file | 行 | 現状 | 切替時の書き換え |
|---|---|---|---|
| `references/model-selection.md` | 19 | 「日常は `high`、設計判断は `xhigh` を振る」 | Opus 5 用に「日常は `medium`、設計判断は `high`、`low` を積極活用」に更新 |
| `references/model-selection.md` | 68-75 | effort table と Fable 5 は `high` default の注記 | Opus 5 行を追記する。「Opus 5 は `medium` default で開始、coding も `high` 起点」 |
| `commands/memory-save.md` 他 | frontmatter | 個別 command で `effort: low` / `medium` を pin 済 | 変更不要。既に低 effort 前提の設計だ |

### subagent 委譲系 (抑制指示の追加検討)

| file | 行 | 現状 | 切替時の判断 |
|---|---|---|---|
| `CLAUDE.global.md` | 40-50 | Auto-Delegation 表。N=1 は inline、N=2+ は agent 並列 | 現行は N=1 inline を明記しており抑制側に寄っている。変更不要 |
| `CLAUDE.global.md` | 60 | 「破壊的変更 / migration / security 修正は developer-agent → reviewer-agent + `/lint-test` の 1 round loop」 | Opus 5 が自主的に委譲するなら、条件を明示する trigger 表記のまま維持する (放任ではなく明示 rule が必要だ) |
| `CLAUDE.global.md` | 33 | `general-purpose` agent 全面禁止 | 変更不要。抑制方向で既に厳しい |

## 切替時の作業手順 (order)

1. `/model` で Opus 5 が利用可能な状態か確認 (現状 `not available`)
2. 上表のうち「切替時の判断」が「削除」の項目だけ先に反映する
3. 「実測してから判断」の項目は 1 か月 (CLAUDE.md `## Compounding Engineering` の infra 変更 rule と整合) 運用してから採否を決める
4. `references/model-selection.md` の effort 起点を書き換える
5. `guidelines/writing/PRINCIPLES.md` の簡潔さ section に免責短縮の 1 行を追記するか検討

## 現時点で変更しない理由

- Opus 5 access が未取得で実測できない
- 記事 1 本のみを根拠に既存 rule を書き換えると、CLAUDE.md `## Compounding Engineering` の「automation infra は 1 か月以上実測してから」に反する
- 現行の検証系 rule は個別の retrospective (例: 2026-06-22 `manager-hallucination.md`) や実測 log (jp-fix hook の block 実績等) を根拠に組んであるため、model 変更だけで一斉に削除するのは危険が伴う

## 関連 file

- `CLAUDE.global.md` (top-level 指示)
- `guidelines/writing/PRINCIPLES.md` (簡潔さ規範)
- `rules/thinking-principles.md` (思考原則、model 非依存)
- `references/model-selection.md` (model / effort 選定)
- `references/compounding-engineering-cycle.md` (実測起点の変更 rule)
