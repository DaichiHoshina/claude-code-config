# /explain の読者レベル別 1 枚 HTML 図解 (手動運用 template)

複雑な実装を読む前の準備運動として、対象読者のレベルを制約にした「たとえ + 図解 + 対応表」の 1 枚 HTML を作る手順。読者レベルを下げる制約が構造抽出を強制し、対応表で実 code に戻れる (出典: Zenn「AIに『中学生でもわかるように1枚のHTMLで図解して』が、複雑なコードを読む前の最良の準備運動かも」)。

`/explain` の flag にはまだしない (2026-09-05 決定)。この file の prompt を `/explain` の後に手で入力して 2-3 回運用し、対応表の抜けや手戻りが実測できてから `--audience` flag に昇格させるか判断する。運用結果は末尾の「実測ログ」に追記する。

## 使い方 (3 手)

1. `/explain <対象>` を通常どおり実行し、対象特定 (diff / PR / file / symbol) と Serena 読解を済ませる
2. 下の prompt を level を指定して入力する。`<対象>` は `/explain` で宣言した対象をそのまま記載する
3. 生成された HTML を scratchpad に Bash heredoc で作成し、`open <path>` で開く。local-docs には作成しない (保持したいときだけ user が `/ld guide` で起こす)

## level 表

| level | 読者像 | 本文の形 | 図解 | 対応表 |
|---|---|---|---|---|
| `low` | 小学生まで | 物語 / 絵本形式。専門用語 0 | 登場人物と流れの絵 1-2 点 | 「登場人物 → class / method」の最小表 |
| `mid` (既定) | 中学生 | たとえ + 手順の分解 | timeline / 比較表など 3 点以上 | たとえ ↔ package / struct / method の 3 段表 |
| `high` | 高校〜大学 | 理由付き技術仕様。用語はそのまま | 呼び出し経路図 + data flow | code 引用付きの対応表 |

## prompt (入力する本文)

```
直前の /explain で読んだ <対象> の仕組みを、<level の読者像> でもわかるように 1 枚の HTML に図解も入れて作ってください。

- 出力は self-contained な HTML 1 file (inline CSS + inline SVG、外部 URL / CDN / font 参照なし)
- 冒頭に「たとえは近似で、正確な挙動は末尾の対応表にある code を読む」の注記を入れる
- 本文は <level 表の「本文の形」>
- 図解は <level 表の「図解」>
- 末尾に対応表を置く: <level 表の「対応表」>。対応表の symbol は Serena find_symbol で見つかる実在のものだけを記載する
- 用語はフロント / シンフロ / ネイティブ側 / admin / BE の呼び分けに従う
- 実データ (ID / 名前 / 金額) は書かず架空の値にする
- file は scratchpad 配下に <対象名>-<level>.html として Bash heredoc で書き、open で開く
```

## 出来上がりの確認 (4 点)

- たとえ / 図解 (level 表の点数) / 対応表 / 近似注記 の 4 要素がある
- 対応表の symbol を 1 つずつ `find_symbol` で取得して全部実在する (この確認を省くと「分かった気」で終わる)
- `grep -c 'https\?://' <file>` が 0 (外部参照なし)
- `low` では本文に code 識別子が無く、対応表にだけある

## 注意点

- たとえは近似で、実装の正確な挙動を保証しない。対応表を経由して code に戻ってから読解を始める
- `high` を隣接チームや修正担当者に共有するときは、架空データへの置換を確かめてから渡す (`rules/public-repo-private-data-block.md`)
- scratchpad は session 終了で消える。保持するなら user が `/ld guide` で local-docs へ起こす

## 実測ログ

flag 昇格の判断材料。1 回ごとに「日付 / 対象 / level / model / 対応表の抜け件数 / 手戻り」を 1 行で追加する。

| 日付 | 対象 | level | model | 対応表の抜け | 手戻り |
|---|---|---|---|---|---|
| 2026-09-05 | <product-repo> の景品抽選経路 (API → usecase → writer) | mid | Fable 5.1 | 0 (16 行、未読の 8 symbol を grep で確認) | 0 (heredoc 1 回で書けた。SVG 3 点は座標手置きで、これ以上増やすと乱れやすい) |
