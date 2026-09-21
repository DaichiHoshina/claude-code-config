---
allowed-tools: Read, Glob, Grep, Bash, mcp__serena__*
description: 実装内容を読み手が理解できる順に説明する (read-only)。diff / PR / file / symbol を対象に、変更の目的から呼び出し経路までを順に chat に書く
argument-hint: "[diff | PR 番号 | file path | symbol] [--level brief|normal|line] [--known <既知の仕組み>]"
---

# /explain - 実装内容の説明 (read-only)

> **Goal**: 既にある実装を、読み手 (user) が自分の言葉で説明し直せる状態にする。file の編集、外部への投稿、memory への保存はしない。

## When to use (棲み分け)

| Command | Use |
|---|---|
| `/explain` | 実装を user が理解するための説明を chat に記載する |
| `/workflow understand` | subsystem の entry / 依存 / data flow を agent 並列で構造化 map にする (機械向け) |
| `/diagnose` | error log 起点でデバッグ支援する |
| `/review` | 欠陥や改善点を指摘する |

「説明して + 対象」で発火する (`references/natural-language-triggers.md`)。対象が無い「説明して」は通常の chat 応答で答え、この command は使わない。

## Step 1: 対象の特定

| 入力 | 対象 |
|---|---|
| 無指定 | working diff。無ければ `git diff HEAD~1..HEAD` (main 上では無関係な commit を含めてしまうので、対象宣言で commit を明示する) |
| PR 番号 / URL | `gh pr view <n>` の本文 + `gh pr diff <n>`。変更が 10 file 超か 500 行超なら `gh pr diff <n> --name-only` で file 一覧を出し、範囲を 1 問で限定する |
| file path | その file 全体。1,000 行超なら公開 symbol の一覧を示して範囲を 1 問で限定する |
| symbol 名 | Serena `find_symbol` で本体を引き、`find_referencing_symbols` で呼び出し元を集める |

対象を決めたら、本文を作成する前に次の 2 つを Bash で確かめる。(1) 対象の author (`git log -1 --format=%an <commit>` / `gh pr view <n> --json author`) が user 本人なら、前提知識の段はその author が作成した仕組みを省く。(2) diff の行数 (`git diff --stat` / `gh pr diff --stat`) が 10 行未満なら `--level` の既定を `brief` にする。説明の先頭で「対象: <diff の範囲 / PR / file / symbol> (author: <名前> / <n> 行)」を 1 行宣言してから本文に入る。user の入力に判断を求める問い (「この前提で妥当か」等) が含まれていても、対象の説明を先に出し、問いへの答えは Output format の末尾「補足」に 1 段落だけ記載する。判断が主目的で説明が不要な入力なら `/deep` へ誘導してこの command は終える。

`--level` の既定は `normal` (diff 10 行未満は `brief`)。`brief` は「一言でいうと / なぜ必要か / 変更前との違い / 確認したい点」の 4 見出しに限定し、他の見出しは省く。`line` は主要 logic を逐行で追う。指定が無いときに `line` を採用しない (chat が長くなり読み手の負荷が上がる)。

## Step 2: 読む

説明に必要な範囲だけを読む。diff の周辺 code、呼び出し元と呼び出し先、関連する test を pinpoint で探す (Serena `find_symbol` / grep)。commit message と PR 本文は Why の一次資料として必ず読む。

推測で埋めない。読んで確かめられなかった点は「未確認」と明示して説明に含める (`rules/thinking-principles.md` Section 1)。

## Step 3: 説明を組み立てる

読み手が前提知識から順に理解できる順に記述する。5 軸 (What / Why / How / Impact / Caveat) を、理解のための順序に並べ替えたものが下の構成になる。

