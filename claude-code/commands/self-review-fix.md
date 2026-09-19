---
allowed-tools: Bash, Read, Edit, Write, Task, AskUserQuestion
argument-hint: "[PR番号|PR-URL] [--dry-run] [--no-prefix-filter] [--include-memo]"
description: 自分が PR に書いた未対応 review comment に対応する。修正 commit と How/Why 返信まで自動で行う (resolve は user 手動)
---

# /self-review-fix - 自分の PR review comment の処理

自分が PR に投稿した未 resolve の review comment を GraphQL で取得する (他者 comment は `--others` で扱う)。対応の要否を triage し、修正が必要な thread は `developer-agent` に委譲する。reply に How (何をしたか) と Why (なぜそうしたか) と commit hash を記載して post するところまでをこの command が行う。**thread の resolve は user が手動で行う**方針で、この command からは `resolveReviewThread` mutation を叩かない (user 決定 2026-08-01)。**発火 trigger**: 「私のコメントに対応して」/ 「PR コメント対応して」/ 「self review fix」/ 明示 `/self-review-fix`。

## 対象 mode (自分 / 他者)

| Mode | 対象 thread | code 修正 | 返信 |
|---|---|---|---|
| default | 自分が起点の thread (`comments[0].author=self`) | commit する | inline reply を自動 post する |
| `--others` | 他者が最後に投稿した未 resolve thread | commit しない (worktree に未 commit で置く) | 返信 draft を chat に記載するだけ |

`--others` の手順はこの command に持たず、`review-reply-draft` skill へそのまま委譲する。委譲先が修正要否の fact-check、未 commit の code 修正、返信 draft の出力までを担う。**委譲中は commit も post もしない**。他者 thread へ意図せず投稿すると取り消せないため、mode を取り違えたときの被害が default mode と桁違いに大きい。

fetch の前に、どちらの mode で実行されるかを 1 行 chat に記載する。filter は mode で反転する (default は `author=self`、`--others` は最後の comment が自分以外かつ bot 以外)。query / bot 判定 / reply API / resolve template は `references/pr-review-thread-api.md` が canonical で、Step 1 の前に Read する。

両 mode を同時に実行しない。同一 PR に両方の thread があるときは default mode を先に終わらせ、その commit を済ませてから `--others` を実行する。順序を守らないと自分 mode の commit と他者 mode の未 commit 修正が同じ worktree で混在し、user が diff 単位で commit を判断できなくなる。

## 前提 (default mode)

- 対象 PR は自分が author。他者 PR に自分が付けた comment は対象外になる (thread の owner が author の PR 上にしかない)
- 判別 signal は `isResolved=false` かつ `comments[0].author=self`。thread の最初の author が自分 = 自分が投げた comment になる。**resolve 済み thread は fetch の結果から外れる**ため、既に user が手動で resolve した thread は自動的に対応対象外になる
- 誤爆対策の prefix filter は default on (`@claude` / `[c]` / `→claude` を含む thread のみ取得する)。`--no-prefix-filter` で全 self-authored thread を対象にする
- **除外語 filter** (default on): thread の 1 通目 body に `memo` / `メモ` を含む thread は fetch から除外する。user が自分向けの memo として書いた comment を誤って対応対象にしないための guard になる。`--include-memo` で off にできる

## Flow

### Step 1: fetch (GraphQL で未対応 thread 取得)

reference の query で `pullRequest.reviewThreads` を引き、author=self かつ isResolved=false で filter する。prefix filter が on なら body に prefix 語を含む thread に限定する。除外語 filter (default on) で 1 通目 body に `memo` / `メモ` を含む thread を除外する。

thread 0 件なら「未対応 comment なし」と 1 行報告して終了する。

### Step 2: triage (thread ごとに 3 分類)

各 thread を chat に列挙し、`AskUserQuestion` で 3 択を 1 問ずつ聞く。

| 分類 | 意味 | 後続 |
|---|---|---|
| fix | 修正が必要 | Step 3 で developer-agent に委譲 |
| discuss | 議論のみで修正不要 | Step 4 で reply のみ post、Step 5 で resolve 案内 |
| skip | 対応しない | 触らず次の thread へ |

thread 1 件ずつ聞く (`minimize-questions.md` の 1 回 1 問原則)。ただし 5 件超えたら「一括で fix / 一括で discuss / 個別判定」の 3 択に集約する。

### Step 3: fix (`developer-agent` 委譲)

fix 判定した thread ごとに 1 委譲する。prompt には thread の body / path / line / 対応方針 (user が Step 2 で追記した notes があればそれも) を書き切る。**1 comment = 1 commit** で、commit message の先頭に `fix(pr-review): <thread 要約>` を置き、末尾に `Refs: <thread URL>` を記載する。

`developer-agent` の trailer (`status` / `confidence`) を読み、`status: failure` なら該当 thread を Step 4 で「対応失敗、手動対応要」の reply に切り替えて resolve せず保持する。

1 comment が複数 file 越境するなら user に確認する。選択肢は「1 commit で束ねる / thread ごとに commit 分割 / この thread は手動対応」の 3 択とする。

### Step 4: reply post

thread ごとに inline reply を post する (API 経路は reference 「返信の post」)。

