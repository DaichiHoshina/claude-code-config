#!/usr/bin/env bash

_ss_maybe_reexec_bash() {
    if [[ -z "${_JP_HOOK_BASH_UPGRADED:-}" && "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
        for _cand in /opt/homebrew/bin/bash /usr/local/bin/bash; do
            if [[ -x "$_cand" ]]; then
                export _JP_HOOK_BASH_UPGRADED=1
                exec "$_cand" "$0" "$@"
            fi
        done
    fi
}
_ss_maybe_reexec_bash "$@"

# SessionStart Hook - protection-mode + guidelines 自動読み込み
# セッション開始時にSerena memoryリストを確認 + compact-restore読み込み
# NOTE: Serena有無はチェックしない（compact直後はMCP未初期化の可能性あり）

set -euo pipefail

# init_duration 計測: microsec 精度で hook 処理開始時刻を記録 (bash 5.0+ EPOCHREALTIME)
# bash 5+: EPOCHREALTIME 利用 / bash 3-4: fallback (timing 計測無効化)
_ss_start_timer() {
    if (( BASH_VERSINFO[0] >= 5 )); then
        _SS_START_US="${EPOCHREALTIME/./}"
    else
        _SS_START_US=0
    fi
}

_ss_init_logging_and_lib() {
    exec 2>>"$HOME/.claude/logs/hook-errors.log"

    # dirname + cd + pwd の 2 fork → bash parameter expansion に削減
    _ss_src="${BASH_SOURCE[0]}"
    [[ "${_ss_src}" == /* ]] || _ss_src="${PWD}/${_ss_src}"
    SCRIPT_DIR="${_ss_src%/*}"
    source "${SCRIPT_DIR}/../lib/hook-utils.sh"

    # Nerd Fonts icons
    # ICON_* は hook-utils.sh で定義済み
}

# stat コマンドの mtime フラグを先頭で 1 回判定（macOS: -f%m / GNU: -c%Y）
# 各キャッシュ age チェックで dual call していた失敗 fork を排除する
_ss_detect_stat_flag() {
    if stat -c%Y /dev/null >/dev/null 2>&1; then
        _SS_STAT_FLAG="-c%Y"
    else
        _SS_STAT_FLAG="-f%m"
    fi
}

_ss_parse_input() {
    # jq前提条件チェック
    require_jq

    # JSON入力を読み込み、jq 1回で全フィールド取得（v2.2.1 fork削減 / _SS_INPUT 変数廃止）
    eval "$(jq -r '@sh "_SS_SESSION_ID=\(.session_id // "") _CWD=\(.cwd // "") _SS_SOURCE=\(.source // "")"')"
    # stdin JSON が canonical source。env CLAUDE_CODE_SESSION_ID は session 切替時に
    # 前 session 値が leak することがあるため参照しない (incident 2026-06-25)
    _SS_SESSION_ID="${_SS_SESSION_ID:-unknown}"
    _SS_PROJECT=$(basename "${_CWD:-.}")
    # 日付を事前取得してキャッシュ（date fork を hook 起動 1 回に抑える）
    _SS_DATE_TODAY=$(date +%Y%m%d)
}

# git 状態を 1 回だけ取得してキャッシュ（statusline marker + session title ブロックで再利用）
# git fork を 2 回 → 1 回に削減:
# rev-parse --abbrev-ref HEAD は git repo 外で失敗するため --git-dir チェックを兼ねる
_ss_detect_git() {
    _SS_IS_GIT=false
    _SS_GIT_BRANCH=""
    if [[ -n "${_CWD:-}" ]] && [[ -d "${_CWD}" ]]; then
        if _SS_GIT_BRANCH=$(git -C "${_CWD}" rev-parse --abbrev-ref HEAD 2>/dev/null); then
            _SS_IS_GIT=true
        fi
    fi
}

# ====================================
# statusline マーカー初期化
# ====================================
# /tmp/claude-wt-${SESSION_ID}-YYYYMMDD は post-tool-use.sh が cd 検出時に書き込み、
# statusline.js が cwd 解決の優先元として読む。session 開始時に最新の cwd で
# 初期化することで、過去 session で記録された古いマーカーが残存するのを防ぐ
# （例: 同セッションで一時的 cd した後、cd 含まない Bash が続いてマーカーが
# 古いままになるケースの再発防止は別途必要、ここでは session 境界のみ対処）
_ss_init_statusline_marker() {
    if [[ -n "${_SS_SESSION_ID}" && "${_SS_SESSION_ID}" != "unknown" && -n "${_CWD:-}" && -d "${_CWD:-}" ]]; then
      if [[ "${_SS_IS_GIT}" == "true" ]]; then
        _SS_ABS=$(cd "${_CWD}" && pwd)
        echo "${_SS_ABS}" > "/tmp/claude-wt-${_SS_SESSION_ID}-${_SS_DATE_TODAY}"
      fi
    fi
}

# ====================================
# ハーネス自己診断（24時間キャッシュ）
# ====================================
_ss_harness_diagnostics() {
    _HARNESS_WARNINGS=()
    _DIAG_MSG=""
    _DIAG_CACHE="${HOME}/.claude/cache/harness-diag.cache"
    _SETTINGS_FILE="${HOME}/.claude/settings.json"

    # キャッシュが24時間以内なら再利用
    _NEED_DIAG=true
    if [[ -f "${_DIAG_CACHE}" ]]; then
      _CACHE_AGE=$(( EPOCHSECONDS - $(stat ${_SS_STAT_FLAG} "${_DIAG_CACHE}" 2>/dev/null || echo 0) ))
      if [[ ${_CACHE_AGE} -lt 86400 ]]; then
        _DIAG_MSG=$(<"${_DIAG_CACHE}")
        _NEED_DIAG=false
      fi
    fi

    if [[ "${_NEED_DIAG}" == "true" ]]; then
      # 1. 必須hookファイルの存在・実行権限チェック
      for _hook in pre-tool-use.sh post-tool-use.sh permission-denied.sh session-start.sh stop.sh stop-failure.sh; do
        _hook_path="${SCRIPT_DIR}/${_hook}"
        if [[ ! -f "${_hook_path}" ]]; then
          _HARNESS_WARNINGS+=("hook missing: ${_hook}")
        elif [[ ! -x "${_hook_path}" ]]; then
          _HARNESS_WARNINGS+=("hook not executable: ${_hook}")
        fi
      done

      # 2. 必須libファイルの存在チェック
      _LIB_BASE="${SCRIPT_DIR}/../lib"
      for _lib in hook-utils.sh analytics-writer.sh; do
        if [[ ! -f "${_LIB_BASE}/${_lib}" ]]; then
          _HARNESS_WARNINGS+=("lib missing: ${_lib}")
        fi
      done

      # 3. settings.json のhook参照先チェック
      if [[ -f "${_SETTINGS_FILE}" ]]; then
        while IFS= read -r _hook_cmd; do
          # command フィールドは "path arg1 arg2..." 形式があり得る（例: serena-hook.sh activate）。
          # 存在チェックは実行ファイル部分（最初の空白までのトークン）のみ対象
          _hook_path="${_hook_cmd%% *}"
          _expanded="${_hook_path/#\~\//${HOME}/}"
          if [[ ! -f "${_expanded}" ]]; then
            _HARNESS_WARNINGS+=("settings.json hook not found: ${_hook_cmd}")
          elif [[ ! -x "${_expanded}" ]]; then
            _HARNESS_WARNINGS+=("settings.json hook not executable: ${_hook_cmd}")
          fi
        done < <(jq -r '.. | objects | select(.type == "command") | .command // empty' "${_SETTINGS_FILE}" 2>/dev/null)
      fi

      # 診断結果を文字列化 & キャッシュ
      if [[ ${#_HARNESS_WARNINGS[@]} -gt 0 ]]; then
        _DIAG_MSG="${ICON_WARNING} **Harness診断**: ${#_HARNESS_WARNINGS[@]}件の問題検出\n"
        for _w in "${_HARNESS_WARNINGS[@]}"; do
          _DIAG_MSG+="  - ${_w}\n"
        done
      fi
      mkdir -p "$(dirname "${_DIAG_CACHE}")"
      printf '%s' "${_DIAG_MSG}" > "${_DIAG_CACHE}"
    fi
}

# --- 多リポ配下起動ガード（cwd単位 1時間キャッシュ）---
# cwd がリポジトリルートでない（.git 無し）かつ子孫に複数の git リポがある場合、
# git/rg/Glob が全体を舐めに行き体感が極端に遅くなる。個別リポ cd を促す警告。
# glob 走査は重いため cwd ハッシュ単位で 1h キャッシュ化
_ss_check_multi_repo_cwd() {
    _CWD_GUARD_MSG=""
    if [[ -n "${_CWD:-}" ]] && [[ -d "${_CWD}" ]] && [[ ! -d "${_CWD}/.git" ]]; then
      _CWD_SAFE="${_CWD//\//_}"
      _CWD_CACHE="${HOME}/.claude/cache/cwd-multi-repo-${_CWD_SAFE}.cache"
      _CWD_CACHE_HIT=false
      if [[ -f "${_CWD_CACHE}" ]]; then
        _CWD_CACHE_AGE=$(( EPOCHSECONDS - $(stat ${_SS_STAT_FLAG} "${_CWD_CACHE}" 2>/dev/null || echo 0) ))
        if [[ ${_CWD_CACHE_AGE} -lt 3600 ]]; then
          _CWD_GUARD_MSG=$(<"${_CWD_CACHE}")
          _CWD_CACHE_HIT=true
        fi
      fi
      if [[ "${_CWD_CACHE_HIT}" == "false" ]]; then
        _NESTED_REPOS=0
        shopt -s nullglob
        for _git_dir in "${_CWD}"/*/.git "${_CWD}"/*/*/.git "${_CWD}"/*/*/*/.git; do
          if [[ -d "${_git_dir}" ]]; then
            _NESTED_REPOS=$(( _NESTED_REPOS + 1 ))
            [[ ${_NESTED_REPOS} -ge 2 ]] && break
          fi
        done
        shopt -u nullglob
        if [[ "${_NESTED_REPOS}" -ge 2 ]]; then
          _CWD_GUARD_MSG="${ICON_WARNING} **cwd警告**: 複数リポジトリの親ディレクトリで起動中（${_CWD}）。git/rg/Glob が全体を舐めて重くなる。個別リポに cd してから起動推奨\n"
        fi
        mkdir -p "$(dirname "${_CWD_CACHE}")"
        printf '%s' "${_CWD_GUARD_MSG}" > "${_CWD_CACHE}"
      fi
    fi
}

# --- linked worktree で owner CLAUDE.md の path を通知する ---
# linked worktree が org 階層 dir の外にあると owner CLAUDE.md が auto-load されない。
# Claude Code は cwd の祖先 dir にある CLAUDE.md を全部読むので、worktree が org dir の
# 配下 (ai-tools の `<owner>/ai-tools-wt-*` 等) にあるときは auto-load 済で、通知すると誤りになる。
# 以前は全文 inject して first-ctx を毎回 5-10 KB 消費していたので、2026-07-23 に path 通知だけに切り替えた。
# owner cache も同時に廃止した。Claude は作業開始時に該当 path を明示 Read して org 規範を反映する
_ss_check_worktree_owner() {
    _WT_OWNER_MSG=""
    if [[ "${_SS_IS_GIT}" == "true" ]] && [[ -n "${_CWD:-}" ]]; then
      _WT_OWNER_CLAUDE="$(_resolve_worktree_owner_claude_md "${_CWD}" 2>/dev/null || true)"
      # owner 側は git rev-parse 由来の実体 path なので、cwd も pwd -P で実体に合わせてから祖先判定する
      _WT_CWD_REAL="$(cd "${_CWD}" 2>/dev/null && pwd -P || printf '%s' "${_CWD}")"
      if [[ -n "${_WT_OWNER_CLAUDE}" ]] && [[ -f "${_WT_OWNER_CLAUDE}" ]] \
         && [[ "${_WT_CWD_REAL%/}/" != "$(dirname "${_WT_OWNER_CLAUDE}")/"* ]]; then
        _WT_OWNER_MSG="${ICON_WARNING} **linked worktree で作業中**: org 階層の owner CLAUDE.md \`${_WT_OWNER_CLAUDE}\` は org 階層 dir の外にあるため auto-load されない。作業開始前に明示 Read して org 規範を反映する。\n"
      fi
    fi
}

# NOTE: project-scope .mcp.json 自動再生成は user-scope MCP 登録に移行したため撤去
# (2026-06-17)。Serena MCP は ~/.claude.json の mcpServers で --project-from-cwd 起動

# --- Worktree Memory Symlink（バックグラウンド実行）---
# symlink 操作のみで出力に依存しないため非同期化
_ss_start_worktree_memory_link_bg() {
    ( ensure_worktree_memory_link "${_CWD:-}" 2>/dev/null || true ) &
}

# --- Analytics: セッション開始記録 ---
# init_duration_ms は analytics_start_session 呼び出し直前で確定する
# （その後の処理 = dir-color / 出力組み立て は analytics 対象外）
_ss_record_session_analytics() {
    if (( BASH_VERSINFO[0] >= 5 && _SS_START_US > 0 )); then
        _SS_DURATION_MS=$(( (${EPOCHREALTIME/./} - _SS_START_US) / 1000 ))
    else
        _SS_DURATION_MS=0
    fi

    # session-init-timing.log に append（session-end.sh がここから直近 duration を参照）
    _SS_TIMING_LOG="${HOME}/.claude/logs/session-init-timing.log"
    mkdir -p "$(dirname "${_SS_TIMING_LOG}")"
    # plugin count: 24h cache で jq fork 削減
    _SS_PLUGIN_CACHE="${HOME}/.claude/cache/plugin-count.cache"
    _SS_PLUGIN_COUNT=0
    _SS_PLUGIN_CACHE_HIT=false
    if [[ -f "${_SS_PLUGIN_CACHE}" ]]; then
      _SS_PLUGIN_CACHE_AGE=$(( EPOCHSECONDS - $(stat ${_SS_STAT_FLAG} "${_SS_PLUGIN_CACHE}" 2>/dev/null || echo 0) ))
      if [[ ${_SS_PLUGIN_CACHE_AGE} -lt 86400 ]]; then
        _SS_PLUGIN_COUNT=$(<"${_SS_PLUGIN_CACHE}")
        _SS_PLUGIN_CACHE_HIT=true
      fi
    fi
    if [[ "${_SS_PLUGIN_CACHE_HIT}" == "false" ]]; then
      _SS_PLUGIN_COUNT=$(jq '.enabledPlugins | length' "${HOME}/.claude/settings.json" 2>/dev/null || echo 0)
      mkdir -p "$(dirname "${_SS_PLUGIN_CACHE}")"
      printf '%s' "${_SS_PLUGIN_COUNT}" > "${_SS_PLUGIN_CACHE}"
    fi
    _SS_TS=$(TZ=UTC date +%Y-%m-%dT%H:%M:%SZ)
    echo "[${_SS_TS}] session_id=${_SS_SESSION_ID} duration_ms=${_SS_DURATION_MS} plugin_count=${_SS_PLUGIN_COUNT}" >> "${_SS_TIMING_LOG}" 2>/dev/null || true
    # 直近 1000 行に切り詰め: 1% 確率で実行 (毎回の wc fork 削減)
    if (( RANDOM % 100 == 0 )); then
      if [[ -f "${_SS_TIMING_LOG}" ]] && [[ $(wc -l < "${_SS_TIMING_LOG}" 2>/dev/null || echo 0) -gt 1000 ]]; then
        tail -n 1000 "${_SS_TIMING_LOG}" > "${_SS_TIMING_LOG}.tmp" 2>/dev/null \
            && mv "${_SS_TIMING_LOG}.tmp" "${_SS_TIMING_LOG}" 2>/dev/null || true
      fi
      # hook-errors.log は settings.json の 2>> redirect 先で inline rotation 不可のためここで size 回収する
      # shellcheck source=lib/log-rotation.sh
      source "${SCRIPT_DIR}/lib/log-rotation.sh" 2>/dev/null || true
      if declare -f _rotate_log_if_needed &>/dev/null; then
        _rotate_log_if_needed "$HOME/.claude/logs/hook-errors.log" 2
      fi
    fi

    # /tmp/claude-* marker GC: 1% 確率で 7 日以上古い marker を非同期削除
    # 対象: claude-ngdict-* / claude-ng-inject-* / claude-session-scan-* / claude-transcript-decl-*
    #       / claude_session_bloat_* / claude-last-prompt-* / claude-deleg-checklist-*
    #       / claude-serena-fail-count-* / claude-today-commits-* / claude-fail-prompt-* / claude-wt-*
    # 各 hook が期限切れ回収せず蓄積する問題への対応 (現 session の marker は mtime 新しいので保護)
    if (( RANDOM % 100 == 0 )); then
      (
        for _pat in 'claude-ngdict-*' 'claude-ng-inject-*' 'claude-session-scan-*' \
                    'claude-transcript-decl-*' 'claude_session_bloat_*' 'claude-last-prompt-*' \
                    'claude-deleg-checklist-*' 'claude-serena-fail-count-*' \
                    'claude-today-commits-*' 'claude-fail-prompt-*' 'claude-wt-*'; do
          find /tmp -maxdepth 1 -name "${_pat}" -type f -mtime +7 -delete 2>/dev/null
        done
      ) &
    fi

    # analytics_start_session はバックグラウンド実行（SQLite append のみ、出力不要）
    _SS_LIB_DIR="${SCRIPT_DIR}/../lib"
    if [[ -f "${_SS_LIB_DIR}/analytics-writer.sh" ]]; then
        (
          source "${_SS_LIB_DIR}/analytics-writer.sh"
          analytics_start_session "${_SS_SESSION_ID}" "${_SS_PROJECT}" "${_SS_DURATION_MS}" 2>/dev/null || true
        ) &
    fi
}

# --- Directory Color ---
# jq 1回で default + mappings を取得して bash側でマッチング（fork大幅削減）
# mtime cache: dir-colors.json が変わった時のみ jq 再実行
_ss_detect_dir_color() {
    _COLOR_CONFIG="${HOME}/.claude/config/dir-colors.json"
    _COLOR_PARSED_CACHE="${HOME}/.claude/cache/dir-colors-parsed.cache"
    _SESSION_COLOR="default"
    if [[ -f "${_COLOR_CONFIG}" ]]; then
        _COLOR_DATA=""
        _COLOR_CONFIG_MTIME=$(stat ${_SS_STAT_FLAG} "${_COLOR_CONFIG}" 2>/dev/null || echo 0)
        if [[ -f "${_COLOR_PARSED_CACHE}" ]]; then
            _COLOR_CACHE_MTIME=$(stat ${_SS_STAT_FLAG} "${_COLOR_PARSED_CACHE}" 2>/dev/null || echo 0)
            if [[ ${_COLOR_CACHE_MTIME} -ge ${_COLOR_CONFIG_MTIME} ]]; then
                _COLOR_DATA=$(<"${_COLOR_PARSED_CACHE}")
            fi
        fi
        if [[ -z "${_COLOR_DATA}" ]]; then
            # 1行目=default、2行目以降="pattern\tcolor"
            _COLOR_DATA=$(jq -r '.default // "default", (.mappings[]? | "\(.pattern)\t\(.color)")' "${_COLOR_CONFIG}" 2>/dev/null || echo "default")
            mkdir -p "$(dirname "${_COLOR_PARSED_CACHE}")"
            printf '%s' "${_COLOR_DATA}" > "${_COLOR_PARSED_CACHE}"
        fi
        _FIRST=true
        while IFS=$'\t' read -r _PATTERN _COLOR; do
            if $_FIRST; then
                _SESSION_COLOR="${_PATTERN}"  # 1行目は default 値
                _FIRST=false
                continue
            fi
            if [[ -n "${_PATTERN}" ]] && [[ "${PWD}" == *"${_PATTERN}"* ]]; then
                _SESSION_COLOR="${_COLOR}"
                break
            fi
        done <<< "${_COLOR_DATA}"
    fi
}

# --- 出力組み立て ---
_ss_build_output_prefix() {
    _SM_PREFIX="${ICON_SUCCESS}"
    if [[ ${#_HARNESS_WARNINGS[@]} -gt 0 ]] || [[ -n "${_CWD_GUARD_MSG}" ]] || [[ -n "${_WT_OWNER_MSG}" ]]; then
      _SM_PREFIX="${ICON_WARNING}"
    fi

    _AC_BASE="**memory 読込 (条件付き、token 節約)**: 実作業 (編集 / 実装 / 調査 / debug) を開始する時のみ \`<repo-root>/memory/MEMORY.md\` (3 tool 共有 index) を read し、関連 topic の個別 file を必要時に read する。作業対象 repo が \`<ghq-root>/github.com/<org>/\` 配下 (linked worktree 含む、origin URL で判定) の場合、\`<ghq-root>/github.com/<org>/memory/MEMORY.md\` (org 作業 memory index) が存在すればそれも read する。質問応答や軽い確認のみの session では読まない。\`mcp__serena__list_memories\` も同条件 (project は --project-from-cwd で自動 activate 済)\n\n**追加推奨**: コーディング作業を開始する場合、最初の編集前に \`/load-guidelines\` を実行"
    _AC_PREFIX="current_session_id: ${_SS_SESSION_ID}"$'\n\n'
    # turn 締め self-check の 3 点を毎 session 冒頭に再掲する (CLAUDE.md 内の宣言が auto-load 時に目立たなくなる対策)。
    # 7-21 実測 baseline: block 18 件 / 7 日 (うち今日単日 17 件)、7-28 で再測定して効果評価する
    _AC_PREFIX+="**[turn 締め self-check]** 送信直前に (a) 最後の 1 文が \`完了\` / \`〜済\` / \`次に\` / \`加えて\` で終わらない (b) 矢印チェーンを prose 化した (c) 本文が要点箇条書き default で、作業工程の列挙や成果物と重複する詳細を含まない (d) 全文を敬体 (です・ます) の完結した文で書き、常体終止や「済」「要確認」の省略語で切っていない (e) 短くする目的で主語・助詞・目的語を削っていない の 5 点を必ず見直す (canonical: guidelines/writing/PRINCIPLES.md 「chat 応答の基本形」 +「完了」「〜済」の禁止)。\n\n"
    if [[ -n "${_WT_OWNER_MSG}" ]]; then
        _AC_PREFIX+="${_WT_OWNER_MSG}"
    fi
    if [[ -n "${_CWD_GUARD_MSG}" ]]; then
        _AC_PREFIX+="${_CWD_GUARD_MSG}"
    fi
    if [[ -n "${_DIAG_MSG}" ]]; then
        _AC_PREFIX+="${_DIAG_MSG}"
    fi
}

# --- memory promote trigger 提示 (1 日 1 回上限) ---
# trigger: 同 prefix 3 file 以上 (同じ話題を繰り返し記録している = 昇格の signal)
# 旧 trigger A (MEMORY.md 50 行超) は 2026-08-24 に廃止した。index は全 memory file を
# 載せる設計になり行数が file 数に比例して増えるため、行数の超過は昇格すべき知見が
# 蓄積したことを意味しない (実測 131 行で毎日発火していた)。肥大の監視は /memory-clean が担当する。
# 詳細: ~/.claude/references-private/memory-promotion-flow.md Section 6
_ss_check_memory_promotion() {
    _PROMOTE_STATE_DIR="${HOME}/.claude/state"
    # memory は 2026-07-09 集約で <repo-root>/memory/ に一本化済 (3 tool 共有 SoT、cwd 非依存)。
    # 変更前の実装は ~/.claude/projects/<encoded-cwd>/memory/MEMORY.md を見ていたが、そこに実 file が
    # 無く trigger が常に対象なしで終わっていた (2026-07-13 修正)。実 SoT path を直接指す
    _MEMORY_INDEX="${MEMORY_SAVE_DIR:-${HOME}/ai-tools/memory}/MEMORY.md"
    [[ -f "${_MEMORY_INDEX}" ]] || _MEMORY_INDEX=""
    # state file の分離 key は cwd slug を維持 (promote 提示の 1 日 1 回上限は project 単位)
    _CWD_SLUG=""
    if [[ -n "${_CWD:-}" ]]; then
        _CWD_SLUG="${_CWD//\//-}"
        _CWD_SLUG="${_CWD_SLUG//./-}"
    fi
    # state file は project 別 (memory も project 別、reminder も project 単位で 1 日 1 回)
    _PROMOTE_STATE_FILE="${_PROMOTE_STATE_DIR}/promote-prompted-${_CWD_SLUG:-default}-${_SS_DATE_TODAY}"
    if [[ -f "${_MEMORY_INDEX}" ]] && [[ ! -f "${_PROMOTE_STATE_FILE}" ]]; then
        # dirname fork 削減: bash parameter expansion で親ディレクトリを取得
        _MEMORY_DIR="${_MEMORY_INDEX%/*}"
        _PROMOTE_HITS=()
        # trigger: 同 prefix 3 file 以上 (feedback_xxx_*, reference_xxx_*, project_xxx_*, work-context-xxx_*)
        # prefix = 先頭 2 token (例: feedback_design_doc → feedback_design)
        # find|grep|sed|sort|uniq -c|awk の 6-fork chain → bash glob + 連想配列に置換
        declare -A _TOPIC_MAP=()
        for _mf in "${_MEMORY_DIR}"/*.md; do
            [[ -f "${_mf}" ]] || continue
            _bn="${_mf##*/}"          # basename 相当 (fork なし)
            _bn="${_bn%.md}"          # .md 除去
            [[ "${_bn}" == "MEMORY" ]] && continue
            # prefix 抽出: sed -E 's/^([a-z]+([_-][a-z0-9]+)?).*$/\1/' と同等
            # bash regex で先頭 2 token マッチ (lower は sed 前に実施済み相当)
            _bnl="${_bn,,}"
            if [[ "${_bnl}" =~ ^([a-z]+([_-][a-z0-9]+)?) ]]; then
                _pfx="${BASH_REMATCH[1]}"
            else
                _pfx="${_bnl:0:20}"
            fi
            _TOPIC_MAP["${_pfx}"]=$(( ${_TOPIC_MAP["${_pfx}"]:-0} + 1 ))
        done
        _TOPIC_COUNTS=""
        for _pfx in "${!_TOPIC_MAP[@]}"; do
            if (( _TOPIC_MAP["${_pfx}"] >= 3 )); then
                _TOPIC_COUNTS+="${_pfx}(${_TOPIC_MAP["${_pfx}"]}) "
            fi
        done
        unset _TOPIC_MAP _mf _bn _bnl _pfx
        if [[ -n "${_TOPIC_COUNTS}" ]]; then
            _PROMOTE_HITS+=("同 topic 3 file 以上: ${_TOPIC_COUNTS} (promote trigger)")
        fi
        if (( ${#_PROMOTE_HITS[@]} > 0 )); then
            _PROMOTE_MSG="${ICON_WARNING} memory 昇格候補あり: $(printf '%s; ' "${_PROMOTE_HITS[@]}")\n  → \`/promote\` で SoT 集約検討 (詳細: ~/.claude/references-private/memory-promotion-flow.md)\n\n"
            _AC_PREFIX+="${_PROMOTE_MSG}"
            # state file 作成 (本日 1 回限り)
            mkdir -p "${_PROMOTE_STATE_DIR}"
            touch "${_PROMOTE_STATE_FILE}"
        fi
    fi
}

# --- sleep proposals 通知 (staged があれば /sleep-review を案内) ---
_ss_check_sleep_proposals() {
    _SLEEP_MEMORY_DIR="${MEMORY_SAVE_DIR:-${HOME}/ai-tools/memory}"
    _SLEEP_STAGED=0
    if [[ -d "${_SLEEP_MEMORY_DIR}" ]]; then
        for _spf in "${_SLEEP_MEMORY_DIR}"/sleep-proposals-*.md; do
            [[ -f "${_spf}" ]] || continue
            case "${_spf}" in *.rejected.md|*.adopted.md) continue ;; esac
            _SLEEP_STAGED=$(( _SLEEP_STAGED + 1 ))
        done
        unset _spf
    fi
    if (( _SLEEP_STAGED > 0 )); then
        _AC_PREFIX+="${ICON_WARNING} sleep proposals ${_SLEEP_STAGED} 件 staged → \`/sleep-review\` で triage\n\n"
    fi
    if [[ -f "${HOME}/.claude/sleep/tracked-change-warn" ]]; then
        # flag には "<date> <発生源>" (mine / retrospective) が追記されている
        _TCW_SRC="$(tr '\n' ' ' < "${HOME}/.claude/sleep/tracked-change-warn" 2>/dev/null)"
        _AC_PREFIX+="${ICON_WARNING} 夜間の無人実行 (${_TCW_SRC:-発生源不明}) が repo file を変更して復元された → \`/sleep-review\` で確認\n\n"
        unset _TCW_SRC
    fi
}

# ====================================
# compact 直後の文脈復元 (source=compact)
# ====================================
# PostCompact は decision control を持たず additionalContext の注入保証もないため、
# 圧縮後に AI へ復元手順を届けられるのはこの経路だけ (公式 hooks docs)。
# pre-compact.sh が書いた ${HOME}/.claude/.compact-memory-state を消費する
_ss_restore_compact_context() {
    if [[ "${_SS_SOURCE:-}" == "compact" ]]; then
        _CS_STATE="${HOME}/.claude/.compact-memory-state"
        _CS_MEMDIR="${MEMORY_SAVE_DIR:-${HOME}/ai-tools/memory}"
        _CS_TS=""
        if [[ -f "${_CS_STATE}" ]]; then
            _CS_RAW=$(cat "${_CS_STATE}" 2>/dev/null || echo "")
            rm -f "${_CS_STATE}"
            [[ "${_CS_RAW}" == ready:* ]] && _CS_TS="${_CS_RAW#ready:}"
        fi
        _CS_FILE=""
        if [[ -n "${_CS_TS}" && -f "${_CS_MEMDIR}/compact-restore-${_CS_TS}.md" ]]; then
            _CS_FILE="${_CS_MEMDIR}/compact-restore-${_CS_TS}.md"
        else
            _CS_FILE=$(ls -t "${_CS_MEMDIR}"/compact-restore-*.md 2>/dev/null | head -1) || true
        fi

        if [[ -n "${_CS_FILE}" ]]; then
            _AC_PREFIX+="## compact 直後の復元 (自動実行)\n\n"
            _AC_PREFIX+="1. Read: \`${_CS_FILE}\`\n"
            _AC_PREFIX+="2. 読み終えたら Bash \`rm\` で同 file を削除する (蓄積防止)\n"
            _AC_PREFIX+="3. 復元した task / 次アクションを 3 行で報告し、圧縮前の作業をそのまま続ける\n\n"
            _AC_PREFIX+="詳細手順が要るときだけ \`commands/reload.md\` を参照する。\n\n"
        else
            _AC_PREFIX+="${ICON_WARNING} compact 直後だが compact-restore file が無い。失われた文脈は user に確認する\n\n"
        fi
        unset _CS_STATE _CS_MEMDIR _CS_TS _CS_RAW _CS_FILE
    fi
}

_ss_finalize_additional_context() {
    if [[ -n "${_AC_PREFIX}" ]]; then
        _AC_FULL="${_AC_PREFIX}\n${_AC_BASE}"
    else
        _AC_FULL="${_AC_BASE}"
    fi
}

# ====================================
# sessionTitle (2.1.152 hookSpecificOutput.sessionTitle)
# repo名 + ブランチ名でセッションを識別可能にする
# ====================================
_ss_build_session_title() {
    _SESSION_TITLE=""
    if [[ -n "${_CWD:-}" && -d "${_CWD:-}" ]]; then
        _REPO_NAME=$(basename "${_CWD}")
        # _SS_IS_GIT / _SS_GIT_BRANCH は冒頭で取得済み（git fork 再実行なし）
        if [[ "${_SS_IS_GIT}" == "true" ]]; then
            if [[ -n "${_SS_GIT_BRANCH}" ]]; then
                _SESSION_TITLE="${_REPO_NAME} @ ${_SS_GIT_BRANCH}"
            else
                _SESSION_TITLE="${_REPO_NAME}"
            fi
        else
            _SESSION_TITLE="${_REPO_NAME}"
        fi
    fi
}

_ss_emit_output() {
    if [[ -n "${_SESSION_TITLE}" ]]; then
        jq -n \
          --arg sm "${_SM_PREFIX} Session初期化完了 [color:${_SESSION_COLOR}]" \
          --arg ac "${_AC_FULL}" \
          --arg color "${_SESSION_COLOR}" \
          --arg title "${_SESSION_TITLE}" \
          '{systemMessage: $sm, additionalContext: $ac, color: $color, hookSpecificOutput: {hookEventName: "SessionStart", sessionTitle: $title}}'
    else
        jq -n \
          --arg sm "${_SM_PREFIX} Session初期化完了 [color:${_SESSION_COLOR}]" \
          --arg ac "${_AC_FULL}" \
          --arg color "${_SESSION_COLOR}" \
          '{systemMessage: $sm, additionalContext: $ac, color: $color}'
    fi
}

# ====================================
# main: 実行順は元 script の上から下の順序を維持する
# ====================================
_ss_start_timer
_ss_init_logging_and_lib
_ss_detect_stat_flag
_ss_parse_input
_ss_detect_git
_ss_init_statusline_marker
_ss_harness_diagnostics
_ss_check_multi_repo_cwd
_ss_check_worktree_owner
_ss_start_worktree_memory_link_bg
_ss_record_session_analytics
_ss_detect_dir_color
_ss_build_output_prefix
_ss_check_memory_promotion
_ss_check_sleep_proposals
_ss_restore_compact_context
_ss_finalize_additional_context
_ss_build_session_title
_ss_emit_output
