#!/usr/bin/env bash
# Task/Agent tool checkers (extracted from pre-tool-use.sh)
# 多重 source 防止
if [[ "${_TASK_AGENT_CHECKERS_LOADED:-}" == "1" ]]; then
    return 0
fi
_TASK_AGENT_CHECKERS_LOADED=1

# shellcheck source=thresholds.sh
source "${BASH_SOURCE[0]%/*}/thresholds.sh"

_explore_contract_has_field() {
  local prompt="$1"
  local field="$2"
  printf '%s\n' "$prompt" | LC_ALL=C awk -v wanted="$field" '
    {
      line=$0
      sub(/^[[:space:]-]*/, "", line)
      pos=index(line, ":")
      if (pos == 0) next
      key=tolower(substr(line, 1, pos - 1))
      gsub(/[[:space:].-]/, "_", key)
      if (key == wanted) found=1
    }
    END { exit(found ? 0 : 1) }
  '
}

_explore_contract_value() {
  local prompt="$1"
  local field="$2"
  printf '%s\n' "$prompt" | LC_ALL=C awk -v wanted="$field" '
    {
      line=$0
      sub(/^[[:space:]-]*/, "", line)
      pos=index(line, ":")
      if (pos == 0) next
      key=tolower(substr(line, 1, pos - 1))
      gsub(/[[:space:].-]/, "_", key)
      if (key != wanted) next
      value=substr(line, pos + 1)
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      gsub(/^["`]|["`]$/, "", value)
      print value
      exit
    }
  '
}

_explore_contract_occurrence_count() {
  local prompt="$1"
  shift
  local wanted
  wanted=$(IFS=,; printf '%s' "$*")
  printf '%s\n' "$prompt" | LC_ALL=C awk -v wanted_csv="$wanted" '
    BEGIN {
      count=split(wanted_csv, wanted, ",")
      for (i=1; i<=count; i++) wanted_key[wanted[i]]=1
    }
    {
      line=$0
      sub(/^[[:space:]-]*/, "", line)
      pos=index(line, ":")
      if (pos == 0) next
      key=tolower(substr(line, 1, pos - 1))
      gsub(/[[:space:].-]/, "_", key)
      if (key in wanted_key) occurrences++
    }
    END { print occurrences + 0 }
  '
}

_explore_block_values() {
  local prompt="$1"
  local field="$2"
  # 第 3 引数を渡すと "項目<TAB>分割前の行" で返す。comma 分割した断片だけでは
  # どの anchor が失敗したか読み手が特定できないため、anchor 検証だけが使う
  local with_origin="${3:-}"
  printf '%s\n' "$prompt" | LC_ALL=C awk -v wanted="$field" -v with_origin="$with_origin" '
    function trim(value) {
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      return value
    }
    function emit(value, count, item, origin) {
      value=trim(value)
      sub(/^[[]/, "", value)
      sub(/[]]$/, "", value)
      origin=value
      count=split(value, items, ",")
      for (i=1; i<=count; i++) {
        item=trim(items[i])
        gsub(/^["'\''`]|["'\''`]$/, "", item)
        if (item == "") continue
        if (with_origin != "") print item "\t" origin
        else print item
      }
    }
    {
      raw=$0
      line=raw
      sub(/^[[:space:]-]*/, "", line)
      pos=index(line, ":")
      if (!in_anchors && pos > 0) {
        key=tolower(substr(line, 1, pos - 1))
        gsub(/[[:space:].-]/, "_", key)
        if (key == wanted) {
          match(raw, /^[[:space:]]*/)
          anchor_indent=RLENGTH
          value=substr(line, pos + 1)
          value=trim(value)
          if (value != "") emit(value)
          in_anchors=1
          next
        }
      }
      if (!in_anchors) next
      if (raw ~ /^[[:space:]]*$/) next
      match(raw, /^[[:space:]]*/)
      indent=RLENGTH
      if (indent <= anchor_indent && raw !~ /^[[:space:]]*-/) exit
      value=raw
      sub(/^[[:space:]]*-[[:space:]]*/, "", value)
      emit(value)
    }
  '
}

_explore_anchor_values() {
  _explore_block_values "$1" anchor_evidence with_origin
}

# inline (`paths: [a, b]`) と block (`paths:` + `- a`) の両記法を同じ値として返す
_explore_contract_collection_value() {
  local prompt="$1"
  local field="$2"
  local value
  value=$(_explore_contract_value "$prompt" "$field")
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  _explore_block_values "$prompt" "$field"
}

_explore_value_is_placeholder() {
  local value="$1"
  local lower normalized
  [[ -z "$value" ]] && return 0
  [[ "$value" == *"<"* || "$value" == *">"* || "$value" == *"{{"* || "$value" == *"}}"* ]] && return 0
  lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  normalized=$(printf '%s' "$lower" | tr -d '[:space:]["'\''`]')
  case "$normalized" in
    ""|"none"|"n/a"|"na"|"todo"|"tbd"|"unknown"|"placeholder")
      return 0
      ;;
  esac
  return 1
}

_explore_collection_has_substantive_content() {
  local value="$1"
  printf '%s\n' "$value" | LC_ALL=C awk '
    BEGIN { RS="[\n,]" }
    {
      item=tolower($0)
      gsub(/^[[:space:]-]*/, "", item)
      gsub(/[[:space:]]*$/, "", item)
      sub(/^[[]/, "", item)
      sub(/[]]$/, "", item)
      gsub(/^["'\''`]+|["'\''`]+$/, "", item)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", item)
      normalized=item
      gsub(/[[:space:]]/, "", normalized)
      if (normalized == "" || normalized == "null" || normalized == "none" ||
          normalized == "n/a" || normalized == "na" || normalized == "todo" ||
          normalized == "tbd" || normalized == "unknown" ||
          normalized == "placeholder") next
      # <now> / <nil> のような正当な部分表記で誤爆しないよう、item 全体が
      # placeholder token だけで構成される場合のみ skip する
      stripped=item
      gsub(/<[^>]*>/, "", stripped)
      gsub(/\{\{[^}]*\}\}/, "", stripped)
      gsub(/[[:space:]]/, "", stripped)
      if (stripped == "") next
      found=1
    }
    END { exit(found ? 0 : 1) }
  '
}

