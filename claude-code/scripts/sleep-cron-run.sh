#!/usr/bin/env bash
# Usage: sleep-cron-run.sh [--repo <path>] [--days N] [--model M] [--checker-model M]
#                          [--max-cost-usd X] [--max-seconds N] [--dry-run]
# 夜間 1 回の単発 pipeline: harvest → mine (claude -p) → gate → stage/reject。
# exit: 0=staged or skip / 2=env error / 3=no-proposal / 4=gate reject or tracked 変化
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/redact.sh
source "${ROOT}/lib/redact.sh"
# shellcheck source=../lib/tracked-guard.sh
source "${ROOT}/lib/tracked-guard.sh"

REPO="$(cd "${ROOT}/.." && pwd)"
DAYS=7
MODEL="sonnet"
CHECKER_MODEL="haiku"
MAX_COST_USD="2.00"
MAX_SECONDS=900
# 子 process の終了を待つ watchdog の poll 間隔。bats は 1 を渡して待ちを縮める
# (既定の 5 のままだと stub 化した claude の終了待ちに 1 tick 5 秒を払う)。
# bash の算術は整数のみなので 1 秒未満は採らない (waited の加算が壊れる)
POLL_SECONDS="${SLEEP_CRON_POLL_SECONDS:-5}"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --days) DAYS="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --checker-model) CHECKER_MODEL="$2"; shift 2 ;;
    --max-cost-usd) MAX_COST_USD="$2"; shift 2 ;;
    --max-seconds) MAX_SECONDS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || true)}"
[[ -n "${CLAUDE_BIN}" ]] || { echo "ERROR: claude CLI が見つかりません" >&2; exit 2; }
command -v jq >/dev/null || { echo "ERROR: jq が見つかりません" >&2; exit 2; }
git -C "${REPO}" rev-parse --git-dir >/dev/null 2>&1 || { echo "ERROR: --repo が git repo でない: ${REPO}" >&2; exit 2; }
[[ -d "${REPO}/memory" ]] || { echo "ERROR: ${REPO}/memory がない" >&2; exit 2; }

STATE_DIR="${SLEEP_STATE_DIR:-${HOME}/.claude/sleep}"
LOG_DIR="${HOME}/.claude/logs"
LOG="${LOG_DIR}/sleep-cron.log"
STATE="${STATE_DIR}/state.md"
TEMPLATE="${ROOT}/templates/sleep-mine-prompt.md.template"
DATE="$(date '+%F')"
STAGE_FILE="${REPO}/memory/sleep-proposals-${DATE}.md"
DIGEST_FILE="${STATE_DIR}/digest-${DATE}.md"
WARN_FLAG="${STATE_DIR}/tracked-change-warn"
mkdir -p "${STATE_DIR}" "${LOG_DIR}"
find "${STATE_DIR}" -maxdepth 1 -name 'digest-*.md' -mtime +7 -delete 2>/dev/null || true
tracked_guard_cleanup_quarantine "${STATE_DIR}"

# stdout に出力する (stderr に出力すると launchd の err.log に正常ログが蓄積し daily-report が誤警報する)
_log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "${LOG}"; }

_init_state() {
  [[ -f "${STATE}" ]] && return 0
  cat > "${STATE}" <<EOF
# sleep pipeline state

- Status: never-run

## Ledger

| date | result | proposals | cost (USD) |
|------|--------|-----------|------------|
EOF
}

_ledger() {
  local row="| ${DATE} | $1 | $2 | $3 |"
  awk -v row="${row}" '{ print; if (!done && /^\|---/) { print row; done = 1 } }' \
    "${STATE}" > "${STATE}.tmp" && mv "${STATE}.tmp" "${STATE}"
}

_mark_done() {
  if grep -q '^- Status: ' "${STATE}"; then
    sed 's|^- Status: .*|- Status: done|' "${STATE}" > "${STATE}.tmp" && mv "${STATE}.tmp" "${STATE}"
  fi
}

_reject() {
  local reason="$1"
  printf '\nREJECT (%s): %s\n' "${DATE}" "${reason}" >> "${STAGE_FILE}"
  # maker が記載した本文ごと伏字化して保持する (.rejected.md はローカル限定だが、redact 経路を reject 理由行だけにしない)
  redact_private_terms < "${STAGE_FILE}" > "${STAGE_FILE}.tmp" && mv "${STAGE_FILE}.tmp" "${STAGE_FILE}"
  mv "${STAGE_FILE}" "${STAGE_FILE%.md}.rejected.md"
  _ledger "REJECT" "-" "${total_cost:-0}"
  _log "reject: ${reason}"
}

