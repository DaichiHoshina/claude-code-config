#!/usr/bin/env bash
# local-docs-context.sh — local-docs の authoring 規範を 1 call でまとめて出す
#
# skill `local-docs` の Prerequisites は CLAUDE.md / STRUCTURE.md / writing 規範を
# section 単位で 6 回前後 Read していた。同じ内容を 1 回の実行で出して往復を畳む。
#
# usage:
#   local-docs-context.sh --root              # 置き場の絶対 path だけ出す
#   local-docs-context.sh                     # 規範一式
#   local-docs-context.sh --type decision     # type 固有の規範を足す
#
# mode (new / update / reformat) は 2026-09-21 に廃止した。
# 理由: 現在の置き場 (~/local-docs) は規約を README.html 1 本で持つため、
# mode で出し分ける対象が無く、出力が header 1 行しか変わらなかった。
# CLAUDE.md 方式の置き場へ戻すなら、出し分けの要否をそこで再検討する。
set -uo pipefail

AI_TOOLS_GUIDELINES="${AI_TOOLS_GUIDELINES:-$HOME/.claude/guidelines/writing}"

# 置き場は ~/local-docs に固定する (user 決定 2026-09-21)。
# 探索をやめた理由: 同名の dir が複数あると解決先が機体や探索順で変わる。
# LOCAL_DOCS_ROOT は test と一時的な差し替え用の override として残す。
resolve_root() {
  local root="${LOCAL_DOCS_ROOT:-$HOME/local-docs}"
  [ -d "$root" ] || return 1
  printf '%s\n' "$root"
}

# section <file> <見出し文字列>: "## 見出し" から次の同レベル見出しの手前までを出す
section() {
  local file="$1" head="$2"
  [ -f "$file" ] || { echo "(missing: $file)"; return; }
  awk -v want="$head" '
    function level(s) { match(s, /^#+/); return RLENGTH }
    $0 ~ /^#+ / {
      if (f && level($0) <= wantlvl) exit
      title = $0; sub(/^#+ /, "", title)
      if (!f && index(title, want) == 1) { f = 1; wantlvl = level($0); print "### [" FILENAME_SHORT "] " title; next }
    }
    f { print }
  ' FILENAME_SHORT="$(basename "$file")" "$file"
  echo
}

usage() {
  echo "usage: local-docs-context.sh [--root] [--type <type>]" >&2
  exit 1
}

root_only=""
type_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root_only=1; shift ;;
    --type) type_arg="${2:-}"; [ -n "$type_arg" ] || usage; shift 2 ;;
    *) usage ;;
  esac
done

ROOT=$(resolve_root) || { echo "error: local-docs が見つからない (LOCAL_DOCS_ROOT で指定する)" >&2; exit 1; }

if [ -n "$root_only" ]; then
  printf '%s\n' "$ROOT"
  exit 0
fi

echo "# local-docs authoring context${type_arg:+ (type: $type_arg)}"
echo "# root: $ROOT"
echo

# --- 置き場側 canonical ---
# md の CLAUDE.md / STRUCTURE.md を持つ置き場と、README.html 1 本で規約を持つ置き場がある。
if [ -f "$ROOT/CLAUDE.md" ]; then
  section "$ROOT/CLAUDE.md" "Templates"
  section "$ROOT/CLAUDE.md" "Title Rules"
  section "$ROOT/CLAUDE.md" "Metadata"
  section "$ROOT/STRUCTURE.md" "置き場判断フロー"
  section "$ROOT/CLAUDE.md" "コンポーネント活用マップ"
  section "$ROOT/STRUCTURE.md" "html 形式"
elif [ -f "$ROOT/README.html" ]; then
  echo "### [README.html] 置き場の規約"
  # style / script を落としてから tag を外し、本文だけ出す (規約は README 1 本が正本)
  sed -e '/<style/,/<\/style>/d' -e '/<script/,/<\/script>/d' "$ROOT/README.html" \
    | sed -e 's/<[^>]*>//g' \
    | sed -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e 's/&amp;/\&/g' \
    | grep -v '^[[:space:]]*$'
  echo
else
  echo "### 置き場の規約が見つからない ($ROOT に CLAUDE.md も README.html も無い)"
  echo
fi

# --- ai-tools 側 writing 規範 ---
section "$AI_TOOLS_GUIDELINES/PRINCIPLES.md" "文書全体の読みやすさ"
section "$AI_TOOLS_GUIDELINES/long-form-doc.md" "構造ゲート適用"
section "$AI_TOOLS_GUIDELINES/long-form-doc.md" "品質検証タイミング"

case "$type_arg" in
  postmortem|report|plan|decision)
    section "$AI_TOOLS_GUIDELINES/long-form-doc.md" "type 別の本文品質"
    ;;
esac
[ "$type_arg" = "decision" ] && section "$AI_TOOLS_GUIDELINES/long-form-doc.md" "decision 専用 hard checklist"

exit 0
