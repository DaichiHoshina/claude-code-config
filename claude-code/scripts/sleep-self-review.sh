#!/usr/bin/env bash
# Usage: sleep-self-review.sh <stage-file>
# gate B 通過済 proposal を Tier 判定し、Tier1 (data/dict 追記) と Tier2 (command/skill/claude-md
# 追記) は self-review (claude -p, sonnet) の AUTO_ADOPT 判定を経て自動適用する。
# audit (npm audit fix) は npm test 通過を条件に決定的に auto-adopt する (LLM 不要)。
# Tier3 (hook / remove / new-skill) は常に HOLD (翌朝 /sleep-review 必須)。
# exit: 0=処理完了 (adopt/hold/reject の内訳は stdout) / 1=proposal 解析失敗 / 2=usage / env error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

STAGE_FILE="${1:-}"
[[ -n "${STAGE_FILE}" && -f "${STAGE_FILE}" ]] || { echo "ERROR: stage file を指定する" >&2; exit 2; }
command -v jq >/dev/null || { echo "ERROR: jq が見つかりません" >&2; exit 2; }

REPO="$(cd "$(dirname "$(dirname "${STAGE_FILE}")")" && pwd)"
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || true)}"
DATE="$(date '+%F')"
TRIAGE_LOG="${REPO}/memory/sleep-triage-log.md"
LOG="${SLEEP_STATE_DIR:-${HOME}/.claude/sleep}/self-review.log"
mkdir -p "$(dirname "${LOG}")"

# Tier2 の claude -p は無人実行なので上限を掛ける。timeout 発動 (124) は
# verdict 空 → HOLD / 適用途中 → verify_diff fail → revert の既存経路へ落ちる
TIER2_MAX_SECONDS="${TIER2_MAX_SECONDS:-300}"
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
[[ -n "${TIMEOUT_BIN}" ]] || printf 'WARN: timeout / gtimeout が無いため無制限で実行する\n' >> "${LOG}"

_claude_bounded() {
  if [[ -n "${TIMEOUT_BIN}" ]]; then
    "${TIMEOUT_BIN}" "${TIER2_MAX_SECONDS}" "${CLAUDE_BIN}" "$@"
  else
    "${CLAUDE_BIN}" "$@"
  fi
}

SKILL_LINT="${REPO}/claude-code/scripts/skill-lint.sh"
[[ -x "${SKILL_LINT}" ]] || SKILL_LINT="${ROOT}/scripts/skill-lint.sh"

adopt_count=0
hold_count=0
reject_count=0
any_pending=0

_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "${s}"
}

_resolve_target_path() {
  local raw first
  raw="$1"
  first="$(_trim "${raw%%,*}")"
  if [[ "${first}" == /* ]]; then
    printf '%s' "${first}"
  else
    printf '%s' "${REPO}/${first}"
  fi
}

_tier_for() {
  local type="$1" target="$2" first
  case "${type}" in
    hook|remove|new-skill) echo 3; return ;;
    audit) echo audit; return ;;
  esac
  first="$(_trim "${target%%,*}")"
  case "${first}" in
    CLAUDE*.md|*/CLAUDE*.md)
      echo 3; return ;;
  esac
  case "${first}" in
    */NG-DICTIONARY.md|NG-DICTIONARY.md|*/allowed-en-terms.txt|allowed-en-terms.txt|*/lib/jp-quality/*|lib/jp-quality/*)
      echo 1; return ;;
  esac
  case "${first}" in
    commands/*.md|skills/*/SKILL.md|skills/*/skill.md|agents/*.md|cursor/*|cursor/*/*)
      echo 2; return ;;
  esac
  echo 3
}

_is_tier1_additive() {
  local change="$1"
  if [[ "${change}" != *追加* && "${change}" != *追記* ]]; then
    return 1
  fi
  if [[ "${change}" == *置換* || "${change}" == *削除して* || "${change}" == *上書き* ]]; then
    return 1
  fi
  return 0
}

_log_triage() {
  local pnum="$1" title="$2" status="$3" reason="$4"
  printf '%s | %s %s | %s | %s\n' "${DATE}" "${pnum}" "${title}" "${status}" "${reason}" >> "${TRIAGE_LOG}"
}

_commit_proposal() {
  local target_path="$1" pnum="$2" title="$3"
  git -C "${REPO}" add -- "${target_path}" >>"${LOG}" 2>&1 || true
  git -C "${REPO}" commit -q -m "sleep-auto: ${pnum} ${title}" >>"${LOG}" 2>&1 || true
}

