---
allowed-tools: Bash, Read, Write, Edit, Agent
name: review-reply-draft
description: 自分の PR に付いた未返信 review comment を集め、code 根拠付きの返信 draft と未 commit の修正案を作る。投稿と commit は user が行う。「未返信コメント取得」「返信 draft 作って」「review 返信案」で起動。
---

# review-reply-draft

自分が author の PR に付いた他者 review comment のうち、未返信のものを集めて返信 draft を作る skill。実 code を根拠にして draft を組み立て、chat 出力と memory 保存までを担当する。投稿は行わない。返信に code 修正が伴う場合は、対象 branch の worktree に未 commit の修正として置き、diff を提示して user の commit 判断に委ねる。

## 対象決定

- 引数に PR 番号があればその PR を対象にする。無指定なら現 branch に対応する PR を対象にする
- 「chain 全体」「app 側全部」のような指定は `gh pr list --author "@me" --state open` で対象 PR 群を列挙する
- 複数 PR が対象になる場合、PR 番号の昇順で 1 PR ずつ直列に処理する。PR 着手前に `[PR <番号>] 着手 (<進捗>/<総数>)` の 1 行を chat に出す。並列化はしない (memory 書き込み・fact-check round が PR 間で競合するため)

## Step 1. 未返信 thread の抽出

GraphQL で reviewThreads を取得し、次の 2 条件で限定する。

- `isResolved == false`
- thread 最後の comment の author が自分以外

「了解です 👍」のように会話が完結している thread は「resolve 操作のみ残 (user 手動)」に分類し、返信の対象外にする (一覧化は Step 1.5 で行う)。bot の comment は対象外とする。

取得 query の骨格、bot 判定 (`author.__typename == "Bot"`。`login` の `[bot]` suffix は GraphQL に付かない)、resolve 案内の template は `references/pr-review-thread-api.md` が canonical で、Step 1 の前に Read する。

## Step 1.5. resolve-only thread の一覧案内

Step 1 で「resolve 操作のみ残」に分類した thread は、返信の対象外にするだけで終わらせず、reference の resolve template で chat に一覧表示する (`/self-review-fix` Step 5 と同じ形式)。複数 thread は 1 block にまとめ、thread id は Step 1 query の `id` field から取る。

## Step 2. memory 保存

repo 用 memory dir に `pr<番号>-unreplied-review-comments.md` を作成し (既存 file があれば追記)、index (MEMORY.md) へ 1 行追加する。質問の全文と、回答に必要な論点の分解を記載する。

## Step 3. 回答方針の fact-check とセルフレビュー

draft の主張ごとに次の 1〜3 を確認する。反証や未確認事項が見つかった場合だけ再確認し、round 数を満たすための反復はしない。

1. **worktree と PR tip の一致確認**: 読解する worktree の対象 file が PR branch tip と diff ゼロであることを確かめてから読む。一致しないまま読むと、古い code を根拠にした誤答になる
2. **別名実装の探索**: 「他に呼び出し / 処理はない」と主張する前に、関数名 1 個の grep で断定しない。同じ挙動を別名で行う実装 (別関数 / transaction 内の一括処理 / raw SQL) が存在し得るため、テーブル名や操作対象の単位でも grep する。この skill を作る前の session で、関数名だけの grep により transaction 内の削除処理を見落とし、投稿済みの返信を訂正する事態が起きた
3. **他者の目での検証**: 挙動の主張に file:line の根拠を付け、reviewer-agent に検証させる。指摘を draft に反映してから次の round に進む

## Step 4. draft 作成と日本語 / jargon チェック