# gate B が proposal 単位で reject したときに、その section だけを .rejected.md へ分離する。
# stage file には approve 分だけを残し、1 提案の違反で残りを巻き添えにしない
_split_rejected() {
  local ids="$1" reasons="$2"
  local rej="${STAGE_FILE%.md}.rejected.md" body="${STAGE_FILE}.rejbody"
  rm -f "${body}"
  # 同 run 内で gate A / gate B が両方 split しうるため、既存 file には追記する
  if [[ ! -f "${rej}" ]]; then
    printf '# sleep proposals %s (per-proposal reject)\n\n' "${DATE}" > "${rej}"
  fi
  awk -v ids=" ${ids} " -v body="${body}" '
    /^### P[0-9]+:/ { id = $2; sub(/:$/, "", id); cur = (index(ids, " " id " ") > 0) ? "R" : "K" }
    { if (cur == "R") print > body; else print }
  ' "${STAGE_FILE}" > "${STAGE_FILE}.keep"
  if [[ -f "${body}" ]]; then cat "${body}" >> "${rej}"; fi
  rm -f "${body}"
  printf '\nREJECT (%s):\n%s\n' "${DATE}" "${reasons}" >> "${rej}"
  redact_private_terms < "${rej}" > "${rej}.tmp" && mv "${rej}.tmp" "${rej}"
  mv "${STAGE_FILE}.keep" "${STAGE_FILE}"
}

_init_state

# 完走した run は ledger に STAGED 行を記録するか file を .rejected/.adopted へ rename する。
# ledger 無しの素の当日 file は途中死 (電源断 / battery sleep) の残骸で、放置すると当日 re-run と /sleep-review を止める
if [[ -f "${STAGE_FILE}" ]] && ! grep -q "^| ${DATE} | STAGED |" "${STATE}" 2>/dev/null; then
  _log "未完走の stage file を回収して再実行する (前回 run の途中死)"
  rm -f "${STAGE_FILE}"
fi

# 自分が生成する file 名に厳密一致させる。広い glob だと同日の audit / retrospective の
# staging file に hit し、catch-up 実行で順序が入れ替わった日に mine を丸ごと skip してしまう
for _suffix in .md .rejected.md .adopted.md; do
  if [[ -f "${REPO}/memory/sleep-proposals-${DATE}${_suffix}" ]]; then
    _log "当日分が既に存在するため skip (idempotent)"
    exit 0
  fi
done

staged_count=0
for f in "${REPO}"/memory/sleep-proposals-*.md; do
  [[ -f "${f}" ]] || continue
  case "${f}" in
    *.rejected.md|*.adopted.md) continue ;;
  esac
  staged_count=$((staged_count + 1))
done
if [[ "${staged_count}" -ge 3 ]]; then
  _log "staged が ${staged_count} 件滞留している。/sleep-review を先に実行する (新規 mine skip)"
  exit 0
fi

[[ -f "${TEMPLATE}" ]] || { echo "ERROR: template がない: ${TEMPLATE}" >&2; exit 2; }

_log "harvest start (days=${DAYS})"
"${SCRIPT_DIR}/sleep-harvest.sh" --days "${DAYS}" --repo "${REPO}" > "${DIGEST_FILE}"

# gate 差し戻し用 (attempt 2 で reject 理由と前回本文を prompt へ注入する)
RETRY_FEEDBACK=""
PREV_PROPOSALS=""

_build_prompt() {
  sed -e "s|{{DATE}}|${DATE}|g" -e "s|{{TARGET_FILE}}|${STAGE_FILE}|g" "${TEMPLATE}"
  if [[ -n "${RETRY_FEEDBACK}" ]]; then
    printf '\n---\n\n## 前回 reject 理由 (必ず修正)\n\n%s\n\n### 前回の提案本文 (修正の起点にする)\n\n%s\n' \
      "${RETRY_FEEDBACK}" "${PREV_PROPOSALS}"
  fi
  printf '\n---\n\n## Harvest digest\n\n'
  cat "${DIGEST_FILE}"
}

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "=== sleep plan (dry-run) ==="
  echo "repo=${REPO} model=${MODEL} checker=${CHECKER_MODEL} stage=${STAGE_FILE}"
  echo ""
  _build_prompt
  exit 0
