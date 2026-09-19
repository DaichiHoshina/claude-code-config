#!/usr/bin/env bash
# 2026-08-29 に非メイン PC の transcript を根拠に削除した command / plugin を、
# このマシンの transcript で数え直す。メイン PC で回して 0 でないものは git revert の対象。
# 使い方: ./scripts/prune-usage-recount.sh [--days N]   (default 90)
set -u
DAYS=90
[ "${1:-}" = "--days" ] && DAYS="${2:-90}"
ROOT="${HOME}/.claude/projects"
LOGS=$(find "$ROOT" -name '*.jsonl' -mtime "-${DAYS}" 2>/dev/null || true)
echo "# transcript: $(echo "$LOGS" | grep -c . ) file (過去 ${DAYS} 日) on $(hostname -s)"
printf '%-18s %s\n' command sessions
for c in handoff review-full analytics jp-lint norm-apply audit refactor review-fix-push review-fix-fable; do
  n=$(echo "$LOGS" | xargs grep -l "<command-name>/${c}</command-name>" 2>/dev/null | wc -l | tr -d ' ')
  printf '%-18s %s\n' "$c" "$n"
done
echo
printf '%-18s %s\n' plugin sessions
for p in 'code-review:code-review' 'commit-commands:commit' 'commit-commands:commit-push-pr' 'commit-commands:clean_gone'; do
  n=$(echo "$LOGS" | xargs grep -l "<command-name>${p}</command-name>" 2>/dev/null | wc -l | tr -d ' ')
  printf '%-30s %s\n' "$p" "$n"
done
echo
echo "復元点: 10c12b86 (handoff / review-full + plugin) / 59e5f679 (analytics jp-lint norm-apply audit refactor) / e84ce989 (review-fix-* の flag 統合)"
