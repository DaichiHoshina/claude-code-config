#!/usr/bin/env bash
# launchd install 系 script (scripts/install-*-cron.sh) 共通の plist 生成 / worktree guard /
# preview・書き込み / bootstrap 手順を関数化した lib。source して使う (直接実行しない)。
#
# 各 installer の固有値 (LABEL / ProgramArguments / schedule / log path) はこの lib を
# source する側が保持し、本 lib は「値を渡されて定型処理をする」だけに徹する

# 引数: allow_var_name repo_root pattern install_hint_path
# REPO_ROOT が worktree pattern に一致し、allow_var (env) が 1 でなければエラーを stderr に出し
# 戻り値 2 を返す (呼び出し側は `|| exit $?` する)
launchd_check_worktree_repo_root() {
  local allow_var="$1" repo_root="$2" pattern="$3" install_hint="$4"
  local allow_val
  allow_val="$(eval "echo \"\${${allow_var}:-0}\"")"
  if [[ "$allow_val" -ne 1 && "$repo_root" == *"${pattern}"* ]]; then
    cat >&2 <<EOF
ERROR: REPO_ROOT が worktree 配下です: ${repo_root}
  cron 実行時には worktree が消えている可能性があります。
  main repo path を --repo で明示してください:
    ${install_hint}
EOF
    return 2
  fi
  return 0
}

# 引数: script_root pattern
# DETECTED_ROOT (script 自身の root) が worktree pattern に一致すれば拒否する
# (sleep-cron / loop-cron が使う variant。--repo 誤配置ではなく script 自体の設置場所を見る)
launchd_check_worktree_script_root() {
  local allow_val="$1" script_root="$2" pattern="$3" caller_hint="$4"
  if [[ "$allow_val" -ne 1 && "$script_root" == *"${pattern}"* ]]; then
    echo "ERROR: script root が worktree 配下です: ${script_root}" >&2
    echo "  ${caller_hint}" >&2
    return 2
  fi
  return 0
}

# 引数: path label
# 実行 file が存在しなければエラーを stderr に出し 2 を返す
launchd_check_executable() {
  local path="$1" label="$2"
  if [[ ! -x "$path" ]]; then
    echo "ERROR: ${label} が見つかりません" >&2
    return 2
  fi
  return 0
}

# 引数: hour minute [weekday(default 1)]
# 標準出力に StartCalendarInterval の中身 (Weekday/Hour/Minute) を出す。weekday を渡さない
# installer (morning-ping) は launchd_calendar_interval_daily を使う
launchd_calendar_interval_weekly() {
  local hour="$1" minute="$2" weekday="${3:-1}"
  cat <<EOF
    <key>Weekday</key>
    <integer>${weekday}</integer>
    <key>Hour</key>
    <integer>${hour}</integer>
    <key>Minute</key>
    <integer>${minute}</integer>
EOF
}

# 引数: hour minute
launchd_calendar_interval_daily() {
  local hour="$1" minute="$2"
  cat <<EOF
    <key>Hour</key>
    <integer>${hour}</integer>
    <key>Minute</key>
    <integer>${minute}</integer>
EOF
}

# 引数: "min hour dom mon dow" (5-field cron、数値か * のみ対応)
# 標準出力に Minute/Hour/Day/Month/Weekday の順で "*" 以外の key を出す。
# sleep-cron / loop-cron が共有していたロジックをそのまま抽出したもの
launchd_calendar_interval_from_cron5() {
  local schedule="$1"
  local c_min c_hour c_dom c_mon c_dow extra
  read -r c_min c_hour c_dom c_mon c_dow extra <<< "$schedule"
  [[ -z "${extra:-}" && -n "${c_dow:-}" ]] || {
    echo "ERROR: --schedule は 5 field (min hour dom mon dow)" >&2
    return 2
  }
  local lines=""
  local key val
  for pair in "Minute:${c_min}" "Hour:${c_hour}" "Day:${c_dom}" "Month:${c_mon}" "Weekday:${c_dow}"; do
    key="${pair%%:*}"
    val="${pair#*:}"
    [[ "$val" == "*" ]] && continue
    [[ "$val" =~ ^[0-9]+$ ]] || {
      echo "ERROR: schedule field '${val}' は数値か * のみ対応" >&2
      return 2
    }
    lines+="    <key>${key}</key><integer>${val}</integer>
"
  done
  printf '%s' "$lines"
}