fi

# gate A (schema fail) / gate B (checker REJECT) は理由を prompt へ注入して 1 回だけ再 mine する。
# infra 起因の fail (watchdog timeout / tracked file 変更) は再試行で解消しないため即 reject する
total_cost=0
for attempt in 1 2; do
  if [[ "${attempt}" -eq 2 ]]; then
    _ledger "RETRY" "-" "${total_cost}"
    _log "retry: 前回 reject 理由を注入して再 mine する (attempt 2/2)"
  fi

  printf '# sleep proposals %s\n\n(この file を Edit tool で埋める)\n' "${DATE}" > "${STAGE_FILE}"

  before_fp="$(tracked_guard_fingerprint "${REPO}")"
  before_paths="$(tracked_guard_changed_paths "${REPO}")"
  _log "mine start (model=${MODEL}, attempt ${attempt})"

  maker_out="${STATE_DIR}/.maker-out"
  : > "${maker_out}"
  set -m
  # acceptEdits は Write / NotebookEdit も自動承認するため、tool 単位で明示的に禁止する
  # (許可は stage file を埋める Edit のみ。Task も禁止する: subagent は別 tool set を保持し迂回路になる)
  ( _build_prompt | (cd "${REPO}" && "${CLAUDE_BIN}" -p --model "${MODEL}" \
      --disallowedTools "Write" "Bash" "NotebookEdit" "WebFetch" "WebSearch" "Task" \
      --output-format json --permission-mode acceptEdits) > "${maker_out}" 2>>"${LOG}" ) &
  maker_pid=$!
  set +m
  waited=0
  watchdog_timeout=0
  while kill -0 "${maker_pid}" 2>/dev/null; do
    sleep "${POLL_SECONDS}"
    waited=$((waited + POLL_SECONDS))
    if [[ "${waited}" -ge "${MAX_SECONDS}" ]]; then
      # maker_pid はパイプライン全体の process group leader (set -m で個別 group 化)。
      # 単一 PID kill だと外側 subshell しか終了せず claude 本体が orphan で残存する
      kill -- "-${maker_pid}" 2>/dev/null || kill "${maker_pid}" 2>/dev/null || true
      wait "${maker_pid}" 2>/dev/null || true
      watchdog_timeout=1
      break
    fi
  done
  [[ "${watchdog_timeout}" -eq 1 ]] || wait "${maker_pid}" || true

  attempt_cost=$(jq -r 'if type=="array" then (.[-1].total_cost_usd // 0) else (.total_cost_usd // 0) end' \
    "${maker_out}" 2>/dev/null || echo 0)
  total_cost=$(awk -v a="${total_cost}" -v b="${attempt_cost}" 'BEGIN { printf "%.4f", a + b }')
  if awk -v a="${total_cost}" -v b="${MAX_COST_USD}" 'BEGIN { exit !(a >= b) }'; then
    _log "WARN: mine cost \$${total_cost} が上限 \$${MAX_COST_USD} に達した"
  fi

  after_fp="$(tracked_guard_fingerprint "${REPO}")"
  if [[ "${before_fp}" != "${after_fp}" ]]; then
    tracked_guard_revert_new_paths "${REPO}" "${before_paths}" "${STATE_DIR}/quarantine-${DATE}-mine" \
      | while IFS= read -r line; do _log "guard: ${line}"; done
    printf "%s mine\n" "${DATE}" >> "${WARN_FLAG}"
    _reject "maker が tracked file を変更した (該当 path のみ restore 済、要確認)"
    exit 4
  fi

  if [[ "${watchdog_timeout}" -eq 1 ]]; then
    _reject "mine が ${MAX_SECONDS}s を超過 (watchdog kill)"
    exit 4
  fi

  _log "gate A: schema check (attempt ${attempt})"
  set +e
  gate_a_out=$("${SCRIPT_DIR}/sleep-proposal-check.sh" "${STAGE_FILE}" --repo "${REPO}" --digest "${DIGEST_FILE}" 2>&1)
  gate_a=$?
  set -e
  printf '%s\n' "${gate_a_out}" >> "${LOG}"
  if [[ "${gate_a}" -eq 3 ]]; then
    # NO-PROPOSAL 経路も reject / staged と同様に本文を伏字化してから保持する
    redact_private_terms < "${STAGE_FILE}" > "${STAGE_FILE}.tmp" && mv "${STAGE_FILE}.tmp" "${STAGE_FILE}"
    mv "${STAGE_FILE}" "${STAGE_FILE%.md}.rejected.md"
    _ledger "NO-PROPOSAL" "0" "${total_cost}"
    _mark_done
    _log "no-proposal で終了 (正常)"
    exit 3
  elif [[ "${gate_a}" -ne 0 ]]; then
    # gate B と同じ per-proposal 構造: block 単位の NG のみ (file-level 違反なし) で、
    # clean な proposal が 1 件以上残存するなら、違反分だけ分離して gate B へ続行する。
    # file-level 違反 (行数/件数超過・private term・block ゼロ) は proposal に帰属できないため従来どおり全体差し戻し
    a_bad_ids=$(grep -oE '^NG: block P[0-9]+' <<< "${gate_a_out}" | grep -oE 'P[0-9]+' | sort -u | tr '\n' ' ')
    a_bad_count=$(wc -w <<< "${a_bad_ids}" | tr -d ' ')
    a_file_level=$(grep '^NG: ' <<< "${gate_a_out}" | grep -cv '^NG: block P[0-9]* L' || true)
    a_all=$(grep -cE '^### P[0-9]+:' "${STAGE_FILE}" || true)
    if [[ "${a_file_level}" -eq 0 && "${a_bad_count}" -gt 0 && "${a_bad_count}" -lt "${a_all}" ]]; then
      a_reasons=$(grep '^NG: block P[0-9]' <<< "${gate_a_out}" | sed 's/^NG: block //')
      _split_rejected "${a_bad_ids% }" "${a_reasons}"$'\n'
      _log "gate A: schema violation ${a_bad_count} 件を分離、残り $((a_all - a_bad_count)) 件で続行"
    elif [[ "${attempt}" -eq 1 ]]; then
      RETRY_FEEDBACK="gate A schema check fail:"$'\n'"${gate_a_out}"
      PREV_PROPOSALS="$(cat "${STAGE_FILE}")"
      rm -f "${STAGE_FILE}"
      _log "gate A fail → 差し戻し (schema violation)"
      continue
    else
      _reject "schema check fail (詳細: ${LOG})"
      exit 4
    fi
  fi

  _log "gate B: checker verdict (model=${CHECKER_MODEL}, attempt ${attempt})"
  checker_prompt=$(printf 'You are an independent reviewer. Answer from the digest and proposals only.\nChecklist: (1) each Evidence cites data that exists in the digest (2) each Change stays within its Target scope (3) no proposal performs config self-modification, merge, push, or deploy (proposing a removal for human review is allowed; Type: remove needs only zero-usage evidence).\nJudge every proposal independently: a violation in one proposal must not affect the verdict of the others.\nOutput one line per proposal, in the order they appear, and nothing else:\nP<n>: APPROVE\nP<n>: REJECT <reason>\n\n## Digest\n\n%s\n\n## Proposals\n\n%s\n' \
    "$(cat "${DIGEST_FILE}")" "$(cat "${STAGE_FILE}")")
  # checker にも watchdog を掛ける。API stall で hang すると gate A 通過済の中間 file が残り、
  # 翌日以降 idempotent skip に阻まれて手動介入まで pipeline が止まる
  checker_raw="${STATE_DIR}/.checker-out"
  : > "${checker_raw}"
  set -m
  ( printf '%s' "${checker_prompt}" | "${CLAUDE_BIN}" -p --model "${CHECKER_MODEL}" \
      --output-format json > "${checker_raw}" 2>>"${LOG}" ) &
  checker_pid=$!
  set +m
  waited=0
  checker_timeout=0
  while kill -0 "${checker_pid}" 2>/dev/null; do
    sleep "${POLL_SECONDS}"
    waited=$((waited + POLL_SECONDS))
    if [[ "${waited}" -ge "${MAX_SECONDS}" ]]; then
      kill -- "-${checker_pid}" 2>/dev/null || kill "${checker_pid}" 2>/dev/null || true
      wait "${checker_pid}" 2>/dev/null || true
      checker_timeout=1
      break
    fi
  done
  [[ "${checker_timeout}" -eq 1 ]] || wait "${checker_pid}" || true
  if [[ "${checker_timeout}" -eq 1 ]]; then
    _reject "checker が ${MAX_SECONDS}s を超過 (watchdog kill)"
    exit 4
  fi
  checker_out=$(jq -r 'if type=="array" then (.[-1].result // empty) else (.result // empty) end' \
    "${checker_raw}" 2>/dev/null || true)
  # proposal ごとに verdict 行を取得する。行が無い id は全体 verdict へ fallback し、
  # それも無ければ parse 不能として reject 側にする (安全側)
  fallback_verdict=""
  if grep -q 'VERDICT: APPROVE' <<< "${checker_out}"; then
    fallback_verdict="APPROVE"
  else
    fallback_verdict="REJECT $(grep -o 'VERDICT: REJECT.*' <<< "${checker_out}" | head -1 || true)"
  fi
  approved_ids=""
  rejected_ids=""
  reject_reasons=""
  while read -r id; do
    [[ -n "${id}" ]] || continue
    verdict_line=$(grep -m1 -E "^${id}: (APPROVE|REJECT)" <<< "${checker_out}" || true)
    verdict="${verdict_line#"${id}": }"
    [[ -n "${verdict_line}" ]] || verdict="${fallback_verdict}"
    if [[ "${verdict}" == APPROVE* ]]; then
      approved_ids="${approved_ids}${id} "
    else
      rejected_ids="${rejected_ids}${id} "
      [[ "${verdict}" == REJECT*[![:space:]]* ]] || verdict="REJECT (checker 出力が parse 不能)"
      reject_reasons="${reject_reasons}${id}: ${verdict}"$'\n'
    fi
  done <<< "$(grep -oE '^### P[0-9]+:' "${STAGE_FILE}" | sed -e 's/^### //' -e 's/:$//')"
  approved_count=$(wc -w <<< "${approved_ids}" | tr -d ' ')
  rejected_count=$(wc -w <<< "${rejected_ids}" | tr -d ' ')
  _log "gate B: approve ${approved_count} / reject ${rejected_count}"

  if [[ "${rejected_count}" -gt 0 ]]; then
    if [[ "${approved_count}" -gt 0 ]]; then
      _split_rejected "${rejected_ids% }" "${reject_reasons}"
      _log "gate B: reject ${rejected_count} 件を分離、approve ${approved_count} 件で staging を続ける"
      break
    fi
    reason="VERDICT: REJECT ${reject_reasons//$'\n'/ }"
    if [[ "${attempt}" -eq 1 ]]; then
      RETRY_FEEDBACK="gate B checker verdict: ${reason}"
      PREV_PROPOSALS="$(cat "${STAGE_FILE}")"
      rm -f "${STAGE_FILE}"
      _log "gate B 全 reject → 差し戻し (${reason})"
      continue
    fi
    _reject "${reason}"
    exit 4
  fi
  break
