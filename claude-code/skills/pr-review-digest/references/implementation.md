# pr-review-digest 実装詳細

SKILL.md の Flow (Step 0-8) の実行コード。SKILL 本体は各 Step の目的だけ持ち、実装はここを Read して使う。

## Mode 判定 (先頭で必ず行う)

引数 `--chat` の有無で mode を分岐する。chat mode は Step 1 / 5A / 6 (HTML 側) / 7 / 8 を skip し、代わりに Step 5B と Step 6-chat を実行する。

```bash
MODE=html
for arg in "$@"; do
  [ "$arg" = "--chat" ] && MODE=chat
done
```

## Step 0. config load

```bash
CONF=~/.claude/references-private/pr-review-digest.env
[ -f "$CONF" ] || { echo "config not found: $CONF"; exit 1; }
set -a; source "$CONF"; set +a
```

## Step 1. snapshot (HTML mode 限定)

chat mode ではこの Step 全体を skip する。実行前に現行 file を archive dir にコピーする (rollback 用)。snapshot は直近 2 世代だけ残し、古い分はコピー直後に削除する (rollback は直近分で足り、日次実行で無制限に積むと 1 か月で 30 件超になる。2026-08-31 に 33 件を手動掃除した再発防止)。

```bash
# glob は eval 経由で展開する (source した env 変数の * は自動展開されない)
DOC=$(eval ls -t "$TARGET_DOC_GLOB" 2>/dev/null | head -1)
[ -n "$DOC" ] && [ -f "$DOC" ] || { echo "no doc matched: $TARGET_DOC_GLOB"; exit 1; }
ARCHIVE=$(dirname "$DOC")/_archive
mkdir -p "$ARCHIVE"
cp "$DOC" "$ARCHIVE/$(basename "$DOC" .html)-$(date +%Y%m%d-%H%M%S).html"
ls -t "$ARCHIVE" | tail -n +3 | while read -r old; do rm "$ARCHIVE/$old"; done
```

## Step 2. since 時刻を決める

`<!-- since-cursor: YYYY-MM-DDTHH:MM:SSZ -->` (前回実行の正確な UTC 時刻) を最優先で使う。**date-only の `data-window` + 1 日方式は使わない**。旧方式は JST 朝の cron 実行で cutoff が未来日に飛ぶ不具合があった。同日再実行でも同じ理由で cutoff が未来に飛んでいた (2026-07-30 実踏)。

**HTML mode**:

```bash
CURSOR=$(grep -oE '<!-- since-cursor: [0-9TZ:-]+ -->' "$DOC" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z')
if [ -n "$CURSOR" ]; then
  SINCE_ISO="$CURSOR"
  # PR 検索の net は 1 日広げる (GitHub search の日付粒度対策)
  SINCE=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" -v-1d "$CURSOR" +%Y-%m-%d)
else
  # 旧形式 doc の fallback。+1 日は付けない (右辺の日付をそのまま UTC 0時として使い、取りこぼし分もまとめて取得する)
  # TODO: 追跡中の全 doc に since-cursor が行き渡ったらこの分岐は削除する
  SINCE=$(grep -oE 'data-window: [0-9-]+/[0-9-]+' "$DOC" | awk -F/ '{print $2}')
  SINCE_ISO=$(date -j -f "%Y-%m-%d" "$SINCE" +%Y-%m-%dT00:00:00Z)
fi
TODAY=$(date +%Y-%m-%d)
```

**chat mode**:

```bash
CHAT_CURSOR=~/.claude/references-private/pr-review-digest-chat-cursor.txt
mkdir -p "$(dirname "$CHAT_CURSOR")"
if [ -f "$CHAT_CURSOR" ]; then
  SINCE_ISO=$(cat "$CHAT_CURSOR")
  SINCE=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" -v-1d "$SINCE_ISO" +%Y-%m-%d)
else
  # 初回起動: 7 日前を default にする
  SINCE_ISO=$(date -u -v-7d +%Y-%m-%dT00:00:00Z)
  SINCE=$(date -u -v-7d +%Y-%m-%d)
fi
TODAY=$(date +%Y-%m-%d)
```