_tier2_review() {
  local block="$1" target_path="$2" content=""
  [[ -f "${target_path}" ]] && content="$(cat "${target_path}")"
  local prompt
  prompt=$(printf 'You are an independent reviewer for a proposed doc/config edit. Judge only from the proposal and current file content below.\nChecklist: (1) the change is additive only, it does not remove or rewrite existing guard sentences, frontmatter, or established rules (2) the Change stays within the Target scope described (3) the edit does not touch hooks, permissions, or destructive operations.\nIf all pass respond exactly "VERDICT: AUTO_ADOPT", otherwise "VERDICT: HOLD <reason>" or "VERDICT: REJECT <reason>".\n\n## Proposal\n\n%s\n\n## Current file content (%s)\n\n%s\n' \
    "${block}" "${target_path}" "${content}")
  printf '%s' "${prompt}" | _claude_bounded -p --model sonnet --fallback-model sonnet \
    --output-format json 2>>"${LOG}" \
    | jq -r 'if type=="array" then (.[-1].result // empty) else (.result // empty) end' || true
}

_tier2_apply() {
  local block="$1" target_path="$2"
  local prompt
  prompt=$(printf 'Apply exactly the following proposed change to the file %s. Make only the described addition; do not remove or rewrite unrelated existing content. Respond with "APPLIED" when done.\n\n%s\n' \
    "${target_path}" "${block}")
  (cd "${REPO}" && printf '%s' "${prompt}" | _claude_bounded -p --model sonnet --fallback-model sonnet \
    --output-format json --permission-mode acceptEdits) >/dev/null 2>>"${LOG}"
}

# _tier2_apply 後、reviewer LLM の checklist 判断だけに頼らず決定的に検証する:
# (1) 変更 file が target_path のみ (2) 削除行が 0 (additive-only)
_tier2_verify_diff() {
  local target_path="$1" rel status_lines file_count del
  rel="${target_path#"${REPO}"/}"
  status_lines="$(git -C "${REPO}" status --porcelain)"
  file_count="$(printf '%s\n' "${status_lines}" | grep -c '.' || true)"
  if [[ "${file_count}" -ne 1 ]]; then
    return 1
  fi
  if ! printf '%s\n' "${status_lines}" | awk '{print $2}' | grep -qx -- "${rel}"; then
    return 1
  fi
  del="$(git -C "${REPO}" diff --numstat -- "${target_path}" | awk '{print $2}')"
  [[ "${del:-0}" == "0" ]]
}

_tier2_revert_all() {
  local files=()
  while IFS= read -r f; do
    [[ -n "${f}" ]] && files+=("${f}")
  done < <(git -C "${REPO}" status --porcelain | awk '{print $2}')
  if [[ "${#files[@]}" -gt 0 ]]; then
    git -C "${REPO}" checkout -- "${files[@]}" 2>/dev/null || true
  fi
}