- **基調は「謙虚なエンジニアの丁寧な返事」とする** (user 明示 2026-08-05)。感謝・同意・謝罪は実際の判断に合う場合だけ書き、反論や維持判断で非や妥当性を作らない。結論と理由を率直に伝える
- **draft を書き始める前に `<repo-root>/memory/feedback_review_reply_style.md` を必ず Read して従う** (2026-08-20 指摘 → 08-21 再違反の実績があるため、記憶でなく毎回現物を読む)
- **文体は user 本人の手書き返信に合わせる**。repo memory に文体の傾向があればそれを優先する。memory がなく、語調の判断が内容を左右する場合だけ、過去 reply を少数参照する。取得数・文体指標を目的にした計測や、返信ごとの機械的な型の再現は行わない
- 返信は丁寧なです・ます体を基調にし、過去 reply にある「！」、`mm`、絵文字、定型句は必要な場合だけ使う。commit hash は文中に埋めず、必要な場合だけ別行に bare short hash か commit URL で置く。常体の「対応: 〜した (hash)。」形式は /self-review-fix の AI 返信専用で、本人投稿用 draft には使わない
- 実装用語は読み手基準で開く (例: selection → サイズ選択レコード)。文は字数を揃えず、主語・因果・条件を読み違える箇所で分ける
- 出力前に `guidelines/writing/PRINCIPLES.md` の「文章生成の不変条件」と日本語品質を確認する。英語 jargon と矢印チェーンを見直し、元の事実・時制・判断・本人の語調を変えない。確認工程や文体指標は draft や完了報告に書かない
- 投稿はしない。chat に全文を出力し、memory の同 file にも draft を追記する
- 末尾 marker "by claude code" は付けない (marker を付けるのは /self-review-fix の返信だけ)

## Step 5. code 修正が伴う場合 (未 commit で置く)

comment 文言の修正のように、返信とセットで code を修正する場合の手順:

- 対象 PR の branch を格納した worktree で修正を適用する (場所は `git worktree list` で確認する)
- **commit しない**。`git diff` を提示し、commit / push は user の判断に委ねる
- 返信 draft には修正する旨と修正内容の 1 行要約を入れる。commit hash は user の commit 後に差し替える
- **comment の書き換えで応じる前に、その処理自体が必要かを先に確かめる**。指摘された comment が説明している処理が現行経路で到達しない (no-op / 防御用) なら、書き換えでなく削除を第一候補として提示する。到達しない分岐の説明はどう書いても読み手に伝わらず、往復だけが増える。実際に、同じ comment を 3 度書き換えた末に user 判断で revert し、最終的に処理ごと削除した事例がある (canonical: `rules/thinking-principles.md` Section 6)

## Step 6. 訂正 flow

draft や投稿済みの文面に誤りが見つかった場合:

1. 訂正 draft を作る。何が誤りで、正しくは何かを先頭に記載する
2. 同じ主張を書き出した外部反映先 (issue comment / DesignDoc / memory) を列挙し、全部を追跡訂正する
3. 見落としの原因を 1 行で memory に記録する

## Step 7. follow-up: commit → push → hash 反映の再出力

user が「コミットプッシュして返信例を出力」「ハッシュ入りで再度出力」等と指示したら、次を 1 依頼で最後まで実行する (途中で止めて追加依頼を待たない。2026-08 の実測で、この連結を user が毎回手で依頼する同型 prompt が週 20 件超あった):

1. Step 5 で置いた未 commit 修正を thread 単位の粒度で commit し push する (1 thread 対応 = 1 commit 基準、無関係な差分は含めない)。commit / push はこの明示指示があるときだけ行う
2. push 済み commit の short hash を取り、該当 draft の hash 行を差し替える。**記載する前に `git branch -r --contains <hash>` で remote branch に含まれることを確かめる**。確認できない hash は draft に記載しない (未 push の hash や amend / force-push で消えた hash は GitHub がリンク化せず、reviewer に「リンクになっていない」と指摘される※)
3. 全未返信 thread の draft を全件再出力する (一部だけの再掲は不可)。draft 本文は地の文で置き、blockquote で囲まない
4. 再出力前に Step 4 の文体確認 (feedback_review_reply_style.md + NG 語) を再適用し、memory の同 file も hash 入りに更新する

※ 実際に投稿済み返信の hash が local にも remote にも存在せず、指摘を受けた実例がある。

## 注意

- この skill は GitHub への投稿を行わない。comment の投稿や PATCH は、user の明示指示があるときだけ skill の外で行う
- `/self-review-fix --others` の委譲先でもある。委譲で入った場合も投稿と commit はしない (呼び出し元の default mode は commit + 自動 post だが、その挙動を引き継がない)
- skill 本体に社名 / repo 名 / 個人 login を記載しない。owner / repo / login は実行時に現 repo と `gh api user` から導出する
