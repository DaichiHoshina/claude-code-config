#!/usr/bin/env bash
# trigger 判定系 (外向き文書 / 委譲 / NG語 pre-sweep trigger) - user-prompt-submit.sh から抽出
# 多重 source 防止
if [[ "${_PROMPT_TRIGGER_DETECTORS_LOADED:-}" == "1" ]]; then
    return 0
fi
_PROMPT_TRIGGER_DETECTORS_LOADED=1

# === 外向き執筆 trigger 語彙 (single source of truth) ===
# _OUTWARD_SHARE_TRIGGERS: 共有/報告 phrase subset。chat 応答にも外向き規範を適用する trigger。
# _OUTWARD_EXTRA_TRIGGERS: 文書種別 + 動作動詞 (外向き文書 trigger の残り部分、subset の superset を構成)。
# 論理: _is_outward_writing_trigger = SHARE ∪ EXTRA、_inject_outward_mode_if_trigger = SHARE
readonly _OUTWARD_SHARE_TRIGGERS=(
  "共有用" "報告用" "共有して" "報告して" "共有文" "報告文"
  "共有テキスト" "報告書" "共有する文" "報告する内容"
)
readonly _OUTWARD_EXTRA_TRIGGERS=(
  "プルリク" "commit" "コミット" "push" "issue" "slack" "notion"
  "design doc" "デザインドック" "設計書" "prd" "rca" "障害報告" "ポストモーテム" "postmortem"
  "/git-push" "/commit" "/post-comment" "/sdd-design" "/prd" "/docs"
  "ドラフト" "下書き"
)

# === 共有/報告系 trigger → outward-mode inject ===
# user 入力に共有/報告系 phrase が含まれる場合、chat 応答にも外向き規範を適用するよう inject
_inject_outward_mode_if_trigger() {
  local prompt="$1"
  [[ "${CLAUDE_WRITING_CONTEXT_INJECTION:-0}" == "1" ]] || return 1
  local t
  for t in "${_OUTWARD_SHARE_TRIGGERS[@]}"; do
    if [[ "$prompt" == *"$t"* ]]; then
      printf '%s\n' "[jp-quality-outward-mode] 共有する文章では、入力の事実・時制・因果関係・主体・書き手の評価を保つ。user が求めていない規則名・採点・書き直し工程は本文に出さない。source: guidelines/writing/PRINCIPLES.md"
      return 0
    fi
  done
  return 1
}

# === delegation trigger → developer-agent Section 0 checklist + scope allowlist inject ===
# 委譲意図 keyword 検出時に parent 向け checklist を additionalContext として注入する。
# 目的: scope creep / 直列 chain / verify 省略 / Gate 未検出 の構造的予防。
# throttle: session 1 回のみ (flag: /tmp/claude-deleg-checklist-<sid>-<date>)
_inject_delegation_checklist_if_trigger() {
  local prompt="$1"
  local session_id="$2"
  local date_today="$3"
  local prompt_lower="${prompt,,}"

  # 委譲意図 keyword (実装 / 修正 / 編集 / refactor / dev 委譲 / Task(developer 等)
  # 質問形 (どう / 教えて / なぜ) は skip、調査 / explore は別 agent 経路
  local question_re='(どう思う|どう考え|教えて|なぜ|どうやって|どうすれ|意見|相談)'
  [[ "${prompt_lower}" =~ ${question_re} ]] && return 1

  local trigger_re='(実装|修正|編集|リファクタ|refactor|impl|fix bug|developer-agent|task\(developer|/dev |/flow|並列で|並列に|分担で|分担して)'
  [[ "${prompt_lower}" =~ ${trigger_re} ]] || return 1

  # throttle: session 1 回 inject 済ならスキップ
  [[ -n "${session_id}" && "${session_id}" != "unknown" ]] || return 1
  local _FLAG="/tmp/claude-deleg-checklist-${session_id}-${date_today}"
  if [[ -f "${_FLAG}" ]]; then
    return 1
  fi

  touch "${_FLAG}" 2>/dev/null || true

  printf '%s\n' "[delegation-checklist] developer-agent 委譲意図検出。発火前に Section 0 checklist 7 項目を満たすこと: (1) target file:line 特定済 (2) verify cmd bash literal 確定 (3) DoD 1 行化 (4) 単 domain (5) touchable_files: YAML block を delegation prompt Section 1 に literal 記載 (6) blocker-on-stop 方針記載 (7) Self-Review Gate 明示。touchable_files 欠落で発火 = subagent 側 partial 停止。Return 時は Section 0.5 B fact-check (数値 formula 確認 / 測定値 1 sample 再現 / file 変更 git diff --stat) を最低 1 つ実行。source: references/developer-agent-delegation-prompt.md Section 0, Section 0.5, Section 1"
  return 0
}

