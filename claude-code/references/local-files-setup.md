# local file setup (この設定が期待する機体固有 file)

ai-tools は一部を公開する可能性があるため、**社内固有名 / 個人 path / repo 固有の構造**を repo に置かない。それらは `~/.claude/references-private/` 配下の local file に格納し、repo 側は読み取り経路だけを含める。

そのため **新しい機体では下記 file を置くまで、該当機能が無言で動作しない**。どれも「不在なら no-op か skip」になる設計で、error にはならない。移行直後に必ず点検する。

## 一覧

| file | 有効になる機能 | 不在時の挙動 | env var |
|---|---|---|---|
| `references-private/social-hit-terms.txt` | 社内固有名を外向き text で block (cwd が ai-tools 配下のときだけ) | block しない | `SOCIAL_HIT_TERM_FILE` |
| `references-private/private-name-list.txt` | 個人名 / 会社名を block (cwd 無条件) | block しない | `PRIVATE_TERM_FILE` |
| `references-private/extra-permissions.json` | 個人環境固有の permission を settings へ追加する | template の permission だけになる | `CLAUDE_EXTRA_PERMISSIONS_FILE` |
| `references-private/repo-rules.json` | repo rule の置き場と repo profile (build command / branch 命名 等) | rule 読込と `--get` を skip | `CLAUDE_REPO_RULES_MANIFEST` |
| `references-private/large-repo-paths.txt` | 連続 inline 編集で delegation を促す対象の判定 | 判定ごと no-op | `CLAUDE_LARGE_REPO_PATHS_FILE` |
| `references-private/review-member/` (`detail.md` + `lens-history.md`) | `review-member` の 33 lens 照合 | lens 照合を skip して汎用 self-review だけ | `CLAUDE_REVIEW_MEMBER_DATA_DIR` |

`references-private` は `sync.sh` の `SYNC_ITEMS` に無いので、同期しても消えない。

## 点検

```bash
for f in social-hit-terms.txt private-name-list.txt extra-permissions.json \
         repo-rules.json large-repo-paths.txt review-member/detail.md; do
  [ -e "$HOME/.claude/references-private/$f" ] && echo "ok   $f" || echo "MISS $f"
done
```

`MISS` が表示された機能は現在有効になっていない。中身の書式は各 file の先頭コメントと下記の canonical を見る。

## 書式の canonical

- term 2 系統 (統合してはいけない理由を含む): `rules/public-repo-private-data-block.md`
- repo profile と rule の当たり判定、large-repo list: `references/on-demand-rules/repo-rules-manifest.md`
- permission overlay: `scripts/settings-validator.sh` の `merge_local_permissions`
- lens data: `skills/review-member/SKILL.md`

## 置くときの原則

- **AI は read のみ**。追記は user が行う (term list と permission は特に)
- repo 側へ literal を戻さない。戻すと公開時に露出してしまう
- 新しい repo 固有値が必要なときは、command 本文に書かず `repo-rules.json` の key を増やして `resolve-repo-rules.sh --get <key>` で取得する