_explore_excludes_is_valid() {
  local value="$1"
  local normalized
  normalized=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  case "$normalized" in
    "[]"|"none")
      return 0
      ;;
  esac
  _explore_collection_has_substantive_content "$value"
}

# contract 違反時に見せる最小例。target identity の 3 行だけは run ごとに変わるため
# placeholder で保持し、それ以外は literal でそのまま検査を通過する形を保つ。
# 例示が validator を通過することは tests/unit/hooks/task-agent-checkers-anchor-evidence.bats が実測する
# (誘導文言と受理形式の乖離が誤爆の再発源だった)
_explore_contract_example() {
  cat <<'EXAMPLE'
run_id: r1
scope_id: 1/1
expected_count: 1
target:
  worktree_path: <absolute path>
  branch: <branch>
  head: <full sha>
anchor_evidence:
  - src/main.go:12
paths: [src/]
questions: ["X はどこか"]
excludes: [vendor/]
stop_when: "X 特定で停止"
budget_class: focused
EXAMPLE
}

# 欠落 block の真因 (key 名の揺れ / prose 化 / scope 節の省略) を後から追えるよう、
# prompt に実在する key 名だけを値抜きで並べる。値を保持すると log に repo 固有情報が入る
_explore_contract_present_keys() {
  local prompt="$1"
  printf '%s\n' "$prompt" | LC_ALL=C awk '
    {
      line=$0
      sub(/^[[:space:]-]*/, "", line)
      pos=index(line, ":")
      if (pos == 0) next
      key=substr(line, 1, pos - 1)
      if (key !~ /^[A-Za-z_][A-Za-z0-9_]*$/) next
      if (seen[key]++) next
      out=(out == "" ? key : out "," key)
    }
    END { printf "%s", out }
  '
}

