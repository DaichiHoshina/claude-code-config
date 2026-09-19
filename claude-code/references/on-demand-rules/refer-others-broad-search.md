# 「他を参考」発話時は project 全体を横断調査する

user が「他の実装を参考にして」「参考例を探して」「他ではどうしてる」等を発話したら、対象 project 全体を横断調査してから提案する。1-2 file の pinpoint Read や単発 grep で打ち切ると、局所事例の過度な一般化の原因になり、実装が実態と合わなくなる。

## 発火 trigger 語

以下の語 (完全一致でなく substring 判定) が user 入力に含まれたら、Discovery Routing の broad-search 分岐に強制的に入る。

- 「他を参考」/ 「他の実装を参考」/ 「他の例」
- 「参考例」/ 「参考にして」/ 「他ではどう」
- 「既存 pattern」/ 「類似コード」/ 「同じような処理」
- 「他の場所ではどう書いてる」/ 「repo 内の書き方」

## 動作

trigger 発火時は下記を必ず守る。

1. **broad search を Explore agent または explore-agent で 3+ query 並列 fan-out**する。単発 Bash grep / find で終わらせない (CLAUDE.md `Discovery / Investigation Routing` の broad search 分岐に合流)。explore-agent の各 prompt には explore contract (canonical: `agents/explore-agent.md` 「Prompt contract」、fan-out では `run_id` / `expected_count` を共有し `scope_id` を分ける) を先頭に記載する。欠落は hook が block する
2. 検索 scope は project 全体 (現 repo の root 起点)。単一 dir に限定する場合は user に確認を取る
3. 検索観点を最低 3 系統に分けて並列化する。例: (a) 命名 pattern / (b) 呼び出し pattern / (c) test 記述 pattern
4. 出力は「単一事例の引用」ではなく「複数事例から抽出した pattern と例外」の形で提示する

## 例外 (broad search を skip して良い場合)

- user が「1 file だけ見て」「この function だけ参考に」等 scope を明示的に限定した場合はそれに従う
- 対象 pattern が repo に 1 箇所しかないと事前に判明している場合 (単一 file 命名の central config 等)
- user が「他 = 別 repo」を意図している場合 (context7 skill 経由の外部 doc 参照に切替)

## Anti-pattern (即 reject)

- trigger 発火に気付かず 1 file の Read で「他ではこう書いています」と答える
- 単発 `grep -r <keyword>` のヒット 1 件を「他の例」として提示する
- 「他を参考」に対して自分の記憶の pattern を answer する (実物確認を skip する)

## 参照

- CLAUDE.md `## Discovery / Investigation Routing (anti-overuse)` (broad search 分岐の判定表)
- `rules/thinking-principles.md` Section 1 事実と推測を分離する (記憶で答えない)
- `agents/explore-agent.md` (broad search の主体)
