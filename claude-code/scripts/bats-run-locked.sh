#!/usr/bin/env bash
# bats suite を machine 全体で 1 本ずつ直列実行する wrapper。
# 複数 session (worktree 含む) が全 suite を同時に回すと同じ jobs 数同士で CPU を
# 奪い合い、各 run が単独時の数倍に伸びて timeout する (2026-08-23 実踏)。
# worktree 間で lock を共有するため、lock は repo 外の固定 path に置く
set -euo pipefail

TARGET_DIR="${1:?usage: bats-run-locked.sh <tests-dir>}"

LOCK_DIR="${AI_TOOLS_BATS_LOCK_DIR:-/tmp/ai-tools-bats-suite.lock}"
RECLAIM_DIR="${LOCK_DIR}.reclaim"
WAIT_TIMEOUT="${AI_TOOLS_BATS_LOCK_TIMEOUT:-1200}"
POLL_INTERVAL="${AI_TOOLS_BATS_LOCK_POLL:-5}"

acquire() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "$$" > "$LOCK_DIR/pid"
    return 0
  fi
  return 1
}

release() {
  # 自分の lock でなければ触らない。stale 回収を間に実行すると LOCK_DIR が別 run の物に
  # すり替わっていることがあり、無条件 rm だと相手の実行中 lock を解放してしまう
  [ "$(cat "$LOCK_DIR/pid" 2>/dev/null || true)" = "$$" ] || return 0
  rm -rf "$LOCK_DIR"
}

# 死んだ保持者の lock を回収する。回収を 1 process に絞らないと、同時に stale 判定した
# 2 waiter が両方 rm し、片方が相手の獲得直後の lock を消して二重実行になる
# (mkdir の原子性が破れる)。回収権を取れなかった側は 1 を返して待機側へ回る
reclaim_stale() {
  local holder="$1" current
  mkdir "$RECLAIM_DIR" 2>/dev/null || return 1
  current="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  # 回収権を待つ間に別 run が再取得していることがあるため、消す直前にもう一度検証する
  if [ "$current" = "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
    rm -rf "$LOCK_DIR"
  fi
  rmdir "$RECLAIM_DIR" 2>/dev/null || true
  return 0
}

waited=0
announced=0
until acquire; do
  holder="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
    # 保持 process が死んでいる stale lock は回収して再取得する
    if reclaim_stale "$holder"; then
      continue
    fi
    # 回収権を取れない = 別 waiter が回収中。ただし回収中の process が SIGKILL されると
    # RECLAIM_DIR が残り、以後どの waiter も stale lock を回収できなくなる。回収処理は
    # 数 command で終わるので、60s 超の残存は保持者の死亡とみなして落とす
    # (trap は SIGKILL を拾えないため age で判定する)
    if [ -n "$(find "$RECLAIM_DIR" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
      rmdir "$RECLAIM_DIR" 2>/dev/null || true
      continue
    fi
    # まだ新しい回収権なら busy loop を避けて下の sleep へ落とす
  fi
  if [ "$announced" -eq 0 ]; then
    echo "bats-run-locked: 別の bats 実行 (pid ${holder:-unknown}) の完了を待つ (最大 ${WAIT_TIMEOUT}s)" >&2
    announced=1
  fi
  if [ "$waited" -ge "$WAIT_TIMEOUT" ]; then
    echo "bats-run-locked: ${WAIT_TIMEOUT}s 待っても lock が空かない。実行中の suite 完了後に再実行する" >&2
    exit 1
  fi
  sleep "$POLL_INTERVAL"
  waited=$((waited + POLL_INTERVAL))
done
trap release EXIT

if command -v parallel >/dev/null 2>&1; then
  # jobs は 2026-09-21 に 8 から 16 へ上げた。待ちと file I/O が多く CPU が空くため、
  # core 数 (10) を超える値の方が速い。実測 (unit): 8=173.5s / 12=166.7s / 16=152.4s
  bats --jobs "${AI_TOOLS_BATS_JOBS:-16}" --no-parallelize-within-files -r "$TARGET_DIR"
else
  bats -r "$TARGET_DIR"
fi