_block_explore_contract() {
  local detail="$1"
  local present_keys="${2:-}"
  GUARD_CLASS="Forbidden"
  MESSAGE="${ICON_CRITICAL} Explore contract invalid: ${detail} (agents/explore-agent.md 「Prompt contract」)。anchor_evidence は実在 file の path:line か path#symbol を 1-3 件 (相対 path、注記や prose を同じ行へ足さない)。最小例 (target の 3 行だけ実値へ置換する):
$(_explore_contract_example)"
  # anchor 側と同じ理由で保持する。log が無いと retrospective の集計に含まれず、
  # 同じ違反を何度踏んでも signal にならない (2026-08-29 に budget_class の
  # 誤値で 3 回 block されたが log は 1 件も無かった)
  if declare -f _append_block_log >/dev/null 2>&1; then
    _append_block_log "${HOME}/.claude/logs/explore-anchor-block.log" "${TOOL_NAME:-Agent}" "explore-contract" "${detail}${present_keys:+ keys=${present_keys}}"
  fi
}

_block_explore_target_anchor() {
  local detail="$1"
  GUARD_CLASS="Forbidden"
  MESSAGE="${ICON_CRITICAL} Explore Target Anchor Gate invalid: ${detail}。anchor_evidence は実在 file の path:line か path#symbol を 1-3 件 (相対 path、prose 不可)。反例: src/a.go:12-30 (行範囲不可) / src/a.go:0 (正の行番号のみ)。全違反を列挙済みなので 1 回の書き直しで全部直し、同じ Agent を resume せず fresh-launch する"
  # 誤爆と再発を後追いできるよう記録する。log が無いと retrospective の集計に含まれない
  if declare -f _append_block_log >/dev/null 2>&1; then
    _append_block_log "${HOME}/.claude/logs/explore-anchor-block.log" "${TOOL_NAME:-Agent}" "explore-anchor" "$detail"
  fi
}