done

# STAGED 側にも redact を適用する (digest は redact 済だが、maker が digest 外から
# private term を引用した場合の防御を reject 側と対称にする)
redact_private_terms < "${STAGE_FILE}" > "${STAGE_FILE}.tmp" && mv "${STAGE_FILE}.tmp" "${STAGE_FILE}"

proposals=$(grep -c '^### P[0-9]*:' "${STAGE_FILE}" || echo 0)

_log "gate C: self-review (auto-adopt Tier1/2)"
set +e
self_review_out=$("${SCRIPT_DIR}/sleep-self-review.sh" "${STAGE_FILE}" 2>>"${LOG}")
self_review_status=$?
set -e
if [[ "${self_review_status}" -eq 0 ]]; then
  _log "self-review: ${self_review_out}"
  auto_adopted=$(grep -oE 'AUTO_ADOPT [0-9]+' <<< "${self_review_out}" | grep -oE '[0-9]+' || echo 0)
  _ledger "AUTO ${auto_adopted}/${proposals}" "${proposals}" "${total_cost}"
else
  _log "WARN: self-review 失敗 (exit ${self_review_status})、staging のみで継続"
  _ledger "STAGED" "${proposals}" "${total_cost}"
fi
_mark_done
_log "staged: ${STAGE_FILE} (${proposals} proposals, cost \$${total_cost})"
echo "staged: ${STAGE_FILE}"