1. **一言でいうと**: この実装が何をできるようにするかを 1-2 文で書く
2. **なぜ必要か**: commit message / PR 本文 / issue から目的を記載する。記載がなければ「不明」と書き、code から読める推測は推測と明示する
3. **前提知識**: 説明を読むのに必要な既存の仕組み (関連 module / data 構造 / 外部 service) を、読み手が知らない前提で 1 つずつ短く書く。Step 1 で author が user 本人と分かった仕組みと、`--known` で既知と示された仕組みは省く
4. **どう動くか**: 入口から出口まで呼び出し経路を順に追う。各段で「どの file のどの関数が、何を受け取って何を返すか」を記載する。`normal` では関数単位、`line` では主要 logic を逐行で記載する
5. **test が保証していること**: 関連 test が assert している挙動を、test 名でなく日本語の主張として書く。test が無ければ「無い」と書く
6. **変更前との違い**: diff が対象なら、変更前の挙動と変更後の挙動を対比する。新規なら省く
7. **影響範囲と注意点**: この実装に依存するもの (呼び出し元 / test / 設定 / migration) を挙げる。読むときに誤解しやすい点もここに記載する
8. **次に読む file**: 理解を深めるために読む file を 1-3 件、理由付きで挙げる

code の引用は説明に必要な行だけを fenced code block に分離する。file 全体の再掲はしない。

## Output format (見出しを固定する)

見出しの省略と順序の入れ替えをしない (`brief` が保持する 4 見出し以外を省く場合を除く)。該当が無い段は「無い」と 1 行で書く。「設計判断への影響」「直したほうがよい箇所」のような review の見出しへ置き換えない (置き換わった時点で説明ではなく review になっている)。

```markdown
# Explain: [対象]

対象: [diff の範囲 / PR / file / symbol]

## 一言でいうと
## なぜ必要か
## 前提知識
## どう動くか
## test が保証していること
## 変更前との違い
## 影響範囲と注意点
## 次に読む file

## 確認したい点
[読み手が自分の言葉で答える問いを 1 つ]

## 補足
[user の入力に含まれていた問いへの答え。無ければ省く]
```

## Step 4: 出力と確認

- 「確認したい点」は読み手が自分の言葉で答えられるかを確かめる問いにする (例: 「この経路で validation が実行されるのはどの段でしょうか」)。user が答えたら正誤と補足を返して終える
- user が「分からない」と返した段は、その段だけを前提知識から書き直す。全体を再出力しない
- 説明の後に user が仕組みや整合性の問い (「〜と同等の制限はあるか」「〜で 2 件入らないか」「なぜ〜か」「〜で守れるか」、末尾が「?」の短い問いを含む) を返したら、`rules/thinking-principles.md` Section 8 の型で答える。条件付きの結論 / 不変条件 / 守っている仕組みと code の位置 / 成り立たなくなる順序 1 つ / 解消策 を最初の回答に入れ、初出の用語は 1 行で定義し、後から聞かれそうな問いを最大 3 つ先に答える。問いが他者 (EM / レビュワー) から来たものなら、結論 + 理由 + 措置の 3 文の返答文案を末尾に添える。1 段ずつ答えて追加の問いを待たない
- 説明は chat に記載する。保存が必要なら user の指示で `local-docs` skill に渡す

## Writing

- chat なので敬体で書く。用語は `guidelines/writing/PRINCIPLES.md` に従い、比喩や擬人化で code の動作を言い換えない
- 1 段落 1 論点。経路の各段は箇条書きで 1 段 1 bullet にする
- 「〜のはずです」で断定を避けない。読んで確かめた事実と、確かめていない推測を分けて書く

## Read-only

file 編集 / 投稿 / memory 保存をしない。説明の途中で欠陥に気づいたら「注意点」に 1 行で書くに留め、修正は `/review` や `/dev` へ委ねる。

## Next

説明の末尾に 1 行記載する: 「注意点」を記載したなら `Next: /review  (指摘を先に処理する)`、無ければ `Next: /git-push --pr  (理解できたので PR へ)`。
