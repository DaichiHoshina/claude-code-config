#!/usr/bin/env bash
# local-docs-sync-assets.sh — doc の infrastructure の正本を置き場へ反映する
#
# 置き場 (~/local-docs) は git 管理外のため、失うと復元できない。対象は 3 つある。
#   assets/templates/*.html → _templates/   (type 別の skeleton)
#   assets/style.css        → _index/style.css (共有 CSS)
#   assets/index/*.mjs      → _index/        (doc を起こす / index を組む script)
#
# usage:
#   local-docs-sync-assets.sh            # 正本 → 置き場へ反映し、既存 doc の共有 CSS も更新する
#   local-docs-sync-assets.sh --check    # 差分の有無だけ返す (書き込まない。差分ありで exit 1)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS="$SCRIPT_DIR/../skills/local-docs/assets"
ROOT="${LOCAL_DOCS_ROOT:-$HOME/local-docs}"

check_only=""
[ "${1:-}" = "--check" ] && check_only=1

[ -d "$ASSETS/templates" ] || { echo "error: 正本が無い: $ASSETS/templates" >&2; exit 1; }
[ -d "$ASSETS/index" ] || { echo "error: 正本が無い: $ASSETS/index" >&2; exit 1; }
[ -d "$ROOT" ] || { echo "error: 置き場が見つからない (LOCAL_DOCS_ROOT で指定する)" >&2; exit 1; }

if [ -n "$check_only" ]; then
  rc=0
  diff -rq "$ASSETS/templates" "$ROOT/_templates" 2>&1 || rc=1
  diff -q "$ASSETS/style.css" "$ROOT/_index/style.css" 2>&1 || rc=1
  for f in "$ASSETS/index"/*.mjs; do
    diff -q "$f" "$ROOT/_index/$(basename "$f")" 2>&1 || rc=1
  done
  if [ "$rc" -ne 0 ]; then echo "差分あり"; exit 1; fi
  echo "一致"
  exit 0
fi

mkdir -p "$ROOT/_templates" "$ROOT/_index"
cp "$ASSETS/templates"/*.html "$ROOT/_templates/"
cp "$ASSETS/style.css" "$ROOT/_index/style.css"
cp "$ASSETS/index"/*.mjs "$ROOT/_index/"

# 共有 CSS を置き場の全 doc と template へ配る (正本は _index/style.css)。
if [ -f "$ROOT/_index/sync-style.mjs" ]; then
  (cd "$ROOT" && node _index/sync-style.mjs) || exit 1
  # 注入後の template を正本へ戻し、次回の --check が一致するようにする。
  cp "$ROOT/_templates"/*.html "$ASSETS/templates/"
fi

echo "反映した: templates $(ls -1 "$ASSETS/templates"/*.html | wc -l | tr -d ' ') 件 + style.css + script $(ls -1 "$ASSETS/index"/*.mjs | wc -l | tr -d ' ') 件"
