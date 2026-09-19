#!/usr/bin/env bash

set -euo pipefail

# daily-report が検知した夜間 cron の失敗を無人修復し、PR 作成まで進める (merge は人が判断する)。
# 入力 queue file の形式: job<TAB>state<TAB>err 抜粋 (1 行 1 job、daily-report.sh が書く)

QUEUE="${1:?usage: cron-auto-repair.sh <queue-file>}"
REPO="${REPAIR_REPO:-${HOME}/ghq/github.com/<owner>/ai-tools}"
STATE_DIR="${HOME}/.claude/cron-repair"
LOG="${HOME}/.claude/logs/launchd/cron-auto-repair.log"
ATTEMPTS="${STATE_DIR}/attempts.tsv"
LOCK="${STATE_DIR}/lock"
WEBHOOK_FILE="${HOME}/.claude/secrets/slack-webhook"
CLAUDE_BIN="${CLAUDE_BIN:-${HOME}/.local/bin/claude}"
TEMPLATE="${REPO}/claude-code/templates/cron-repair-prompt.md.template"
MAX_TURNS="${REPAIR_MAX_TURNS:-80}"
MAX_SECONDS="${REPAIR_MAX_SECONDS:-3600}"

mkdir -p "${STATE_DIR}" "$(dirname "${LOG}")"
_log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "${LOG}"; }

