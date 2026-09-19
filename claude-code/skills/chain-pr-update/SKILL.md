---
allowed-tools: Bash, Read, Edit
name: chain-pr-update
description: stacked PR chain (上流と後続の関係を持つ複数 PR) を最新 main / 上流 branch へ順に伝播させる。merge --no-ff 方式で force push 回避。「chain 更新」「chain に main を取り込む」「PR chain rebase」「stacked PR 更新」「chain 整合確認」で起動する。
---

# chain-pr-update

stacked PR (child の base が別 PR の head になっている 2 段以上の chain) へ最新 main を取り込む作業を、chain 全 branch を worktree で実行して merge + push で伝播させる。**rebase は使わない** (履歴を破壊し force push を強いる)。

## 前提

- 各 PR の branch が別 worktree で checkout されていること (`git worktree list` で確認)
- `gh` CLI が authenticate 済み (chain 検出に使う)
- 破壊的操作 (force push) はしない前提。merge --no-ff で新規 commit を積む

## Flow

### Step 1. chain 全体の整合を確認する

`chain-status.sh` で自 open PR の全 pair を behind / ahead 集計する。

```bash
# 全 open PR chain を自動検出して集計する
<repo-root>/claude-code/skills/chain-pr-update/chain-status.sh

# root を指定して下流だけ辿る (root vs main の取り込みは default モードか
# 手動 `git rev-list --count <root>..origin/main` で別途確認する)
<repo-root>/claude-code/skills/chain-pr-update/chain-status.sh <root-branch>

# 明示的な pair 列を渡す (chain が複数実行されている時)
<repo-root>/claude-code/skills/chain-pr-update/chain-status.sh --pairs \
  "child-a parent-a" "child-b child-a"
```

出力の `behind=N (N>0)` が付いた行が更新候補である。behind=0 は skip する。

### Step 1.5. 伝搬前の記録と未 commit 差分の一時保存

- 各対象 PR の変更 file 一覧を控える: `gh pr diff <番号> --name-only | sort > <scratchpad>/pr<番号>-files-before.txt` (Step 4 の scope 検証で使う)
- 伝搬対象 worktree に未 commit 差分があれば `git stash push -u -m "chain-update <branch>" -- <自分が編集した path>` で一時保存し、一時保存した worktree を記録する。同じ checkout を別 session が触っている疑いがあるときは stash でなく patch 移送 (`git diff <files> > <tmp>/wip.patch` → 復元は `git apply`) にする

### Step 2. 上流 root から順に merge + push を伝播させる

chain の **上流から下流の順** で 1 branch ずつ **直列** に処理する。順序が失われる or 並列に実行すると history が壊れる (詳細は「禁止 pattern」節)。

```bash
# worktree path / branch / parent / grandparent (省略可) を渡す
<repo-root>/claude-code/skills/chain-pr-update/chain-propagate.sh \
  <worktree-dir> <branch> <parent-branch> [grandparent-branch]
```

第 4 引数 `grandparent` を渡すと **下流先取り gate** が発動する。parent が更に上流と behind な状態で child を merge しようとすると script が拒否する。

`chain-propagate.sh` は下記を内蔵する: dirty check / HEAD 一致 check、flock による同一 repo の並列実行拒否、下流先取り gate (grandparent 引数を渡した時のみ)、behind=0 skip、merge retry (最大 3 回)。

- **retry 失敗後の状態**: conflict が発生すると retry 3 回のあとに merge を abort し、作業ツリーを元へ戻す。clean に見えても解消は済んでいない
- **復旧手順**: その worktree で `git merge --no-ff origin/<parent>` をやり直してから resolve し、commit + push まで手で行う
- **事前検知の代替**: どの branch が衝突するかは `git merge-tree --write-tree <child> <parent>` で先に測れる。分かっているものは script を通さず手 merge から入る方が早い

### Step 3. Step 1 を再実行して全 pair behind=0 を確認する

伝播中に main が更に進むと再度 behind が発生する。user 意図次第で再伝播する。

### Step 4. 伝搬後の PR diff scope 検証と復元 (報告まで含めて完了)

user の「差分を再確認して」を待たず、伝搬の一部としてここまで行う (2026-08 の実測で、同文の再確認依頼が週 7 回あった):

- 各 PR で `gh pr diff <番号> --name-only | sort` を再取得し、Step 1.5 の before 一覧と `diff` する
- 差があれば file を列挙し、意図した変更 (conflict resolve 等) か main 由来の混入かを切り分けて報告する。差がなければ「全 PR の diff scope 変化なし」と報告する
- Step 1.5 で一時保存した stash をここで `git stash pop` で戻し、戻したことを報告に含める

## 禁止 pattern (絶対に踏まない)

`chain-propagate.sh` が script レベルで拒否する 2 pattern。背景・害・代替の詳細は `references/detail.md` を参照。

- **下流先取り**: parent が main と behind のまま child に main を先取りさせない。root から順に伝播する。gate は第 4 引数 `grandparent` で発動 (root 更新時のみ省略可)
- **同一 repo での並列実行 / 並列 push**: `.git/index` write 競合や PR base 発散の原因になる。`chain-propagate.sh` の flock で拒否されるので 1 branch ずつ直列で実行する
- **chain 対象 branch の force push / squash**: 投稿済み comment の commit hash 参照や下流 merge commit の parent 参照が壊れる。squash 前に GitHub comment 本文の hash 参照と下流伝播済みかを確認し、該当すれば squash しない。対話的 rebase はこの harness では使用禁止

## Gotchas / Troubleshooting

rebase でなく merge を使う理由、index 破損時の対処、worktree path と branch 名の入れ替え修復、flaky test の再実行、root branch を最初に更新する理由、エラー別対処は `references/detail.md` を参照。
