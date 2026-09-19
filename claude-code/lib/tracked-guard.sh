#!/usr/bin/env bash
# 無人 claude 実行 (sleep mine / retrospective cron) が repo 管理 file を
# 勝手に変更していないかを before/after で検査し、変更を戻す共通 guard。
# HEAD は fingerprint に含めない (並走 session の commit で false positive になる)。
# untracked (--others) も含める: acceptEdits 系の無人実行は Write の新規 file 作成も
# 自動承認しうるため、diff だけでは新規 file を見逃す。gitignore 済 path は対象外

tracked_guard_fingerprint() {
  local repo="$1"
  {
    git -C "${repo}" --no-optional-locks diff
    git -C "${repo}" --no-optional-locks diff --cached
    git -C "${repo}" --no-optional-locks ls-files --others --exclude-standard
  } | shasum -a 256 | cut -d' ' -f1
}

tracked_guard_changed_paths() {
  local repo="$1"
  {
    git -C "${repo}" --no-optional-locks diff --name-only
    git -C "${repo}" --no-optional-locks diff --name-only --cached
    git -C "${repo}" --no-optional-locks ls-files --others --exclude-standard
  } | sort -u
}

# before に無かった変更 path を戻す。tracked は restore、untracked は隔離 dir へ移動する
# (mine 中に人間や他 process が作った file を対象に含める可能性があり、不可逆な rm はレビュー不能になる)。
# 処理した path を "restored <path>" / "quarantined <path>" 形式で stdout に返す
tracked_guard_revert_new_paths() {
  local repo="$1" before_paths="$2" quarantine="$3"
  local after_paths new_paths p
  after_paths="$(tracked_guard_changed_paths "${repo}")"
  new_paths="$(comm -13 <(printf '%s\n' "${before_paths}") <(printf '%s\n' "${after_paths}"))"
  while IFS= read -r p; do
    [[ -n "${p}" ]] || continue
    if git -C "${repo}" ls-files --error-unmatch -- "${p}" >/dev/null 2>&1; then
      git -C "${repo}" restore -- "${p}" 2>/dev/null || git -C "${repo}" checkout -- "${p}" 2>/dev/null || true
      printf 'restored %s\n' "${p}"
    else
      mkdir -p "${quarantine}/$(dirname "${p}")"
      mv "${repo}/${p}" "${quarantine}/${p}" 2>/dev/null || rm -f "${repo}/${p}"
      printf 'quarantined %s\n' "${p}"
    fi
  done <<< "${new_paths}"
}

# 30 日超の隔離 dir を掃除する (呼び出し側の起動時 cleanup から呼ぶ)
tracked_guard_cleanup_quarantine() {
  local state_dir="$1"
  find "${state_dir}" -maxdepth 1 -type d -name 'quarantine-*' -mtime +30 -exec rm -rf {} + 2>/dev/null || true
}
