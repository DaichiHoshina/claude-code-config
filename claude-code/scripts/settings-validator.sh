#!/bin/bash
# =============================================================================
# Settings Validator / Sync Helper
# settings.json の検証・同期ロジック。sync.sh から source して使用する。
#
# 前提:
#   - SCRIPT_DIR, CLAUDE_DIR が caller (sync.sh) で export 済み
#   - print_warning / print_error / print_info / print_success は sync.sh が
#     lib/print-functions.sh を source 済みで利用可能
#   - check_jq は sync.sh で定義済み
# =============================================================================

# 多重 source 防止
if [[ "${_SETTINGS_VALIDATOR_LOADED:-}" == "1" ]]; then
    return 0
fi
_SETTINGS_VALIDATOR_LOADED=1

# =============================================================================
# sync_settings_hooks
# settings.json の hooks セクションを template からマージする。
# matcher 単位で dedup: template entries が canonical、live 独自 matcher のみ末尾保持。
# 同 matcher の live entry は template 値で上書きされる (古い command の残留を防ぐ)。
# =============================================================================

sync_settings_hooks() {
    if ! check_jq; then
        print_warning "jq が見つかりません。settings.json hooks の同期をスキップします"
        return
    fi

    local template="$SCRIPT_DIR/templates/settings.json.template"
    local live="$CLAUDE_DIR/settings.json"

    if [ ! -f "$template" ]; then
        return
    fi
    # 別 PC 初回セットアップ対応: settings.json 不在時は template から initial create
    if [ ! -f "$live" ]; then
        if cp "$template" "$live"; then
            print_info "settings.json を template から初期化しました"
        else
            print_error "settings.json 初期化失敗: $live"
            return
        fi
    fi

    local template_hooks
    template_hooks=$(jq '.hooks // {}' "$template" 2>/dev/null)

    # matcher 単位で dedup する。template entry を canonical とし、live 独自 matcher のみ末尾保持する。
    # 同 matcher の live entry は template 値で上書きする (古い command の残留を防ぐ)。
    # matcher 欠落 (null) entry は command 内容も key に含める。
    # matcher == "" は claude-code 上 "*" と同義のため normalize して "*" と dedup する。
    # 2026-07-23 に SessionStart duplicate delta injection を根治する目的で追加した
    local tmpfile
    tmpfile=$(mktemp)
    if jq --argjson th "$template_hooks" '
      def norm_matcher: if . == "" then "*" else . end;
      .hooks = (
        (.hooks // {}) as $live_hooks
        | reduce ($th | to_entries[]) as $ev (
            $live_hooks;
            .[$ev.key] = (
              ($ev.value | map(.matcher | norm_matcher)) as $tpl_matchers
              | ($ev.value | map(select(.matcher == null) | .hooks)) as $tpl_null_hook_sets
              | $ev.value
              + [
                  ($live_hooks[$ev.key] // [])[]
                  | . as $entry
                  | select(
                      if $entry.matcher == null then
                        ($tpl_null_hook_sets | any(. == $entry.hooks) | not)
                      else
                        ($tpl_matchers | index($entry.matcher | norm_matcher) | not)
                      end
                    )
                ]
            )
          )
      )
    ' "$live" > "$tmpfile"; then
        mv "$tmpfile" "$live"
        print_success "settings.json hooks を同期しました"
    else
        rm -f "$tmpfile"
        print_error "settings.json hooks のマージに失敗しました"
        return 1
    fi
}

# =============================================================================
# sync_settings_skill_overrides
# settings.json の skillOverrides セクションを template からマージする。
# template の値を優先しつつ live 独自キーを保持する。孤立 override を警告。
# =============================================================================

sync_settings_skill_overrides() {
    if ! check_jq; then
        return
    fi

    local template="$SCRIPT_DIR/templates/settings.json.template"
    local live="$CLAUDE_DIR/settings.json"

    if [ ! -f "$template" ]; then
        return
    fi
    # sync_settings_hooks が先に live を作成済み（呼び出し順 L359-360）のため
    # live 不在時は return のまま（冪等・簡略化判断）
    if [ ! -f "$live" ]; then
        return
    fi

    local template_overrides
    template_overrides=$(jq '.skillOverrides // {}' "$template" 2>/dev/null)

    if [ "$template_overrides" = "{}" ]; then
        return
    fi

    local tmpfile
    tmpfile=$(mktemp)
    if jq --argjson to "$template_overrides" '.skillOverrides = ((.skillOverrides // {}) + $to)' "$live" > "$tmpfile"; then
        mv "$tmpfile" "$live"
        print_success "settings.json skillOverrides を同期しました"
    else
        rm -f "$tmpfile"
        print_error "settings.json skillOverrides のマージに失敗しました"
        return 1
    fi

    # 孤立 override 検出: template から削除されたが live に残存するキー
    # 削除はユーザー判断（個別追加した override を破壊しないため警告のみ）
    local orphans
    orphans=$(jq -r --argjson tmpl "$template_overrides" \
        '((.skillOverrides // {}) | keys) - ($tmpl | keys) | .[]' \
        "$live" 2>/dev/null || true)

    if [ -n "${orphans}" ]; then
        print_warning "skillOverrides に template 管理外のキー検出:"
        while IFS= read -r key; do
            [ -z "${key}" ] && continue
            echo "  - ${key}" >&2
        done <<< "${orphans}"
        echo "  → 意図的でなければ ~/.claude/settings.json から削除推奨" >&2
    fi
}

# =============================================================================
# sync_settings_permissions
# permissions / sandbox / worktree / enabledPlugins / extraKnownMarketplaces を
# template canonical で上書きする。security-critical sections のため template 優先。
# =============================================================================

sync_settings_permissions() {
    if ! check_jq; then
        print_warning "jq が見つかりません。security-critical sections の同期をスキップします"
        return 0
    fi

    local template="$SCRIPT_DIR/templates/settings.json.template"
    local live="$CLAUDE_DIR/settings.json"

    if [ ! -f "$template" ]; then
        return 0
    fi
    # sync_settings_hooks が先に live を作成済み（呼び出し順）のため
    # live 不在時は return（冪等・簡略化判断）
    if [ ! -f "$live" ]; then
        return 0
    fi

    local sections=("permissions" "sandbox" "worktree" "enabledPlugins" "extraKnownMarketplaces")
    local sections_json
    sections_json=$(printf '%s\n' "${sections[@]}" | jq -R . | jq -s .)

    local tmpfile
    tmpfile=$(mktemp)
    if jq \
        --slurpfile tmpl "$template" \
        --argjson sections "$sections_json" \
        '. as $live | $tmpl[0] as $template |
         reduce ($sections[] | select($template[.] != null)) as $k
           ($live; .[$k] = $template[$k])' \
        "$live" > "$tmpfile"; then
        mv "$tmpfile" "$live"
        print_success "settings.json security-critical sections を同期しました"
    else
        rm -f "$tmpfile"
        print_error "settings.json security-critical sections の同期に失敗しました"
        return 1
    fi

    merge_local_permissions "$live"
}

# =============================================================================
# merge_local_permissions
# 個人環境固有の permission を template でなく local overlay に格納する。
# template は commit される canonical なので個人 path を記載しない (公開されうるため)。
# overlay の allow / deny / ask を template 由来の配列へ後から足す (重複は除く)。
# file 不在なら何もしない (no-op)。
# =============================================================================
merge_local_permissions() {
    local live="$1"
    local overlay="${CLAUDE_EXTRA_PERMISSIONS_FILE:-$HOME/.claude/references-private/extra-permissions.json}"
    [ -f "$overlay" ] || return 0

    if ! jq -e . "$overlay" > /dev/null 2>&1; then
        print_warning "extra-permissions.json が JSON として読めません: $overlay"
        return 0
    fi

    local tmpfile
    tmpfile=$(mktemp)
    if jq --slurpfile ov "$overlay" \
        '.permissions //= {}
         | reduce ("allow", "deny", "ask") as $k
             (.; .permissions[$k] = ((.permissions[$k] // []) + ($ov[0][$k] // []) | unique))' \
        "$live" > "$tmpfile"; then
        mv "$tmpfile" "$live"
        print_success "local permission overlay を適用しました"
    else
        rm -f "$tmpfile"
        print_warning "local permission overlay の適用に失敗しました: $overlay"
    fi
}

# =============================================================================
# sync_settings_root_keys
# allowlist に列挙した root keys を template canonical で上書きする。
# dedicated 関数が担う keys (hooks / skillOverrides / permissions 等) は除外。
# =============================================================================

sync_settings_root_keys() {
    if ! check_jq; then
        print_warning "jq が見つかりません。root keys の同期をスキップします"
        return 0
    fi

    local template="$SCRIPT_DIR/templates/settings.json.template"
    local live="$CLAUDE_DIR/settings.json"

    if [ ! -f "$template" ]; then
        return 0
    fi
    # sync_settings_hooks が先に live を作成済み（呼び出し順）のため
    # live 不在時は return（冪等・簡略化判断）
    if [ ! -f "$live" ]; then
        return 0
    fi

    # allowlist: 既存 dedicated 関数 (hooks / skillOverrides / permissions /
    # sandbox / worktree / enabledPlugins / extraKnownMarketplaces) が担う key を除く
    # template canonical で上書きする root key。template に無い key は live からも消す
    # (template から外した設定が live に残り続け、/output-style 等で直しても sync で戻る齟齬を防ぐ。2026-08-28)。
    # 将来 key を追加する場合はここに明示的に追加すること（暴走防止の allowlist 方式）
    local root_keys=(
        "env"
        "model"
        "fallbackModel"
        "statusLine"
        "autoUpdatesChannel"
        "preferredNotifChannel"
        "defaultMode"
        "verbose"
        "autocompact"
        "includeCoAuthoredBy"
        "refreshInterval"
        "outputStyle"
        "language"
        "spinnerVerbs"
        "effortLevel"
        "showThinkingSummaries"
        "alwaysThinkingEnabled"
        "bashEditDiffEnabled"
        "showTurnDuration"
        "skipAutoPermissionPrompt"
        "skipDangerousModePermissionPrompt"
        "instructions"  # 未サポート key。template から外したので live からの削除用に保持する (2026-08-29)
        "awaySummaryEnabled"
        "claudeMdExcludes"
    )
    local keys_json
    keys_json=$(printf '%s\n' "${root_keys[@]}" | jq -R . | jq -s .)

    local tmpfile
    tmpfile=$(mktemp)
    if jq \
        --slurpfile tmpl "$template" \
        --argjson keys "$keys_json" \
        '. as $live | $tmpl[0] as $template |
         reduce $keys[] as $k
           ($live; if $template[$k] != null then .[$k] = $template[$k] else del(.[$k]) end)' \
        "$live" > "$tmpfile"; then
        mv "$tmpfile" "$live"
        print_success "settings.json root keys (env / model / statusLine / autoUpdatesChannel ほか) を同期しました"
    else
        rm -f "$tmpfile"
        print_error "settings.json root keys の同期に失敗しました"
        return 1
    fi
}