# 引数: label stdout_log stderr_log calendar_interval_xml program_arg...
# 標準出力に plist 全文 (末尾改行込み) を出す。program_arg は ProgramArguments の各 <string> 要素
launchd_render_plist() {
  local label="$1" stdout_log="$2" stderr_log="$3" calendar_xml="$4"
  shift 4
  {
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
  <key>ProgramArguments</key>
  <array>
EOF
    for arg in "$@"; do
      printf '    <string>%s</string>\n' "$arg"
    done
    cat <<EOF
  </array>
  <key>StartCalendarInterval</key>
  <dict>
EOF
    # calendar_xml は $(...) 経由で渡ると末尾改行が失われるため、ここで明示的に 1 つ復元する
    printf '%s\n' "$calendar_xml"
    cat <<EOF
  </dict>
  <key>StandardOutPath</key>
  <string>${stdout_log}</string>
  <key>StandardErrorPath</key>
  <string>${stderr_log}</string>
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
EOF
  }
}

# 引数: dry_run plist_path plist_content
# DRY_RUN=1 なら preview を出して 0 を返す (呼び出し側で `&& exit 0`)。DRY_RUN=0 なら何もせず 1
launchd_preview_if_dry_run() {
  local dry_run="$1" plist_path="$2" plist_content="$3"
  [[ "$dry_run" -eq 1 ]] || return 1
  echo "=== plist preview (${plist_path}) ==="
  # plist_content は $(...) 経由で渡ると末尾改行が失われるため、ここで明示的に 1 つ復元する
  printf '%s\n' "$plist_content"
  return 0
}

# 引数: plist_dir log_dir plist_path plist_content
# plist を配置し配置完了 message を出す
launchd_write_plist() {
  local plist_dir="$1" log_dir="$2" plist_path="$3" plist_content="$4"
  mkdir -p "$plist_dir" "$log_dir"
  printf '%s\n' "$plist_content" > "$plist_path"
  echo "✓ plist を配置しました: ${plist_path}"
}

# 引数: label plist_path show_state(0/1)
# --enable 時の bootout → bootstrap を行う。成功なら 0、失敗なら手動手順を案内して 1。
# show_state=1 の installer は bootstrap 成功後に launchctl print | grep state も出す
launchd_bootstrap_enable() {
  local label="$1" plist_path="$2" show_state="$3"
  local gui_domain
  gui_domain="gui/$(id -u)"
  launchctl bootout "${gui_domain}/${label}" 2>/dev/null || true
  if launchctl bootstrap "$gui_domain" "$plist_path"; then
    echo "✓ launchctl bootstrap 完了 (${gui_domain}/${label})"
    if [[ "$show_state" -eq 1 ]]; then
      launchctl print "${gui_domain}/${label}" 2>/dev/null | grep -E '^\s*(state|last exit code)' || true
    fi
    return 0
  fi
  echo "ERROR: launchctl bootstrap 失敗。手動で実行してください:" >&2
  echo "  launchctl bootstrap ${gui_domain} \"${plist_path}\"" >&2
  return 1
}

# 引数: label plist_path show_state(0/1)
# --enable なしのときの案内 text を stdout に出力する (uninstall 行は呼び出し側の末尾 block が担当する)
launchd_print_enable_instructions() {
  local label="$1" plist_path="$2" show_state="$3"
  cat <<EOF

次のコマンドで enable してください (--enable で自動化可):

  launchctl bootout  gui/\$(id -u)/${label} 2>/dev/null || true
  launchctl bootstrap gui/\$(id -u) "${plist_path}"
EOF
  if [[ "$show_state" -eq 1 ]]; then
    cat <<EOF
  launchctl print    gui/\$(id -u)/${label} | grep state
EOF
  fi
}