reply は `guidelines/writing/PRINCIPLES.md` の「文章生成の不変条件」に従い、対応内容と理由を自然な文で書く。`How:` / `Why:` の label は強制しない。入力や diff にない理由を補わず、commit hash は必要な場合だけ別行に置く。

**返信文体**: draft 前に `<repo-root>/memory/feedback_review_reply_style.md` を Read して従う。返信は 1 本ずつ形を変えて 1〜2 文で書き、定型句 → 太字の結論 → commit hash の同じ並びを全返信で繰り返さない。

| 記号 | 使用条件 |
|---|---|
| `>` (引用) | 相手のコメントの一部にだけ答えるとき |
| 太字 | スキャンで読み取る価値のある結論だけ |
| backtick | 相手が検索して確かめられる literal だけ |

post 前確認へ出す前に、返信を並べて書き出しと構成が揃っていないか見る。

body の例:

```
<!-- self-review-fixed -->
<対応した内容と、その判断に必要な理由。>

<hash 7 桁> (fix 分類のみ)
```

先頭の HTML comment は marker として機能する。user が resolve を忘れた thread も、この marker を含む reply が付いていれば次の起動時に skip する。fix 分類のみ commit hash を記載する。discuss 分類は、修正しない判断と確認済みの理由を本文で伝える。

**post 前に user 確認**: 全 thread の reply body を 1 度にまとめて表示し、「post して良いか」を Yes/No で聞く。No なら body の直接編集を促す。

### Step 5: resolve 案内 (自動 resolve は行わない)

reply post に成功した thread ごとに、user が手動で叩ける `resolveReviewThread` GraphQL mutation を chat に表示するだけに留める。**自動 resolve は行わない** (user 決定 2026-08-01、resolve は user が内容を確認してから自分で実行する運用)。

表示 template は reference 「resolve の案内」を使い、複数 thread は 1 つの block にまとめて出す。reply post に失敗した thread や `developer-agent` fail 判定の thread は resolve 案内から除外する。

## Options

| Argument | Behavior |
|---|---|
| (none) | full pipeline (fetch → triage → fix → reply → resolve 案内) |
| `<PR番号>` / `<PR-URL>` | 対象 PR を明示。省略時は `gh pr view` で現 branch の open PR を自動検出 |
| `--dry-run` | fetch + triage + reply draft 表示まで。fix / post / resolve 案内は実行しない |
| `--others` | 他者 comment mode。`review-reply-draft` skill へ委譲し、fact-check + 未 commit の code 修正 + 返信 draft を出力する (commit も post もしない)。draft 提示後に user が「コミットプッシュして再出力」等を指示したら、同 skill Step 7 (commit → push → hash 差し替え → 全 draft 再出力) を 1 依頼で実行する |
| `--no-commit` | fix を worktree に未 commit で置き、reply は draft の chat 提示に留める (post しない)。「コミットしないで修正して」「コミットはしなくていい」の発話でも on にする。user の commit / amend 後に post 指示を受けたら Step 4 に合流し、hash を差し替えて post する |
| `--no-prefix-filter` | prefix filter を off にし、自分が author の全 unresolved thread を対象にする |
| `--include-memo` | 除外語 filter を off にし、`memo` / `メモ` を含む thread も対象にする |

## 守るべき点

- **inline thread API と issue comment API は経路が違う**。`gh pr comment` (issue comment) を使わない (canonical: `references/pr-review-thread-api.md`)
- **reply post failure 時の rollback**: post が fail しても commit は保持したまま停止する。commit の revert は user 判断だ (自動 revert しない)
- **mode の取り違えは不可逆**: `--others` の対象 thread に default mode の自動 post が実行されると取り消せない。fetch 前に mode を 1 行 chat に書き、filter 条件が mode と一致していることを確かめる
- **`developer-agent` の 1 file 越境原則**: 1 委譲 = 1 file を守る。thread が複数 file 越境するなら Step 3 で user に分割を確認する

## Failure Handling

| Situation | Behavior |
|---|---|
| `gh` auth 失効 | `gh auth login` を促して abort |
| PR 特定不可 (現 branch に PR なし、引数もなし) | user に PR 番号か URL を要求 |
| GraphQL rate limit | 5 分待って 1 回だけ retry |
| `developer-agent` fail | 該当 thread は reply で「対応失敗、手動対応要」と書き、resolve せず保持する |
| reply post fail | commit は残し、chat に手動 post 用の `gh api ...` command を表示して abort |

## Related

- `references/pr-review-thread-api.md` (query / bot 判定 / reply API / resolve template の canonical)
- `commands/post-comment.md` (単発 comment draft、この command は inline reply 専用で post-comment を呼ばない)
- `commands/review.md` 「Fix loop」 (AI 自己 review → fix loop、この command は「user が書いた comment」への対応で目的が違う)
- `skills/review-reply-draft/SKILL.md` (`--others` の委譲先。他者 comment への返信 draft と未 commit の修正案を作る)
- `skills/pr-review-digest/SKILL.md` (他者 review comment を HTML doc に集約、返信はしない)
- `references/natural-language-triggers.md` (「私のコメントに対応して」trigger の登録先)

ARGUMENTS: $ARGUMENTS
