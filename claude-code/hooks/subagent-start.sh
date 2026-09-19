#!/usr/bin/env bash
# SubagentStart Hook - サブエージェント起動を検知
# エージェント情報をログ記録し、統計情報を表示

set -euo pipefail

# dirname + cd + pwd の 2 fork → bash parameter expansion に削減
_sa_src="${BASH_SOURCE[0]}"
[[ "${_sa_src}" == /* ]] || _sa_src="${PWD}/${_sa_src}"
SCRIPT_DIR="${_sa_src%/*}"
source "${SCRIPT_DIR}/../lib/hook-utils.sh"
# shellcheck source=lib/thresholds.sh
source "${BASH_SOURCE[0]%/*}/lib/thresholds.sh"
# shellcheck source=lib/log-rotation.sh
source "${BASH_SOURCE[0]%/*}/lib/log-rotation.sh"

# jq前提条件チェック
require_jq

# JSON入力を読み込む
INPUT=$(cat)

# エージェント情報を抽出（jq 1回で複数フィールド取得）
IFS=$'\x1f' read -r AGENT_ID AGENT_TYPE CWD RUN_ID SCOPE_ID GENERATION < <(
  extract_json_fields "$INPUT" \
    '.agent_id // "unknown"' \
    '.agent_type // "unknown"' \
    '.cwd // "."' \
    '.run_id // "unknown"' \
    '.scope_id // "unknown"' \
    '(.generation // "unknown" | tostring)'
)
TZ=UTC printf -v TIMESTAMP '%(%Y-%m-%dT%H:%M:%SZ)T' -1

# ログディレクトリ作成
LOG_DIR="${HOME}/.claude/logs"
mkdir -p "$LOG_DIR"

# ログファイルに記録（_TH_LOG_ROTATION_LINES 超でローテーション）
LOG_FILE="${LOG_DIR}/subagent-events.log"
_rotate_log_by_lines_if_needed "$LOG_FILE"

# 公式 payload は run_id/scope_id/generation を保証しない。存在時は論理 scope、
# 次に agent_id を安定 identity とし、どちらも無い時だけ type+時刻へ fallback する。
# fallback では別 agent の同時起動を区別できないため、重複判定は警告に留める
_DUP_WARN=""
_LIFECYCLE="START"
_NOW_EPOCH="${EPOCHSECONDS:-$(date +%s)}"
_IDENTITY_NEEDLE=""
if [[ "$RUN_ID" != "unknown" && "$SCOPE_ID" != "unknown" ]]; then
  _IDENTITY_NEEDLE="run_id=${RUN_ID} | scope_id=${SCOPE_ID} "
elif [[ "$AGENT_ID" != "unknown" ]]; then
  _IDENTITY_NEEDLE="agent_id=${AGENT_ID} "
fi
if [[ -f "$LOG_FILE" ]]; then
  # awk 1 fork で「同一 identity の最終 event・generation + 24h 起動カウント」を取得
  # index() は固定文字列検索（payload に正規表現メタ文字が含まれても誤マッチしない）
  # Field 2: -F'[][]' で各角括弧を区切りとし、`[2026-... ]` の中身を取得
  # cutoff: 24h 前を printf -v builtin で生成 (date fork 不要・クロスプラットフォーム)
  _CUTOFF_EPOCH=$(( _NOW_EPOCH - 86400 ))
  TZ=UTC printf -v _CUTOFF_DATE '%(%Y-%m-%dT%H:%M:%SZ)T' "${_CUTOFF_EPOCH}"
  IFS=$'\t' read -r _LAST_EVENT _LAST_SAME _LAST_GENERATION RECENT_COUNT < <(
    awk -F'[][]' \
      -v t="type=${AGENT_TYPE} " \
      -v identity="${_IDENTITY_NEEDLE}" \
      -v cutoff="${_CUTOFF_DATE}" \
      '
      /START|RESUME|STOP/ {
        matches = (identity != "" ? index($0, identity) : index($0, t))
        if (matches) {
          last_ts = $2
          if (index($0, "] STOP  |")) {
            last_event = "STOP"
          } else {
            last_event = (index($0, "] RESUME |") ? "RESUME" : "START")
            last_gen = "unknown"
            n = split($0, parts, "generation=")
            if (n > 1) {
              split(parts[2], suffix, " ")
              last_gen = suffix[1]
            }
          }
        }
      }
      /START|RESUME/ {
        if (cutoff == "" || $2 >= cutoff) cnt++
      }
      END {
        printf "%s\t%s\t%s\t%d\n",
          (last_event ? last_event : "-"),
          (last_ts ? last_ts : "-"),
          (last_gen != "" ? last_gen : "unknown"),
          cnt+0
      }
      ' "$LOG_FILE" || printf '%s\t%s\t%s\t%s\n' "-" "-" "unknown" "0"
  )
  if [[ "$_LAST_SAME" != "-" ]]; then
    if [[ "$GENERATION" =~ ^[0-9]+$ && "$_LAST_GENERATION" =~ ^[0-9]+$ ]] \
      && (( GENERATION > _LAST_GENERATION )); then
      _LIFECYCLE="RESUME"
    elif [[ "$GENERATION" == "unknown" && "$_LAST_EVENT" == "STOP" ]]; then
      _LIFECYCLE="RESUME"
    elif [[ "$_LAST_EVENT" == "START" || "$_LAST_EVENT" == "RESUME" ]]; then
      _LAST_EPOCH=$(_iso8601_to_epoch "$_LAST_SAME" || echo 0)
      if [[ "$_LAST_EPOCH" -gt 0 ]]; then
        _DIFF=$((_NOW_EPOCH - _LAST_EPOCH))
        if [[ "$_DIFF" -lt 60 ]]; then
          _DUP_WARN="⚠️ ${AGENT_TYPE} の同一 identity を${_DIFF}秒前に起動済み。重複起動の可能性あり。"
        fi
      fi
    fi
  fi
else
  RECENT_COUNT=0
fi

echo "[${TIMESTAMP}] ${_LIFECYCLE} | agent_id=${AGENT_ID} | type=${AGENT_TYPE} | run_id=${RUN_ID} | scope_id=${SCOPE_ID} | generation=${GENERATION} | cwd=${CWD}" >> "$LOG_FILE"

# --- Analytics記録をバックグラウンドへ ---
(
  _LIB_DIR="${SCRIPT_DIR}/../lib"
  if [[ -f "${_LIB_DIR}/analytics-writer.sh" ]]; then
    source "${_LIB_DIR}/analytics-writer.sh"
    _PROJECT=$(basename "$CWD")
    analytics_insert_agent_start "$AGENT_ID" "$AGENT_TYPE" "$_PROJECT" 2>/dev/null || true
  fi
) 2>/dev/null &

# 結果を返す（jqで安全にJSON生成）
AC_MSG="**Agent ID**: ${AGENT_ID}
**Type**: ${AGENT_TYPE}
**Lifecycle**: ${_LIFECYCLE}
**Run / Scope / Generation**: ${RUN_ID} / ${SCOPE_ID} / ${GENERATION}
**Working Directory**: ${CWD}
**Recent Activity**: ${RECENT_COUNT} subagents started in last 24h"
if [[ -n "$_DUP_WARN" ]]; then
  AC_MSG="${AC_MSG}

${_DUP_WARN}"
fi

_SM="🚀 Subagent started: ${AGENT_TYPE}"
if [[ "$_LIFECYCLE" == "RESUME" ]]; then
  _SM="🚀 Subagent RESUME: ${AGENT_TYPE}"
fi
if [[ -n "$_DUP_WARN" ]]; then
  _SM="⚠️ Subagent重複疑い: ${AGENT_TYPE}"
fi

jq -n \
  --arg sm "$_SM" \
  --arg ac "$AC_MSG" \
  '{systemMessage: $sm, additionalContext: $ac}'