# anchor 1 件の形式と実在を検証する。失敗理由は _EXPLORE_ANCHOR_DETAIL に置き、
# block するかどうかは呼出側 (注記付き anchor の再試行する) に委ねる
_explore_validate_anchor() {
  local anchor="$1"
  local actual_root="$2"
  local anchor_path anchor_line="" anchor_symbol="" resolved_path

  if [[ "$anchor" =~ ^(.+):([1-9][0-9]*)$ ]]; then
    anchor_path="${BASH_REMATCH[1]}"
    anchor_line="${BASH_REMATCH[2]}"
  elif [[ "$anchor" =~ ^([^#]+)#(.+)$ ]]; then
    anchor_path="${BASH_REMATCH[1]}"
    anchor_symbol="${BASH_REMATCH[2]}"
  else
    _EXPLORE_ANCHOR_DETAIL="anchor format must be path:positive-line or path#symbol (anchor: ${anchor})"
    return 1
  fi
  anchor_path="${anchor_path#./}"
  if [[ -z "$anchor_path" || "$anchor_path" == /* || "$anchor_path" == ".." || "$anchor_path" == ../* ]]; then
    _EXPLORE_ANCHOR_DETAIL="anchor must be relative to verified root (anchor: ${anchor})"
    return 1
  fi
  if [[ ! -f "${actual_root}/${anchor_path}" ]]; then
    _EXPLORE_ANCHOR_DETAIL="anchor file missing (anchor: ${anchor_path})"
    return 1
  fi
  resolved_path=$(_canonical_file_path "${actual_root}/${anchor_path}") || {
    _EXPLORE_ANCHOR_DETAIL="anchor cannot be resolved (anchor: ${anchor_path})"
    return 1
  }
  if [[ "$resolved_path" != "$actual_root"/* ]]; then
    _EXPLORE_ANCHOR_DETAIL="anchor escapes verified root (anchor: ${anchor_path})"
    return 1
  fi
  if [[ -n "$anchor_line" ]] && ! LC_ALL=C awk -v wanted="$anchor_line" 'NR == wanted { found=1; exit } END { exit(found ? 0 : 1) }' "$resolved_path"; then
    _EXPLORE_ANCHOR_DETAIL="anchor line missing (anchor: ${anchor})"
    return 1
  fi
  if [[ -n "$anchor_symbol" ]] && ! grep -Fq -- "$anchor_symbol" "$resolved_path"; then
    _EXPLORE_ANCHOR_DETAIL="anchor symbol missing (anchor: ${anchor})"
    return 1
  fi
  return 0
}

# comma で分割された anchor は断片だけでは元の記述を特定できないため、
# 分割前の行を violation へ添える。分割が起きていなければ detail をそのまま返す。
# detail の括弧の中に入れず外へ繋ぐ。断片が ")" で終わることがあり
# (例: "(注記, 後半)" の後半)、閉じ括弧を取り除く実装では対応が失われる
_explore_anchor_violation() {
  local detail="$1"
  local anchor="$2"
  local origin="$3"

  if [[ -n "$origin" && "$origin" != "$anchor" ]]; then
    printf '%s / 元行: %s' "$detail" "$origin"
    return 0
  fi
  printf '%s' "$detail"
}

_append_agent_context() {
  local text="$1"
  if [[ -n "${ADDITIONAL_CONTEXT:-}" ]]; then
    ADDITIONAL_CONTEXT="${ADDITIONAL_CONTEXT}"$'\n'"${text}"
  else
    ADDITIONAL_CONTEXT="${text}"
  fi
}

_canonical_file_path() {
  local path="$1"
  local link target_dir target_name
  local hops=0

  while [[ -L "$path" ]]; do
    ((hops += 1))
    (( hops <= 40 )) || return 1
    link=$(readlink "$path") || return 1
    if [[ "$link" == /* ]]; then
      path="$link"
    else
      path="${path%/*}/${link}"
    fi
  done

  target_dir="${path%/*}"
  target_name="${path##*/}"
  [[ "$target_dir" != "$path" ]] || target_dir="."
  target_dir=$(cd "$target_dir" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "$target_dir" "$target_name"
}

_validate_explore_prompt_contract() {
  local prompt="$1"
  local invalid=()
  local field value count
  for field in run_id scope_id expected_count anchor_evidence paths questions excludes stop_when budget_class; do
    count=$(_explore_contract_occurrence_count "$prompt" "$field")
    if (( count == 0 )); then
      [[ "$field" == "anchor_evidence" ]] || invalid+=("${field}:missing")
      continue
    fi
    if (( count > 1 )); then
      invalid+=("${field}:duplicate")
      continue
    fi
    [[ "$field" == "anchor_evidence" ]] && continue
    case "$field" in
      paths|questions|excludes|stop_when)
        value=$(_explore_contract_collection_value "$prompt" "$field")
        ;;
      *)
        value=$(_explore_contract_value "$prompt" "$field")
        ;;
    esac
    if [[ "$field" == "excludes" ]]; then
      if ! _explore_excludes_is_valid "$value"; then
        invalid+=("${field}:empty_or_placeholder")
      fi
    elif [[ "$field" == "paths" || "$field" == "questions" ]]; then
      if ! _explore_collection_has_substantive_content "$value"; then
        invalid+=("${field}:empty_or_placeholder")
      fi
    elif _explore_value_is_placeholder "$value" ||
         { [[ "$field" == "stop_when" ]] && ! _explore_collection_has_substantive_content "$value"; }; then
      invalid+=("${field}:empty_or_placeholder")
    fi
  done

  local alias_label aliases
  for alias_label in worktree_path branch head; do
    case "$alias_label" in
      worktree_path) aliases="worktree_path worktree_root" ;;
      branch) aliases="branch worktree_branch" ;;
      head) aliases="head worktree_head" ;;
    esac
    count=$(_explore_contract_occurrence_count "$prompt" $aliases)
    if (( count > 1 )); then
      invalid+=("${alias_label}:duplicate")
    fi
  done

  for field in detached_readonly_reason repo_wide_override_reason; do
    count=$(_explore_contract_occurrence_count "$prompt" "$field")
    if (( count > 1 )); then
      invalid+=("${field}:duplicate")
    fi
  done

  if (( ${#invalid[@]} > 0 )); then
    local invalid_csv
    invalid_csv=$(IFS=,; printf '%s' "${invalid[*]}")
    _block_explore_contract "required=${invalid_csv}" "$(_explore_contract_present_keys "$prompt")"
    return 0
  fi

  local expected_count budget_class
  expected_count=$(_explore_contract_value "$prompt" expected_count)
  budget_class=$(_explore_contract_value "$prompt" budget_class)
  if [[ ! "$expected_count" =~ ^[1-4]$ ]]; then
    _block_explore_contract "expected_count=${expected_count} expected_integer=1-4"
    return 0
  fi
  case "$budget_class" in
    focused|standard|broad) ;;
    *)
      _block_explore_contract "budget_class=${budget_class} expected=focused|standard|broad"
      return 0
      ;;
  esac

  local paths_value
  paths_value=$(_explore_contract_collection_value "$prompt" paths)
  case "$(printf '%s' "$paths_value" | tr '[:upper:]' '[:lower:]')" in
    "all"|"everything"|"anywhere"|"broad"|"[all]"|"[everything]"|"[anywhere]"|"[broad]"|'["all"]'|'["everything"]'|'["anywhere"]'|'["broad"]')
      _append_agent_context "[explore-contract-warn] paths の範囲が曖昧。広い scope は具体的な path で明示する"
      ;;
  esac

  if printf '%s\n' "$paths_value" | grep -qE '^[[:space:]]*(\[[[:space:]]*["'\'']?(\.|\*|\*\*/\*)/?["'\'']?[[:space:]]*\]|["'\'']?(\.|\*|\*\*/\*)/?["'\'']?)[[:space:]]*$'; then
    local repo_wide_reason
    repo_wide_reason=$(_explore_contract_value "$prompt" repo_wide_override_reason)
    if _explore_value_is_placeholder "$repo_wide_reason"; then
      _block_explore_contract "repo_wide_override_reason missing_or_placeholder"
      return 0
    fi
  fi

  local target_path branch head
  target_path=$(_explore_contract_value "$prompt" worktree_path)
  [[ -n "$target_path" ]] || target_path=$(_explore_contract_value "$prompt" worktree_root)
  branch=$(_explore_contract_value "$prompt" branch)
  [[ -n "$branch" ]] || branch=$(_explore_contract_value "$prompt" worktree_branch)
  head=$(_explore_contract_value "$prompt" head)
  [[ -n "$head" ]] || head=$(_explore_contract_value "$prompt" worktree_head)

  local identity_missing=""
  _explore_value_is_placeholder "$target_path" && identity_missing="worktree_path"
  _explore_value_is_placeholder "$branch" && identity_missing="${identity_missing:+${identity_missing},}branch"
  _explore_value_is_placeholder "$head" && identity_missing="${identity_missing:+${identity_missing},}head"
  if [[ -n "$identity_missing" ]]; then
    _block_explore_target_anchor "missing_or_placeholder=${identity_missing}"
    return 0
  fi

  local reason_missing=""
  if [[ "$branch" == "detached-readonly" ]]; then
    local detached_reason
    detached_reason=$(_explore_contract_value "$prompt" detached_readonly_reason)
    _explore_value_is_placeholder "$detached_reason" && reason_missing="detached_readonly_reason"
  fi
  if printf '%s\n' "$prompt" | grep -qiE 'repo[-_ ]wide'; then
    local repo_wide_reason
    repo_wide_reason=$(_explore_contract_value "$prompt" repo_wide_override_reason)
    if _explore_value_is_placeholder "$repo_wide_reason"; then
      reason_missing="${reason_missing:+${reason_missing},}repo_wide_override_reason"
    fi
  fi
  if [[ -n "$reason_missing" ]]; then
    GUARD_CLASS="Forbidden"
    MESSAGE="${ICON_CRITICAL} Explore contract reason missing: ${reason_missing} (agents/explore-agent.md 「Prompt contract」)"
    return 0
  fi

  if [[ "$target_path" != /* || ! -d "$target_path" ]]; then
    _block_explore_target_anchor "worktree_path not_absolute_or_missing=${target_path}"
    return 0
  fi

  local actual_root actual_branch actual_head
  if ! actual_root=$(git -C "$target_path" rev-parse --show-toplevel 2>/dev/null); then
    _block_explore_target_anchor "worktree_path is not a git root=${target_path}"
    return 0
  fi
  if ! actual_head=$(git -C "$target_path" rev-parse HEAD 2>/dev/null); then
    _block_explore_target_anchor "HEAD unavailable at=${target_path}"
    return 0
  fi
  actual_branch=$(git -C "$target_path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)

  local declared_root
  if ! declared_root=$(cd "$target_path" 2>/dev/null && pwd -P); then
    _block_explore_target_anchor "worktree_path cannot be resolved=${target_path}"
    return 0
  fi
  actual_root=$(cd "$actual_root" 2>/dev/null && pwd -P) || {
    _block_explore_target_anchor "git root cannot be resolved=${actual_root}"
    return 0
  }
  local mismatch=""
  [[ "$declared_root" == "$actual_root" ]] || mismatch="worktree_path expected=${declared_root} actual_root=${actual_root}"
  if [[ "$branch" == "detached-readonly" ]]; then
    [[ -z "$actual_branch" ]] || mismatch="${mismatch:+${mismatch}; }branch expected=detached-readonly actual=${actual_branch}"
  else
    [[ "$branch" == "$actual_branch" ]] || mismatch="${mismatch:+${mismatch}; }branch expected=${branch} actual=${actual_branch:-DETACHED}"
  fi
  [[ "$head" == "$actual_head" ]] || mismatch="${mismatch:+${mismatch}; }head expected=${head} actual=${actual_head}"

  if [[ -n "$mismatch" ]]; then
    GUARD_CLASS="Forbidden"
    MESSAGE="${ICON_CRITICAL} Explore Target Anchor Gate mismatch: ${mismatch}。対象を再 preflight し、同じ Agent を resume せず fresh-launch する"
    return 0
  fi

  local anchors=() anchor_origins=()
  local anchor anchor_origin
  while IFS=$'\t' read -r anchor anchor_origin; do
    [[ -n "$anchor" ]] || continue
    anchors+=("$anchor")
    anchor_origins+=("$anchor_origin")
  done < <(_explore_anchor_values "$prompt")

  # 違反は 1 件ずつ返さず全件集約して 1 回で block する。200 行級の prompt を
  # 違反数ぶん再送させた実害があるため (2026-08-23)、書き直し 1 回で通る情報を出す
  local violations=() trimmed
  if (( ${#anchors[@]} < 1 || ${#anchors[@]} > 3 )); then
    violations+=("anchor_evidence count=${#anchors[@]} expected=1-3")
  fi
  local idx
  for idx in "${!anchors[@]}"; do
    anchor="${anchors[$idx]}"
    if _explore_value_is_placeholder "$anchor"; then
      violations+=("placeholder anchor (anchor: ${anchor})")
      continue
    fi
    _explore_validate_anchor "$anchor" "$actual_root" && continue
    trimmed="${anchor%%[[:space:]]*}"
    if [[ -n "$trimmed" && "$trimmed" != "$anchor" ]]; then
      _explore_validate_anchor "$trimmed" "$actual_root" && continue
    fi
    violations+=("$(_explore_anchor_violation "$_EXPLORE_ANCHOR_DETAIL" "$anchor" "${anchor_origins[$idx]}")")
  done
  if (( ${#violations[@]} > 0 )); then
    local joined
    joined=$(printf '%s; ' "${violations[@]}")
    _block_explore_target_anchor "${joined%; }"
    return 0
  fi
}

# ====================================
# Task/Agent tool 分岐ハンドラ (pre-tool-use.sh "Task"|"Agent" case から分離)
# Claude Code 2.1.152+ で Task tool は Agent に rename された (両 name で発火)
# 引数: INPUT (stdin JSON) / TOOL_NAME / SESSION_ID
# GUARD_CLASS / MESSAGE / ADDITIONAL_CONTEXT はグローバル変数として設定する
# ====================================
_handle_task_agent_tool() {
  local INPUT="$1"
  local TOOL_NAME="$2"
  local SESSION_ID="$3"

  GUARD_CLASS="Safe"
  # エージェント起動はSafe（実際の操作は各エージェント内で判定）
  # ただし general-purpose は CLAUDE.md「絶対禁止」最大コスト源 → hard block (GP_BLOCK_OFF=1 で warn に緩和)
  local SUBAGENT_TYPE
  SUBAGENT_TYPE=$(jq -r '.tool_input.subagent_type // empty' <<< "$INPUT")

  # 並列判定 self-review (session 1 回のみ inject、同一 session 内の Task 連発による重複を抑制)
  local PARALLEL_REVIEW=""
  local _PR_NL=""
  local _PR_TODAY=""; printf -v _PR_TODAY '%(%Y%m%d)T' -1
  local _PARALLEL_REVIEW_FLAG
  _PARALLEL_REVIEW_FLAG="/tmp/claude-parallel-review-$(_stable_session_key)-${_PR_TODAY}"
  if [[ ! -f "${_PARALLEL_REVIEW_FLAG}" ]]; then
    PARALLEL_REVIEW=$'【並列 self-review (強制 echo、default=並列/委譲)】\n0. default: 並列発火 + Sonnet 委譲。単発・inline 選択時は「なぜ並列/委譲しないか」を 1 行 echo。迷ったら並列・委譲側\n1. Manager 経由は formula_trace、直接 Task は judgment 行を echo (書式: references/PARALLEL-PATTERNS.md)\n2. 独立 task ≥2 なら 1 message に N 個 Agent を並べる (逐次発火だと peak=1)\n3. echo 抜けは under-parallel risk'
    _PR_NL=$'\n'
    touch "${_PARALLEL_REVIEW_FLAG}" 2>/dev/null || true
  fi

  # parent 事前準備 missing 検出 (warn-only、block しない)
  local TASK_PROMPT
  TASK_PROMPT=$(jq -r '.tool_input.prompt // empty' <<< "$INPUT")

  # developer-agent fire 時、prompt Section 1 touchable_files YAML から allowlist 抽出 →
  # state file に write。subagent 内 Edit/Write の literal match check に使う
  if [ "${SUBAGENT_TYPE}" = "developer-agent" ] && [ -n "$TASK_PROMPT" ]; then
    local _TF_LIST
    _TF_LIST=$(_touchable_extract_from_prompt "$TASK_PROMPT")
    if [ -n "$_TF_LIST" ]; then
      # mapfile alternative for old bash: read into array
      local _TF_PATHS=()
      local _line
      while IFS= read -r _line; do
        [ -n "$_line" ] && _TF_PATHS+=("$_line")
      done <<< "$_TF_LIST"
      _touchable_write "$SESSION_ID" "${_TF_PATHS[@]}"
    fi
  fi

  local PREP_WARN=""
  if _check_parent_prep_missing "$TASK_PROMPT"; then
    PREP_WARN="
【parent 事前準備 missing 疑い】≥500 word の prompt に target / file:line / verify / DoD いずれも未出現。委譲前 checklist を充足してから発火 (references/developer-agent-delegation-prompt.md Section 0)"
  fi
  if _check_colloquial_trigger_missing_delegation "$TASK_PROMPT"; then
    PREP_WARN="${PREP_WARN}
【colloquial 起動検出】口語トリガー (お任せ/全部/改善して 等) + file:line 未明示。inline throttle に注意、複数 task 列挙なら 1 message 内 N tool_use 並列発火を確認"
  fi

  if [ "${SUBAGENT_TYPE}" = "general-purpose" ]; then
    # CLAUDE.md「absolutely banned」最大コスト源 (実測 max 501s) → hard block。
    # GP_BLOCK_OFF=1 で従来の warn 据え置き (hook debug 用 escape hatch)
    if [ "${GP_BLOCK_OFF:-0}" = "1" ]; then
      GUARD_CLASS="Boundary"
      MESSAGE="${ICON_WARNING} general-purpose agent（CLAUDE.md「原則使わない」、最大コスト源）"
      ADDITIONAL_CONTEXT="代替: claude-code-guide / Explore / 直接 grep+find / serena MCP（references/performance-insights.md 参照）${_PR_NL}${PARALLEL_REVIEW}${PREP_WARN}"
    else
      GUARD_CLASS="Forbidden"
      MESSAGE="${ICON_CRITICAL} general-purpose agent は禁止 (CLAUDE.md、最大コスト源 実測 max 501s)。代替: explore-agent (検索) / claude-code-guide (CLI/SDK) / developer-agent (実装)"
    fi
  elif [ -z "${SUBAGENT_TYPE}" ]; then
    # subagent_type 未指定は general-purpose bypass と同等 → hard block。
    # SUBTYPE_EMPTY_BLOCK_OFF=1 で warn-only に降格 (hook debug 用 escape hatch)
    if [ "${SUBTYPE_EMPTY_BLOCK_OFF:-0}" = "1" ]; then
      GUARD_CLASS="Boundary"
      MESSAGE="${ICON_WARNING} subagent_type 未指定の Task (CLAUDE.md「subagent_type must be explicit」)"
      ADDITIONAL_CONTEXT="代替: explore-agent (検索) / claude-code-guide (CLI/SDK) / developer-agent (実装)${_PR_NL}${PARALLEL_REVIEW}${PREP_WARN}"
    else
      GUARD_CLASS="Forbidden"
      MESSAGE="${ICON_CRITICAL} subagent_type 未指定の Task は禁止 (CLAUDE.md「subagent_type must be explicit on every Task call」)。代替: explore-agent (検索) / claude-code-guide (CLI/SDK) / developer-agent (実装)"
    fi
  else
    ADDITIONAL_CONTEXT="${PARALLEL_REVIEW}${PREP_WARN}"
  fi

  case "${SUBAGENT_TYPE,,}" in
    "explore"|"explore-agent")
      _validate_explore_prompt_contract "$TASK_PROMPT"
      ;;
  esac

  # 逐次 Agent fire 検出 (warn-only、既存 ADDITIONAL_CONTEXT に append)
  _check_sequential_agent_fire "$SESSION_ID"

  # bundle 違反検出 (warn-only): developer-agent 限定で逐次発火を検出
  # work-context-20260618 next-action #1 / Gate A 衰弱点補強
  # /flow step 7 では Task(developer-agent)×N を 1 message bundle 必須
  # 連続発火 (>_TH_PARALLEL_WINDOW_NS) ≥2 回 = bundle 違反 = parentUuid serial chain
  # prompt を渡して serial_reason: 宣言 (依存 chain の逐次発火) を counter 対象外にする
  if [ "${SUBAGENT_TYPE}" = "developer-agent" ]; then
    _check_developer_agent_bundle_violation "$SESSION_ID" "$TASK_PROMPT"
  fi
}
