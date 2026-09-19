#!/usr/bin/env bash
# memory-save-helper.sh — /memory-save command の補助 script
#
# 機能:
#   1. resolve-dir         — save 先 dir を解決して echo (default: <repo-root>/memory)
#   1b. resolve-permanent-dir — 恒久 file 本文を stdin で受け、Tier 判定で保存先を echo
#       (social-hit term 含む → references-private 配下、無 → ai-tools/memory)
#   2. list-today          — 同日 work-context-YYYYMMDD-*.md を改行区切りで列挙
#   3. resolve-name        — name collision 回避 (-2/-3 suffix 付与)
#   4. update-index        — MEMORY.md 先頭に `- YYYY-MM-DD [desc](file.md) — hook` を追記 (重複 dedup)
#   5. append-clear-line   — /memory-save clear 用、MEMORY.md に `- YYYY-MM-DD [clear] <topic> — <summary> (commit: <hash>)` を prepend (dedup なし)
#   6. extract-issue-key   — 現 branch 名から issue key (`PROJ-123` / `#123` / `issue-123`) を抽出して echo、無ければ空
#   7. find-topic-match    — 同日 work-context-*-<topic>.md を exact suffix match で filter (issue key prefix は無視)
#   8. prepare / 9. finalize — 前段 metadata の一括返却と index 更新 + pbcopy 統合で往復を減らす
#   10. codex-save-note     — Codex の更新 note を ad_hoc ingestion queue へ安全に保存
#   11. reindex            — index に含まれていない恒久 file を検出、--apply で「## 未分類」章へ追記
#
# 注意: 本 script は AI 経由の Write/Edit ばらつきを排除するための deterministic helper。
#       memory file 本体の write は /memory-save command (AI 側) が担当する
set -euo pipefail

# save 先 dir 解決ルール (canonical: commands/memory-save.md 「Flow」 step 1):
#   1. $MEMORY_SAVE_DIR が set されていればそれを使う (override、test 用)
#   2. cwd の repo origin が <ghq-root>/github.com/<org>/ 配下で <org-root>/memory/ が存在すれば
#      <org-root>/memory/<repo> (org 作業 memory、2026-07-16 分離)。worktree も origin URL で同判定
#   3. それ以外は ${HOME}/ai-tools/memory (3 tool 共有 SoT、汎用知見)
_resolve_memory_dir() {
  if [ -n "${MEMORY_SAVE_DIR:-}" ]; then
    printf '%s\n' "$MEMORY_SAVE_DIR"
    return 0
  fi
  local origin org repo org_mem
  origin=$(git config --get remote.origin.url 2>/dev/null || true)
  if [ -n "$origin" ]; then
    org=$(printf '%s' "$origin" | sed -E 's#^(git@[^:]+:|ssh://[^/]+/|https?://[^/]+/)##; s#\.git$##' | cut -d/ -f1)
    repo=$(printf '%s' "$origin" | sed -E 's#^(git@[^:]+:|ssh://[^/]+/|https?://[^/]+/)##; s#\.git$##' | cut -d/ -f2)
    org_mem="${HOME}/ghq/github.com/${org}/memory"
    if [ -n "$org" ] && [ -n "$repo" ] && [ -d "$org_mem" ]; then
      mkdir -p "${org_mem}/${repo}"
      printf '%s\n' "${org_mem}/${repo}"
      return 0
    fi
  fi
  printf '%s\n' "${HOME}/ai-tools/memory"
}

# private 保存先 (Tier B = project 固有知識、on-demand read の raw 保管)。
# canonical: references/memory-relocation-pattern.md / 2026-07-09 memory-consolidation。
# $MEMORY_PRIVATE_DIR override 可 (test 用)
_resolve_private_dir() {
  if [ -n "${MEMORY_PRIVATE_DIR:-}" ]; then
    printf '%s\n' "$MEMORY_PRIVATE_DIR"
    return 0
  fi
  printf '%s\n' "${HOME}/.claude/references-private/org-knowledge"
}