## Step 3. 対象 PR 抽出

```bash
gh api "search/issues?q=repo:${TARGET_REPO}+is:pr+author:${AUTHOR}+updated:>=$SINCE&per_page=100" \
  | jq -r '.items[].number' | sort -n > /tmp/pr_review_digest_prs.txt
```

## Step 4. 各 PR の新規コメント fetch (並列)

各 PR について 3 endpoint を叩き、bot / 本人除外 + since での限定 + 挨拶単独除外を jq で適用する。

```bash
EXCLUDE_USERS="coderabbitai|Copilot|copilot-pull-request-reviewer"
EXCLUDE_USERS="${EXCLUDE_USERS}|github-actions|dependabot|datadog-official|${AUTHOR}"
# REST の bot login は末尾に [bot] が付く (例: coderabbitai[bot])
# GraphQL では付かないので、この regex を GraphQL 経路へ流用しない (author.__typename で判定する)
# suffix の有無を問わず一致させる
JQ_EXCLUDE_USER="select(.user.login | test(\"^(${EXCLUDE_USERS})(\\\\[bot\\\\])?\$\") | not)"
JQ_EXCLUDE_FILLER='select((.body // "") | test("^(LGTM!?|!\\[LGTM\\]\\(https?://[^)]+\\)|コメントしました！?|レビューしました！?)\\s*$") | not)'

for pr in $(cat /tmp/pr_review_digest_prs.txt); do
  {
    gh api "repos/${TARGET_REPO}/pulls/${pr}/comments?per_page=100" --paginate 2>/dev/null \
      | jq --arg s "$SINCE_ISO" "[.[] | select(.created_at >= \$s) | $JQ_EXCLUDE_USER | $JQ_EXCLUDE_FILLER | {kind:\"inline\", user:.user.login, path:.path, line:.line, created_at:.created_at, body:.body}]" > /tmp/pr_${pr}_inline.json &
    gh api "repos/${TARGET_REPO}/issues/${pr}/comments?per_page=100" --paginate 2>/dev/null \
      | jq --arg s "$SINCE_ISO" "[.[] | select(.created_at >= \$s) | $JQ_EXCLUDE_USER | $JQ_EXCLUDE_FILLER | {kind:\"thread\", user:.user.login, created_at:.created_at, body:.body}]" > /tmp/pr_${pr}_thread.json &
    gh api "repos/${TARGET_REPO}/pulls/${pr}/reviews?per_page=100" --paginate 2>/dev/null \
      | jq --arg s "$SINCE_ISO" "[.[] | select(.submitted_at >= \$s) | select((.body // \"\") != \"\") | $JQ_EXCLUDE_USER | $JQ_EXCLUDE_FILLER | {kind:\"summary\", user:.user.login, state:.state, created_at:.submitted_at, body:.body}]" > /tmp/pr_${pr}_summary.json &
    wait
  }
done
```

## Step 5A. 追記位置決定と Edit (HTML mode 限定)

chat mode ではこの Step 全体を skip する (Step 5B を参照)。各 PR block を `<summary><strong>PR #${pr}</strong>` で検索し、`</details>` の 1 行手前に li を追加する。追加 li の HTML 雛形:

- **inline**: `<li><strong>${user}</strong> <code>${path}:${line}</code> <span class="ts">${date}</span><br>${body_html}</li>`
- **thread**: `<li><strong>${user}</strong> <span class="ts">${date}</span><br>${body_html}</li>`
- **summary APPROVED**: `<li><span class="lbl lbl-ok">APPROVED</span> <strong>${user}</strong> <span class="ts">${date}</span><br>${body_html}</li>`
- **summary COMMENTED**: `<li><span class="lbl lbl-note">COMMENTED</span> <strong>${user}</strong> <span class="ts">${date}</span><br>${body_html}</li>`