# === 外向き text trigger → NG top-N term inject ===
# commit / PR / Notion / Slack 等の外向き text 生成前に block top-N term を注入して retry loop を事前回避する
# 派生値禁止 rule 準拠: top-N は log から動的抽出 (literal 埋め込み禁止)
_inject_commit_ng_top6_if_trigger() {
  local prompt="$1"
  local prompt_lower="${prompt,,}"
  # commit/PR 系 + Notion/Slack 等の外向き投稿系 (2026-06-24: NG block 30+ 件/日対応で拡大)
  local triggers=(
    "push" "pushして" "commit" "/git-push" "/commit" "pr 作" "pr を作" "プルリク"
    "notion" "slack" "投稿" "送って" "送信" "share" "シェア" "/post-comment"
  )
  local hit=0
  local t
  for t in "${triggers[@]}"; do
    if [[ "${prompt_lower}" == *"${t,,}"* ]]; then hit=1; break; fi
  done
  (( hit )) || return 1

  # throttle: 同一 session で 300 秒以内の再 inject を抑制する (delegation checklist と同 pattern)。
  # inject は会話 history に残り以降の全 turn で再送されるため、dedup なしだと 1 日 100 回超の重複が発生した (2026-07-03 実測 117 回)
  local _NG_FLAG="/tmp/claude-ng-topn-${_SESSION_ID:-$$}-${_DATE_TODAY:-0}"
  if [[ -f "${_NG_FLAG}" ]]; then
    local _NG_LAST _NG_NOW _NG_SINCE
    read -r _NG_LAST < "${_NG_FLAG}" 2>/dev/null || _NG_LAST=""
    if [[ ! "${_NG_LAST}" =~ ^[0-9]+$ ]] || (( _NG_LAST == 0 )); then
      return 1
    fi
    printf -v _NG_NOW '%(%s)T' -1
    _NG_SINCE=$(( _NG_NOW - _NG_LAST ))
    if (( _NG_SINCE >= 0 && _NG_SINCE < 300 )); then
      return 1
    fi
  fi
  local _NG_NOW_TS
  printf -v _NG_NOW_TS '%(%s)T' -1
  printf '%s\n' "${_NG_NOW_TS}" > "${_NG_FLAG}" 2>/dev/null || true

  local _LOG="${HOME}/.claude/logs/jp-quality-block.log"
  [[ -f "${_LOG}" ]] || return 1
  # log-rotation.sh は caller (user-prompt-submit.sh) 側 source 前提。単体 source 時は skip
  declare -f _rotate_log_if_needed >/dev/null && _rotate_log_if_needed "${_LOG}"

  # ISO8601 timestamp は辞書順 = 時系列順。bash 側で cutoff 文字列を 1 回生成し、
  # awk 内で文字列比較するだけにして date fork を完全に排除する
  local _NOW _CUTOFF_STR
  printf -v _NOW '%(%s)T' -1
  printf -v _CUTOFF_STR '%(%Y-%m-%dT%H:%M:%S)T' "$(( _NOW - 604800 ))"

  # top-N (拡大: 6 → 12) で日々の block 多様性をカバー
  local _TOP
  _TOP=$(awk -F'|' -v cutoff="${_CUTOFF_STR}" '
    $4 ~ /block/ {
      if (substr($1,1,19) >= cutoff) {
        term = $3
        gsub(/^ +| +$/, "", term)
        if (term != "") count[term]++
      }
    }
    END {
      for (k in count) print count[k], k
    }' "${_LOG}" 2>/dev/null | sort -rn | head -12 | awk '{$1=""; sub(/^ /,""); print}' | paste -sd "," -)

  [[ -n "${_TOP}" ]] || return 1
  printf '%s\n' "[outward-text-ng-pre-sweep] 外向き text (commit/PR/Notion/Slack 等) trigger 検出。直近7日 block top-12: ${_TOP}。draft 生成前に必ず self-check + 回避。代替例: 鑑みる→踏まえる / 踏襲→引き継ぐ / 喫緊→直近 / leverage→使う / utilize→活かす / mitigate→緩和する。source: ~/.claude/logs/jp-quality-block.log"

  # inject 効果計測用 log (誰 trigger / どの hit term / top-N)
  local _SWEEP_LOG="${HOME}/.claude/logs/ng-pre-sweep-inject.log"
  _rotate_log_if_needed "${_SWEEP_LOG}"
  local _TS_INJ
  printf -v _TS_INJ '%(%Y-%m-%dT%H:%M:%S)T' -1
  printf '%s | user-prompt | trigger=%s | top12=%s\n' "$_TS_INJ" "${t}" "${_TOP}" \
    >> "$_SWEEP_LOG" 2>/dev/null || true
  return 0
}

# === chat self-check 強制 trigger (turn 締め語 / 括弧詰め込み 反復 signal。100 字超文は 2026-08-28 に廃止) ===
# 直前 assistant turn の stop.sh warn state file に構造 signal があり、
# かつ直近 24h の jp-quality-block.log にも同種 signal が反復している (単発誤爆除外) 場合、
# 次 turn 頭に強い self-check 指示を注入する。
# 背景: rule 記述だけでは適用されず (7日 warn 424件)、生成前 self-check hook 強制が必要 (2026-07-17 retrospective A案)。
# throttle: 同一 session で 300 秒以内の再 inject を抑制 (_inject_commit_ng_top6_if_trigger と同 pattern)
_inject_chat_selfcheck_if_signal() {
  local session_id="$1"
  local date_today="$2"

  [[ "${CLAUDE_WRITING_CONTEXT_INJECTION:-0}" == "1" ]] || return 1
  [[ -n "${session_id}" && "${session_id}" != "unknown" ]] || return 1

  # signal 1: 直前 assistant turn の構造 warn (stop.sh が書く state file)
  local _JPQ_WARN_FILE="/tmp/claude-stop-jpq-warn-${session_id}-${date_today:-0}"
  [[ -f "${_JPQ_WARN_FILE}" ]] || return 1
  grep -qE '(turn締め語文末|括弧詰め込み)' "${_JPQ_WARN_FILE}" 2>/dev/null || return 1

  # signal 2: 直近 24h の log にも同種 signal が反復しているか (単発誤爆除外)
  local _LOG="${HOME}/.claude/logs/jp-quality-block.log"
  [[ -f "${_LOG}" ]] || return 1
  # log-rotation.sh は caller (user-prompt-submit.sh) 側 source 前提。単体 source 時は skip
  declare -f _rotate_log_if_needed >/dev/null && _rotate_log_if_needed "${_LOG}"
  local _SC_NOW _SC_CUTOFF_STR
  printf -v _SC_NOW '%(%s)T' -1
  printf -v _SC_CUTOFF_STR '%(%Y-%m-%dT%H:%M:%S)T' "$(( _SC_NOW - 86400 ))"
  local _SC_RECENT_HITS
  _SC_RECENT_HITS=$(awk -F'|' -v cutoff="${_SC_CUTOFF_STR}" '
    $0 ~ /(turn締め語文末|括弧詰め込み)/ && substr($1,1,19) >= cutoff { c++ } END { print c+0 }
  ' "${_LOG}" 2>/dev/null) || _SC_RECENT_HITS=0
  (( _SC_RECENT_HITS >= 2 )) || return 1

  # throttle: 300 秒 dedup
  local _SC_FLAG="/tmp/claude-chat-selfcheck-${session_id}-${date_today:-0}"
  if [[ -f "${_SC_FLAG}" ]]; then
    local _SC_LAST _SC_SINCE
    read -r _SC_LAST < "${_SC_FLAG}" 2>/dev/null || _SC_LAST=""
    if [[ "${_SC_LAST}" =~ ^[0-9]+$ ]] && (( _SC_LAST != 0 )); then
      _SC_SINCE=$(( _SC_NOW - _SC_LAST ))
      if (( _SC_SINCE >= 0 && _SC_SINCE < 300 )); then
        return 1
      fi
    fi
  fi
  printf '%s\n' "${_SC_NOW}" > "${_SC_FLAG}" 2>/dev/null || true

  printf '%s\n' "[chat-selfcheck] 送信前に、事実・時制・因果関係・主体・書き手の評価を変えていないか確認する。機械検出は確認箇所を探す補助に留め、語尾や文長の数値だけを理由に書き換えない"
  return 0
}

# === 外向き文書 trigger 判定 (外向き文書品質 + 断定語注意 の発火条件) ===
# 永続化文書を作成する意図を広めに検出。hit 時のみ [外向き文書品質] / [断定語注意] を注入し、
# 毎-turn 固定費を削る。trigger を取りこぼした場合も pre-tool-use.sh の hook block が最終防壁
_is_outward_writing_trigger() {
  local prompt="$1"
  local prompt_lower="${prompt,,}"
  # 文書種別 + 動作動詞。大小文字非依存 (lower 比較)。
  # 単独の "pr" は improve/express/approach/compress/spring 等の英単語に部分一致で誤爆するため
  # 配列に入れず、語境界判定 (後述) で別扱いする。
  # trigger 語彙は file 冒頭の SHARE ∪ EXTRA を union で走査 (single source of truth)
  local t
  for t in "${_OUTWARD_SHARE_TRIGGERS[@]}" "${_OUTWARD_EXTRA_TRIGGERS[@]}"; do
    if [[ "${prompt_lower}" == *"${t,,}"* ]]; then return 0; fi
  done
  # "pr" は語境界 (前後が非英数字 or 行頭行末) のときのみ hit
  if [[ "${prompt_lower}" =~ (^|[^a-z0-9])pr([^a-z0-9]|$) ]]; then return 0; fi
  return 1
}

# === NG 語の指定 (「X も禁止にして」等) 検出 → 候補を log に記録し、登録手順を inject ===
# user が chat で語を禁止と言った turn に、候補語を ~/.claude/logs/ng-candidates.log へ書き、
# その turn で NG-DICTIONARY.md へ登録する手順 (references/on-demand-rules/ng-word-register.md) を注入する。
# 短い発話 (80 字以内) に限り、辞書に既にある語は inject の対象にしない (log には registered と書く)
_inject_ng_word_capture_if_trigger() {
  local prompt="$1"
  [[ -n "${prompt}" ]] || return 1
  (( ${#prompt} <= 80 )) || return 1
  local _last_file="${HOME}/.claude/logs/.ng-capture-last"
  local _now _last=0
  printf -v _now '%(%s)T' -1
  if [[ "${prompt}" =~ (禁止|ダメ|NG語|NG\ 語|使うな|使わないで) ]]; then
    :
  elif (( ${#prompt} <= 12 )) && [[ "${prompt}" =~ (も|とか)$ ]] && [[ -f "${_last_file}" ]]; then
    # 直前 10 分以内に検出があった直後の短い続き (「あと X とか」「Y も」の形) も候補にする
    read -r _last < "${_last_file}" 2>/dev/null || _last=0
    [[ "${_last}" =~ ^[0-9]+$ ]] || return 1
    (( _now - _last < 600 )) || return 1
  else
    return 1
  fi

  local s="${prompt}"
  local _w
  for _w in 'にして' '禁止' 'これも' 'これは' 'ダメやろ' 'ダメ' 'NG語' 'NG 語' '使うな' '使わないで' 'やろ' 'あと' 'とか' 'して' 'ください' 'です' 'ね' '！' '!' '、' '。' '「' '」' '　'; do
    s="${s//${_w}/ }"
  done

  local -a _toks=()
  local _t _blen
  for _t in ${s}; do
    _t="${_t%も}"
    _t="${_t%は}"
    [[ -n "${_t}" ]] || continue
    (( ${#_t} >= 1 && ${#_t} <= 8 )) || continue
    _blen=$(LC_ALL=C; printf '%s' "${#_t}")
    (( _blen > ${#_t} )) || continue
    _toks+=("${_t}")
  done
  (( ${#_toks[@]} > 0 )) || return 1
  printf '%s\n' "${_now}" > "${_last_file}" 2>/dev/null || true

  local _dict="${HOME}/.claude/guidelines/writing/NG-DICTIONARY.md"
  local _log="${HOME}/.claude/logs/ng-candidates.log"
  mkdir -p "${_log%/*}" 2>/dev/null || true
  local _ts
  printf -v _ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1
  # 辞書の (block) 行の語を集め、token がその語を含めば登録済みとみなす (「畳」1 文字登録に「畳んだ」が当たる)
  local -a _terms=()
  local _line _term
  if [[ -f "${_dict}" ]]; then
    while IFS= read -r _line; do
      [[ "${_line}" =~ ^\*\*[^*]*\(block\)\*\*:\ (.*)$ ]] || continue
      _line="${BASH_REMATCH[1]}"
      while [[ "${_line}" == *" / "* ]]; do
        _term="${_line%% / *}"
        _line="${_line#* / }"
        [[ -n "${_term}" ]] && _terms+=("${_term}")
      done
      [[ -n "${_line}" ]] && _terms+=("${_line}")
    done < "${_dict}"
  fi
  local -a _new=()
  local _st
  for _t in "${_toks[@]}"; do
    _st="new"
    for _term in "${_terms[@]}"; do
      if [[ "${_t}" == *"${_term}"* ]]; then
        _st="registered"
        break
      fi
    done
    if [[ "${_st}" == "new" ]]; then
      _new+=("${_t}")
    fi
    printf '%s | %s | %s\n' "${_ts}" "${_t}" "${_st}" >> "${_log}" 2>/dev/null || true
  done
  # log-rotation.sh は caller (user-prompt-submit.sh) 側 source 前提。単体 source 時は skip
  declare -f _rotate_log_if_needed >/dev/null && _rotate_log_if_needed "${_log}"
  (( ${#_new[@]} > 0 )) || return 1

  local _joined
  _joined=$(IFS=/; printf '%s' "${_new[*]}")
  printf '[NG語登録] user が禁止語を指定した: %s。この turn の作業の前に references/on-demand-rules/ng-word-register.md の手順で NG-DICTIONARY.md へ登録する (category と活用形の判断 → fixture と bats → 既存使用箇所の言い換え → sync → lint で実物確認)。候補は ~/.claude/logs/ng-candidates.log に記録済み\n' "${_joined}"
  return 0
}