# social-hit term の実体 file。ai-tools は公開されうるので term literal は repo に置かず
# local file に格納する。$SOCIAL_HIT_TERM_FILE / $MEMORY_SOCIAL_HIT_RULE (旧名、test 用) で override 可
_social_hit_rule_file() {
  printf '%s\n' "${MEMORY_SOCIAL_HIT_RULE:-${SOCIAL_HIT_TERM_FILE:-${HOME}/.claude/references-private/social-hit-terms.txt}}"
}

# term file から 1 行 1 語で読む (# 行・空行は skip)。
# public-repo-guard.sh:_load_social_hit_terms と同じ書式を読む
_memory_social_hit_terms() {
  local rule; rule=$(_social_hit_rule_file)
  [ -f "$rule" ] || return 0
  grep -v '^[[:space:]]*#' "$rule" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' || true
}

# 恒久 file (feedback/project) の保存先を Tier 判定で解決する。
# 引数: file 本文 (heredoc / cat で渡す) を stdin から読む。
# social-hit term を 1 つでも含めば private dir (Tier B)、含まなければ ai-tools/memory (Tier A) を echo。
# canonical: commands/memory-save.md 「恒久ナレッジ化 + promote」 (Tier B routing)
cmd_resolve_permanent_dir() {
  local content; content=$(cat)
  local ai_dir; ai_dir=$(_resolve_memory_dir)
  # org 作業 memory (git 管理外の private dir) が dest なら social-hit を private dir へ移す必要はない。
  # path pattern で限定し、MEMORY_SAVE_DIR override (test 等) では従来どおり移動要否を判定する
  case "$ai_dir" in
    "${HOME}"/ghq/github.com/*/memory/*)
      printf '%s\n' "$ai_dir"
      return 0
      ;;
  esac
  local term
  while IFS= read -r term; do
    [ -z "$term" ] && continue
    if printf '%s' "$content" | grep -qiF -- "$term"; then
      _resolve_private_dir
      return 0
    fi
  done < <(_memory_social_hit_terms)
  printf '%s\n' "$ai_dir"
}

MEMORY_DIR=$(_resolve_memory_dir)
INDEX_FILE="${MEMORY_DIR}/MEMORY.md"

_today() { date +%Y%m%d; }
_today_iso() { date +%Y-%m-%d; }

cmd_resolve_dir() {
  printf '%s\n' "$MEMORY_DIR"
}

cmd_list_today() {
  local today; today=$(_today)
  [ -d "$MEMORY_DIR" ] || { return 0; }
  find "$MEMORY_DIR" -maxdepth 1 -name "work-context-${today}-*.md" -type f 2>/dev/null | sort
}

cmd_resolve_name() {
  local base="${1:?base name required}"
  local candidate="$base" n=2
  while [ -e "${MEMORY_DIR}/${candidate}.md" ]; do
    candidate="${base}-${n}"
    n=$((n + 1))
  done
  printf '%s\n' "$candidate"
}

cmd_update_index() {
  local name="${1:?name required}" desc="${2:?description required}" hook="${3:-}"
  mkdir -p "$MEMORY_DIR"
  local file="${name}.md" date_iso; date_iso=$(_today_iso)
  local line
  if [ -n "$hook" ]; then
    line="- \`${date_iso}\` [${desc}](${file}) — ${hook}"
  else
    line="- \`${date_iso}\` [${desc}](${file})"
  fi

  if [ ! -f "$INDEX_FILE" ]; then
    printf '%s\n' "$line" > "$INDEX_FILE"
    return 0
  fi

  # 既存 entry に同 file への link あれば差し替え (dedup)
  if grep -Fq "](${file})" "$INDEX_FILE"; then
    # 旧行削除 → 先頭に新行
    local tmp; tmp=$(mktemp)
    grep -Fv "](${file})" "$INDEX_FILE" > "$tmp" || true
    { printf '%s\n' "$line"; cat "$tmp"; } > "$INDEX_FILE"
    rm -f "$tmp"
  else
    # 先頭に prepend
    local tmp; tmp=$(mktemp)
    { printf '%s\n' "$line"; cat "$INDEX_FILE"; } > "$tmp"
    mv "$tmp" "$INDEX_FILE"
  fi
}

# /memory-save clear 専用: 個別 file を作らず MEMORY.md に 1 行 entry を prepend する。
# canonical: commands/memory-save.md 「Flow」 step 3
# format: - `YYYY-MM-DD` [clear] <topic> — <1 行 summary> (commit: <hash>)
cmd_append_clear_line() {
  local topic="${1:?topic required}" summary="${2:?summary required}" commit="${3:-}"
  mkdir -p "$MEMORY_DIR"
  local date_iso; date_iso=$(_today_iso)
  local line
  if [ -n "$commit" ]; then
    line="- \`${date_iso}\` [clear] ${topic} — ${summary} (commit: ${commit})"
  else
    line="- \`${date_iso}\` [clear] ${topic} — ${summary}"
  fi

  if [ ! -f "$INDEX_FILE" ]; then
    printf '%s\n' "$line" > "$INDEX_FILE"
    return 0
  fi

  # clear entry は dedup しない (同日複数 clear save を保持する)。先頭 prepend
  local tmp; tmp=$(mktemp)
  { printf '%s\n' "$line"; cat "$INDEX_FILE"; } > "$tmp"
  mv "$tmp" "$INDEX_FILE"

  # 肥大防止: [clear] entry は最新 CLEAR_LINE_MAX 件のみ保持する。
  # 超過分の削除は index からのみで、同 topic の work-context 個別 file は保持されるため情報損失なし
  local max="${CLEAR_LINE_MAX:-10}"
  local tmp2; tmp2=$(mktemp)
  awk -v max="$max" '/^- `[0-9]{4}-[0-9]{2}-[0-9]{2}` \[clear\] / { c++; if (c > max) next } { print }' \
    "$INDEX_FILE" > "$tmp2" && mv "$tmp2" "$INDEX_FILE"
}

# 現 branch 名から issue key を抽出。優先順:
#   1. `PROJ-123` 形式 (JIRA / Linear / Shortcut 等の大文字英字 + 数字)
#   2. `#123` 形式 (GitHub issue 参照、`123` を返す)
#   3. `issue-123` / `issue/123` 形式
# 引数で branch 名を明示可 (test 用)。省略時は `git branch --show-current`。
# 抽出できなければ空を返し exit 0。
# canonical: commands/memory-save.md 「Flow」 step 1 (issue key prefix)
cmd_extract_issue_key() {
  local branch="${1:-}"
  if [ -z "$branch" ]; then
    branch=$(git -C "$(pwd)" branch --show-current 2>/dev/null || echo "")
  fi
  [ -z "$branch" ] && return 0
  # 1. PROJ-123 (JIRA/Linear 形式) — 2 文字以上の大文字英字 + `-` + 数字
  if [[ "$branch" =~ ([A-Z][A-Z0-9]+-[0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  # 2. #123 形式
  if [[ "$branch" =~ \#([0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  # 3. issue-123 / issue/123 形式 (大文字小文字問わず)
  if [[ "$branch" =~ [Ii]ssue[-/_]([0-9]+) ]]; then
    printf 'issue-%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 0
}

# 同日 work-context-*-<topic>.md を exact suffix match で filter する。
# issue key prefix (`PROJ-123` 等) を無視して `<topic>` 部分のみで match するので、
# branch 切替後も同 topic を merge 対象として拾える。
# canonical: commands/memory-save.md 「Flow」 step 1 (merge-new 判定)
cmd_find_topic_match() {
  local topic="${1:?topic required}"
  local today; today=$(_today)
  [ -d "$MEMORY_DIR" ] || return 0
  find "$MEMORY_DIR" -maxdepth 1 -name "work-context-${today}-*-${topic}.md" -o -name "work-context-${today}-${topic}.md" 2>/dev/null | sort
}

# MEMORY.md 先頭から `[clear] <topic>` entry を 1 件返す (直近優先)。
# clear は個別 file を作らないので、reload の名指し経路が topic から直近 state を
# 拾うための source になる。見つからなければ空を返し exit 0。
# canonical: commands/reload.md 「名指し fast path」 (clear entry 経路)
cmd_find_clear_entry() {
  local topic="${1:?topic required}"
  [ -f "$INDEX_FILE" ] || return 0
  grep -m1 -F -- "[clear] ${topic} " "$INDEX_FILE" 2>/dev/null || return 0
}

# `/reload <topic>` を clipboard へコピーする。pbcopy 不在環境 (Linux/CI) は
# silent skip し exit 0 (fail させない)。実際にコピーしたコマンド文字列を stdout に返す。
# canonical: commands/memory-save.md 「Flow」 step 3
cmd_pbcopy_reload() {
  local topic="${1:?topic required}"
  local cmd="/reload ${topic}"
  if command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$cmd" | pbcopy 2>/dev/null || true
  fi
  printf '%s\n' "$cmd"
}

# /memory-save 前段の dir / worktree / issue key / merge-new 判定を 1 call に統合して往復を減らす。
# merge_target 非空なら最古 file へ merge し、空なら new_name を使う (第 2 引数は test 用の branch 明示)
cmd_prepare() {
  local topic="${1:?topic required}" branch_override="${2:-}"
  local today today_iso; today=$(_today); today_iso=$(_today_iso)
  local worktree="" branch="" toplevel
  toplevel=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$toplevel" ]; then
    branch=$(git branch --show-current 2>/dev/null || true)
    if [ -f "${toplevel}/.git" ]; then
      worktree="$toplevel"
    fi
  fi
  local issue_key; issue_key=$(cmd_extract_issue_key "$branch_override")
  local merge_target new_name=""
  merge_target=$(cmd_find_topic_match "$topic" | head -1)
  if [ -z "$merge_target" ]; then
    local base="work-context-${today}-${topic}"
    if [ -n "$issue_key" ]; then
      base="work-context-${today}-${issue_key}-${topic}"
    fi
    new_name=$(cmd_resolve_name "$base")
  fi
  printf 'dir=%s\n' "$MEMORY_DIR"
  printf 'today=%s\n' "$today"
  printf 'today_iso=%s\n' "$today_iso"
  printf 'worktree=%s\n' "$worktree"
  printf 'branch=%s\n' "$branch"
  printf 'issue_key=%s\n' "$issue_key"
  printf 'merge_target=%s\n' "$merge_target"
  printf 'new_name=%s\n' "$new_name"
}

# index 更新と pbcopy-reload を 1 call に束ねて往復を減らす。stdout は `/reload <topic>` の 1 行だ。
# mode は clear (append-clear-line 相当) と topic (update-index 相当) の 2 系統で構成する
cmd_finalize() {
  local mode="${1:?mode (clear|topic) required}"; shift
  case "$mode" in
    clear)
      local topic="${1:?topic required}" summary="${2:?summary required}" commit="${3:-}"
      cmd_append_clear_line "$topic" "$summary" "$commit"
      cmd_pbcopy_reload "$topic"
      ;;
    topic)
      local name="${1:?name required}" topic="${2:?topic required}" desc="${3:?description required}" hook="${4:-}"
      cmd_update_index "$name" "$desc" "$hook"
      cmd_pbcopy_reload "$topic"
      ;;
    *)
      printf 'unknown finalize mode: %s\n' "$mode" >&2
      return 1
      ;;
  esac
}

# Codex は共有 MEMORY.md や memory 本体を直接編集せず、ad_hoc note を ingestion queue へ置く。
# source は workspace または /tmp で作成済みの小さな Markdown file、slug は kebab-case に限定する。
# test では CODEX_MEMORY_NOTE_DIR で保存先を差し替えられる
cmd_codex_save_note() {
  local source_file="${1:?source file required}"
  local slug="${2:?kebab-case slug required}"
  if [[ ! "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    printf 'invalid slug: %s\n' "$slug" >&2
    return 2
  fi
  if [[ ! -f "$source_file" || -L "$source_file" ]]; then
    printf 'source must be a regular file: %s\n' "$source_file" >&2
    return 2
  fi

  local note_dir="${CODEX_MEMORY_NOTE_DIR:-${HOME}/.codex/memories/extensions/ad_hoc/notes}"
  mkdir -p "$note_dir"
  local timestamp target suffix=1
  timestamp=$(date '+%Y%m%d-%H%M%S')
  target="${note_dir}/${timestamp}-${slug}.md"
  while [[ -e "$target" ]]; do
    suffix=$((suffix + 1))
    target="${note_dir}/${timestamp}-${slug}-${suffix}.md"
  done
  cp "$source_file" "$target"
  printf '%s\n' "$target"
}

# frontmatter の 1 key を取り出す (--- で囲まれた先頭 block のみ見る)
_frontmatter_value() {
  local file="$1" key="$2"
  awk -v k="^${key}:[[:space:]]*" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    $0 ~ k { sub(k, ""); print; exit }
  ' "$file"
}

# index に link が無い恒久 file を検出する。--apply で「## 未分類 (reindex)」章へ追記する。
# 全再生成にしないのは、MEMORY.md 後半の章立て分類が frontmatter から導出できない
# 人手のキュレーションで、再生成すると失われるため。既存行と章立ては触らない。
# 除外: MEMORY.md 自身 / work-context (7 日で trash されるため載せると dead-link 化する)
#       compact-restore (compact の一時 file) / sleep-proposals (index を保持しない旨が index 本文に明記)
cmd_reindex() {
  local apply=0
  [ "${1:-}" = "--apply" ] && apply=1

  if [ ! -f "$INDEX_FILE" ]; then
    printf 'index が無い: %s\n' "$INDEX_FILE" >&2
    return 1
  fi

  local missing=() f base
  for f in "$MEMORY_DIR"/*.md; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    case "$base" in
      MEMORY.md|work-context-*|compact-restore-*|sleep-proposals-*) continue ;;
    esac
    grep -Fq "](${base})" "$INDEX_FILE" && continue
    missing+=("$base")
  done

  if [ ${#missing[@]} -eq 0 ]; then
    printf 'index 未登録: 0 件\n'
    return 0
  fi

  if [ "$apply" -eq 0 ]; then
    printf 'index 未登録: %d 件 (--apply で「## 未分類 (reindex)」章へ追記する)\n' "${#missing[@]}"
    printf '  %s\n' "${missing[@]}"
    return 0
  fi

  local added="" desc hook date_str
  for base in "${missing[@]}"; do
    f="${MEMORY_DIR}/${base}"
    desc=$(_frontmatter_value "$f" "description")
    [ -n "$desc" ] || desc="${base%.md}"
    hook=$(_frontmatter_value "$f" "hook")
    date_str=$(date -r "$f" +%Y-%m-%d 2>/dev/null || _today_iso)
    if [ -n "$hook" ]; then
      added+="- \`${date_str}\` [${desc}](${base}) — ${hook}"$'\n'
    else
      added+="- \`${date_str}\` [${desc}](${base})"$'\n'
    fi
  done

  local section="## 未分類 (reindex)"
  local tmp; tmp=$(mktemp)
  if grep -Fxq "$section" "$INDEX_FILE"; then
    awk -v sec="$section" -v add="$added" '{ print } $0 == sec { printf "\n%s", add }' \
      "$INDEX_FILE" > "$tmp"
  else
    { cat "$INDEX_FILE"; printf '\n%s\n\n%s' "$section" "$added"; } > "$tmp"
  fi
  mv "$tmp" "$INDEX_FILE"
  printf 'index へ %d 件追記した (章: %s)\n' "${#missing[@]}" "$section"
}

usage() {
  sed -n '2,16p' "$0"
  exit "${1:-0}"
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    resolve-dir)   cmd_resolve_dir "$@" ;;
    resolve-permanent-dir) cmd_resolve_permanent_dir "$@" ;;
    list-today)    cmd_list_today "$@" ;;
    resolve-name)  cmd_resolve_name "$@" ;;
    update-index)  cmd_update_index "$@" ;;
    append-clear-line) cmd_append_clear_line "$@" ;;
    extract-issue-key) cmd_extract_issue_key "$@" ;;
    find-topic-match)  cmd_find_topic_match "$@" ;;
    find-clear-entry)  cmd_find_clear_entry "$@" ;;
    pbcopy-reload)     cmd_pbcopy_reload "$@" ;;
    prepare)           cmd_prepare "$@" ;;
    finalize)          cmd_finalize "$@" ;;
    codex-save-note)   cmd_codex_save_note "$@" ;;
    reindex)           cmd_reindex "$@" ;;
    -h|--help|help|"") usage 0 ;;
    *) printf 'unknown subcommand: %s\n' "$sub" >&2; usage 1 ;;
  esac
}

main "$@"