notify() {
    local text="$1" url=""
    [[ -f "${WEBHOOK_FILE}" ]] || return 0
    url="$(tr -d '\n\r ' < "${WEBHOOK_FILE}")"
    [[ "${url}" =~ ^https://hooks\.slack\.com/ ]] || return 0
    curl -sf --max-time 15 -X POST -H 'Content-Type: application/json' \
        -d "$(printf '%s' "${text}" | python3 -c 'import sys, json; print(json.dumps({"text": sys.stdin.read()}))')" \
        "${url}" >/dev/null || _log "WARN: slack 通知に失敗した"
}

# 以降の log はすべて分岐の中でしか出ないため、出力が無いことを「起動前に死んだ」と「起動後に何もしなかった」へ分けられない
_log "起動した (queue: ${QUEUE})"

[[ -f "${QUEUE}" ]] || { _log "queue がない: ${QUEUE}"; exit 0; }
[[ -x "${CLAUDE_BIN}" ]] || { _log "ERROR: claude CLI がない: ${CLAUDE_BIN}"; exit 1; }
[[ -f "${TEMPLATE}" ]] || { _log "ERROR: template がない: ${TEMPLATE}"; exit 1; }
command -v jq >/dev/null || { _log "ERROR: jq がない"; exit 1; }

# SIGKILL / reboot で trap が発火しないと lock が残存するため、閾値超過の stale lock は回収する
LOCK_STALE_SEC="${REPAIR_LOCK_STALE_SEC:-7200}"
if ! mkdir "${LOCK}" 2>/dev/null; then
    lock_age=$(( $(date +%s) - $(stat -f %m "${LOCK}" 2>/dev/null || echo 0) ))
    if [[ "${lock_age}" -gt "${LOCK_STALE_SEC}" ]]; then
        _log "stale lock (${lock_age}s 経過) を回収して続行する"
        rmdir "${LOCK}" 2>/dev/null || true
        mkdir "${LOCK}" 2>/dev/null || { _log "lock 再取得に失敗した"; exit 1; }
    else
        _log "別 run が実行中のため skip"
        notify ":hourglass: cron auto-repair: 別 run 実行中のため今回の queue を skip した"
        exit 0
    fi
fi
# repair の claude は REPO 内で fix branch を checkout する。戻さないと以後の session が
# main に居るつもりで branch 上へ merge / commit してしまう (2026-08-23 実踏)
orig_ref="$(git -C "${REPO}" symbolic-ref --short -q HEAD || true)"
restore_branch() {
    [[ -n "${orig_ref:-}" ]] || return 0
    local cur
    cur="$(git -C "${REPO}" symbolic-ref --short -q HEAD || true)"
    [[ "${cur}" == "${orig_ref}" ]] && return 0
    if [[ -n "$(git -C "${REPO}" status --porcelain)" ]]; then
        _log "WARN: ${REPO} に未 commit 変更があり branch を ${orig_ref} へ戻せない (現在: ${cur:-detached})"
        return 0
    fi
    git -C "${REPO}" checkout -q "${orig_ref}" && _log "checkout を ${orig_ref} へ戻した (repair branch: ${cur:-detached})" \
        || _log "WARN: ${orig_ref} への checkout 復帰に失敗した"
}

# trap より後ろで定義すると、その窓で exit したとき restore_branch が未定義で command not found になる
trap 'restore_branch; rmdir "${LOCK}" 2>/dev/null || true' EXIT

today="$(date '+%F')"

while IFS=$'\t' read -r job state excerpt; do
    [[ -n "${job}" ]] || continue

    # 認証切れは code の修復対象ではなく、修復 run 自体も同じ理由で失敗する (2026-09-01 実踏)
    if printf '%s' "${excerpt}" | grep -qiE 'Failed to authenticate|OAuth session expired|Invalid API key'; then
        _log "${job}: 認証切れのため skip (再 login が必要)"
        continue
    fi

    # 一過性の API 障害は次回実行で自然回復するため修復対象にしない
    if printf '%s' "${excerpt}" | grep -qiE 'API Error|Connection closed|timed out|Request timeout|rate limit'; then
        _log "${job}: transient error のため skip"
        continue
    fi

    fp="$(printf '%s %s' "${job}" "${excerpt:0:200}" | shasum -a 256 | cut -c1-16)"
    touch "${ATTEMPTS}"
    recent="$(awk -F'\t' -v fp="${fp}" -v since="$(date -v-7d '+%F')" '$1 == fp && $2 >= since' "${ATTEMPTS}" | wc -l | tr -d ' ')"
    fails="$(awk -F'\t' -v fp="${fp}" '$1 == fp && $3 == "fail"' "${ATTEMPTS}" | wc -l | tr -d ' ')"

    if [[ "${recent}" -gt 0 ]]; then
        _log "${job}: fingerprint ${fp} は 7 日以内に試行済みのため skip"
        continue
    fi
    if [[ "${fails}" -ge 2 ]]; then
        _log "${job}: fingerprint ${fp} は 2 回失敗済み。自動修復を止める"
        notify ":no_entry: cron auto-repair: ${job} は同じ原因で 2 回失敗したため自動修復を止めた。手動対応が要る"
        continue
    fi

    # fingerprint を含めて同日同 job の別 error や残留 remote branch との衝突を避ける
    branch="fix/cron-auto-$(date '+%Y%m%d')-${job}-${fp:0:6}"
    prompt="$(sed -e "s|{{JOB}}|${job}|g" -e "s|{{STATE}}|${state}|g" -e "s|{{BRANCH}}|${branch}|g" "${TEMPLATE}")"
    # template 側の code fence を excerpt 内の ``` で閉じられないよう backtick を落とす
    excerpt="${excerpt//\`/}"
    prompt="${prompt//\{\{EXCERPT\}\}/${excerpt}}"

    _log "${job}: repair 開始 (fp=${fp}, branch=${branch})"
    claude_cmd=("${CLAUDE_BIN}" -p "${prompt}" --model sonnet --max-turns "${MAX_TURNS}"
        --permission-mode acceptEdits --output-format json)
    # claude hang で lock が保持され続けるのを防ぐ (--max-turns は時間上限にならない)
    TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
    [[ -n "${TIMEOUT_BIN}" ]] && claude_cmd=("${TIMEOUT_BIN}" "${MAX_SECONDS}" "${claude_cmd[@]}")

    out="$(cd "${REPO}" && "${claude_cmd[@]}" 2>> "${LOG}")" || true
    result_text="$(printf '%s' "${out}" | jq -r '.result // empty' 2>/dev/null || true)"
    [[ -n "${result_text}" ]] || result_text="${out}"
    # result が raw JSON のとき、緩い文字 class は URL 間の JSON 断片ごと 1 match に飲み込む
    pr_url="$(printf '%s' "${result_text}" | grep -oE 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+' | tail -1 || true)"

    if [[ -n "${pr_url}" ]]; then
        printf '%s\t%s\t%s\n' "${fp}" "${today}" "pr" >> "${ATTEMPTS}"
        _log "${job}: PR を作成した ${pr_url}"
        notify ":wrench: cron auto-repair: ${job} の修正 PR を作った → ${pr_url}"
    else
        printf '%s\t%s\t%s\n' "${fp}" "${today}" "fail" >> "${ATTEMPTS}"
        _log "${job}: PR URL を検出できなかった (fail 記録)。末尾出力: $(printf '%s' "${out}" | tail -c 300 | tr '\n' ' ')"
        notify ":warning: cron auto-repair: ${job} の自動修復が PR まで到達しなかった。log: ~/.claude/logs/launchd/cron-auto-repair.log"
    fi
done < "${QUEUE}"

rm -f "${QUEUE}"