_process_block() {
  local start="$1" end="$2" block header pnum title type target change tier verdict reason target_path

  block="$(sed -n "${start},${end}p" "${STAGE_FILE}")"
  header="$(sed -n '1p' <<< "${block}")"
  pnum="$(grep -oE 'P[0-9]+' <<< "${header}" | head -1)"
  title="$(sed -E 's/^### P[0-9]+: //' <<< "${header}")"
  type="$(sed -n 's/^- Type: //p' <<< "${block}" | head -1)"
  target="$(sed -n 's/^- Target: //p' <<< "${block}" | head -1)"
  change="$(sed -n 's/^- Change: //p' <<< "${block}" | head -1)"

  if [[ -z "${pnum}" || -z "${type}" || -z "${target}" ]]; then
    _log_triage "${pnum:-P?}" "${title:-unknown}" "hold" "block 解析失敗 (Type/Target 欠落)"
    hold_count=$((hold_count + 1))
    any_pending=1
    return
  fi

  tier="$(_tier_for "${type}" "${target}")"
  target_path="$(_resolve_target_path "${target}")"

  case "${tier}" in
    3)
      _log_triage "${pnum}" "${title}" "hold" "Tier3 (${type}) は人手 triage 必須"
      hold_count=$((hold_count + 1))
      any_pending=1
      ;;
    audit)
      # package-lock.json は untracked のため commit は package.json 変更時のみ発生する
      if ! command -v npm >/dev/null; then
        _log_triage "${pnum}" "${title}" "hold" "npm 未検出のため audit auto-adopt 不能"
        hold_count=$((hold_count + 1))
        any_pending=1
      elif (cd "${REPO}/claude-code" && npm audit fix >>"${LOG}" 2>&1 && npm test >>"${LOG}" 2>&1); then
        _commit_proposal "${REPO}/claude-code/package.json" "${pnum}" "${title}"
        _log_triage "${pnum}" "${title}" "auto-adopt" "npm audit fix + npm test pass"
        adopt_count=$((adopt_count + 1))
      else
        git -C "${REPO}" checkout -- claude-code/package.json 2>/dev/null || true
        _log_triage "${pnum}" "${title}" "hold" "npm audit fix または npm test fail、package.json を revert して HOLD"
        hold_count=$((hold_count + 1))
        any_pending=1
      fi
      ;;
    1)
      if [[ ! -f "${target_path}" ]]; then
        _log_triage "${pnum}" "${title}" "hold" "Tier1 target が実在しない: ${target_path}"
        hold_count=$((hold_count + 1))
        any_pending=1
      elif _is_tier1_additive "${change}"; then
        printf '%s\n' "${change}" >> "${target_path}"
        _commit_proposal "${target_path}" "${pnum}" "${title}"
        _log_triage "${pnum}" "${title}" "auto-adopt" "Tier1 追加のみ (形式チェック通過)"
        adopt_count=$((adopt_count + 1))
      else
        _log_triage "${pnum}" "${title}" "hold" "Tier1 additive 判定失敗 (削除/置換/上書き語を含む)"
        hold_count=$((hold_count + 1))
        any_pending=1
      fi
      ;;
    2)
      if [[ -z "${CLAUDE_BIN}" ]]; then
        _log_triage "${pnum}" "${title}" "hold" "CLAUDE_BIN 未検出のため self-review 不能"
        hold_count=$((hold_count + 1))
        any_pending=1
        return
      fi
      verdict="$(_tier2_review "${block}" "${target_path}")"
      if grep -q 'VERDICT: AUTO_ADOPT' <<< "${verdict}"; then
        _tier2_apply "${block}" "${target_path}" || true
        if ! _tier2_verify_diff "${target_path}"; then
          _tier2_revert_all
          _log_triage "${pnum}" "${title}" "hold" "Tier2 適用後 diff 検証 fail (削除行 or target 外編集)、revert して HOLD"
          hold_count=$((hold_count + 1))
          any_pending=1
          return
        fi
        if [[ "${type}" == "skill-edit" && -x "${SKILL_LINT}" ]]; then
          if ! "${SKILL_LINT}" >/dev/null 2>>"${LOG}"; then
            git -C "${REPO}" checkout -- "${target_path}" 2>/dev/null || true
            _log_triage "${pnum}" "${title}" "hold" "Tier2 適用後 skill-lint fail、revert して HOLD"
            hold_count=$((hold_count + 1))
            any_pending=1
            return
          fi
        fi
        _commit_proposal "${target_path}" "${pnum}" "${title}"
        _log_triage "${pnum}" "${title}" "auto-adopt" "Tier2 self-review AUTO_ADOPT"
        adopt_count=$((adopt_count + 1))
      elif grep -q 'VERDICT: REJECT' <<< "${verdict}"; then
        reason="$(grep -o 'VERDICT: REJECT.*' <<< "${verdict}" | head -1 || true)"
        _log_triage "${pnum}" "${title}" "reject" "${reason:-self-review REJECT}"
        reject_count=$((reject_count + 1))
      else
        reason="$(grep -o 'VERDICT: HOLD.*' <<< "${verdict}" | head -1 || true)"
        _log_triage "${pnum}" "${title}" "hold" "${reason:-self-review 出力が parse 不能}"
        hold_count=$((hold_count + 1))
        any_pending=1
      fi
      ;;
  esac
}

starts_raw="$(grep -n '^### P[0-9][0-9]*:' "${STAGE_FILE}" | cut -d: -f1 || true)"
if [[ -z "${starts_raw}" ]]; then
  echo "AUTO_ADOPT 0 / HOLD 0 / REJECT 0 (proposal block なし)"
  exit 0
fi

starts=()
while IFS= read -r ln; do
  [[ -n "${ln}" ]] || continue
  starts+=("${ln}")
done <<< "${starts_raw}"

total_lines="$(wc -l < "${STAGE_FILE}" | tr -d ' ')"
n="${#starts[@]}"
i=0
while [[ "${i}" -lt "${n}" ]]; do
  block_start="${starts[${i}]}"
  if [[ "$((i + 1))" -lt "${n}" ]]; then
    block_end="$((${starts[$((i + 1))]} - 1))"
  else
    block_end="${total_lines}"
  fi
  _process_block "${block_start}" "${block_end}"
  i=$((i + 1))
done

if [[ "${any_pending}" -eq 0 ]]; then
  mv "${STAGE_FILE}" "${STAGE_FILE%.md}.adopted.md"
fi

echo "AUTO_ADOPT ${adopt_count} / HOLD ${hold_count} / REJECT ${reject_count}"
