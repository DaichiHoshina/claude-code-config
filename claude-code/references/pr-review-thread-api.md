# PR review thread の操作手順 (GitHub API 共通)

`/self-review-fix` と `review-reply-draft` skill が共有する GitHub review thread の取得 / 返信 / resolve の手順。両者は対象 thread と post の可否が違うだけで、API 経路と判定 rule は同じ。`pr-review-digest` skill は REST 専用なので bot 判定の節だけ関係する。

## thread の取得 (GraphQL)

`gh api graphql` で `pullRequest.reviewThreads` を取得する。取得 field は `id` / `isResolved` / `path` / `line` と `comments.nodes.{id, author.login, author.__typename, body, createdAt, url}`。

```bash
gh api graphql -f query='
query($pr: Int!) {
  repository(owner: "<owner>", name: "<repo>") {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        nodes {
          id isResolved path line
          comments(first: 30) { nodes { id author { login __typename } body createdAt url } }
        }
      }
    }
  }
}' -F pr=<番号> --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)'
```

呼び出し元ごとの filter:

| 呼び出し元 | 対象 thread |
|---|---|
| `/self-review-fix` (default) | `comments[0].author.login` が自分 (自分が起点の thread) |
| `review-reply-draft` / `/self-review-fix --others` | 最後の comment の author が自分以外かつ bot 以外 |

resolve 済み thread は fetch の時点で除外される。owner / repo / 自分の login は現 repo と `gh api user` から導出し、定義 file に固有名詞を記載しない。

## bot 判定

GraphQL では **`author.__typename == "Bot"`** で判定する。`login` の `[bot]` suffix は REST だけに付き、GraphQL の `author.login` には付かない (同じ coderabbitai が REST では `coderabbitai[bot]`、GraphQL では `coderabbitai` になる)。直近 30 PR の review comment 148 件のうち 109 件が `Bot` 型で、`login` が `[bot]` で終わるものは 0 件だった。suffix 判定だと bot を 1 件も除外できない。

REST 専用の skill (`pr-review-digest`) は suffix の有無を問わない regex で除外してよいが、その regex を GraphQL 側に流用しない。

## 返信の post (inline reply)

`gh api repos/<owner>/<repo>/pulls/<pr>/comments/<comment_id>/replies` を使う。`gh pr comment` は issue comment で経路が違い、thread に対応しない。post するのは `/self-review-fix` default mode だけで、`review-reply-draft` と `--others` は draft を出すだけで post しない。

返信の文体は draft 前に `<repo-root>/memory/feedback_review_reply_style.md` を毎回 Read して従う (記憶でなく現物を読む。2026-08-20 指摘 → 08-21 再違反の実績)。

## resolve の案内 (自動 resolve はしない)

resolve は user が内容を確認してから手で実行する (user 決定 2026-08-01)。定義 file から `resolveReviewThread` mutation を実行せず、次の template を chat に出す。複数 thread は 1 block にまとめ、thread id は取得 query の `id` から取る。

```
以下の thread は <reply を post した / 返信不要で resolve のみ未対応>。resolve は手動でどうぞ。

gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "<thread-id>"}) { thread { id isResolved } } }'
```

## 参照

- `commands/self-review-fix.md` — 自分起点 thread の処理 (fix commit + reply post)
- `skills/review-reply-draft/SKILL.md` — 他者 comment への返信 draft (post しない)
- `skills/pr-review-digest/SKILL.md` — REST での他者 comment 集約