該当 PR block が存在しない場合:

- 「人間レビュアーコメント 0 件の PR」list にあれば削除して、新 details block を追加する
- 無ければ「新規 PR」として `<h2>` "PR 別コメント一覧" 直下の `<p>...</p>` の直後に details block を挿入する

body HTML 変換: 改行 `\n` → `<br>`。URL / user @ mention はテキスト保持。markdown 記法は無変換。

**単純追記原則**: 既存 li の再配置・件数再計算・block 順序変更はしない。既存 h4 セクション (`<h4>inline review comments</h4>`) が該当 PR に無ければ、新 h4 + ul を `</details>` 直前に差し込む。

## Step 5B. chat markdown 出力 (chat mode 限定)

HTML mode ではこの Step 全体を skip する。各 PR の inline / thread / summary を統合して chat に markdown で出す。

```bash
TOTAL=0
{
  for pr in $(cat /tmp/pr_review_digest_prs.txt); do
    inline_count=$(jq 'length' /tmp/pr_${pr}_inline.json)
    thread_count=$(jq 'length' /tmp/pr_${pr}_thread.json)
    summary_count=$(jq 'length' /tmp/pr_${pr}_summary.json)
    pr_total=$((inline_count + thread_count + summary_count))
    [ "$pr_total" -eq 0 ] && continue
    TOTAL=$((TOTAL + pr_total))
    title=$(gh api "repos/${TARGET_REPO}/pulls/${pr}" 2>/dev/null | jq -r '.title')
    echo ""
    echo "## PR #${pr} ${title}"
    jq -r '.[] | "- **" + .user + "** `" + .path + ":" + (.line|tostring) + "` (" + .created_at + ")\n  " + (.body | gsub("\n"; "\n  "))' /tmp/pr_${pr}_inline.json
    jq -r '.[] | "- **" + .user + "** (thread, " + .created_at + ")\n  " + (.body | gsub("\n"; "\n  "))' /tmp/pr_${pr}_thread.json
    jq -r '.[] | "- **" + .user + "** [" + .state + "] (summary, " + .created_at + ")\n  " + (.body | gsub("\n"; "\n  "))' /tmp/pr_${pr}_summary.json
  done
} > /tmp/pr_review_digest_chat.md

if [ "$TOTAL" -eq 0 ]; then
  echo "新着なし (since=${SINCE_ISO})"
else
  cat /tmp/pr_review_digest_chat.md
  echo ""
  echo "since=${SINCE_ISO}、次回は cursor 更新済 (計 ${TOTAL} 件)"
fi
```

## Step 6. metadata 更新

**HTML mode**:

- `<!-- updated: -->` を今日の日付に
- `<!-- data-window: -->` の右辺を今日の日付に
- リード文の「データ取得日は YYYY-MM-DD。」を今日の日付に
- `<!-- since-cursor: -->` を今回の実行時刻 (`date -u +%Y-%m-%dT%H:%M:%SZ`) に更新する。既存 doc にタグが無ければ `<!-- updated: -->` の直後に新規挿入する

**chat mode**:

- 独立 cursor file を今回時刻で上書きする

```bash
date -u +%Y-%m-%dT%H:%M:%SZ > "$CHAT_CURSOR"
```

## Step 7. CSS/JS path check (HTML mode 限定)

chat mode ではこの Step 全体を skip する。追記後、shared CSS/JS の相対 path が有効か grep で確認する。修正はしない (書き換えると他 doc への波及リスク、警告のみ出す)。

## Step 8. build (HTML mode 限定)

chat mode ではこの Step 全体を skip する。

```bash
cd "$(dirname "$DOC")/../.."
/usr/bin/env -i HOME="$HOME" PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" node _index/build.mjs
```

exit 0 で done。fail 時は Step 1 の snapshot から差し替えて調査する。
