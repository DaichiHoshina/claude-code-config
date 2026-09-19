# chain-pr-update 詳細リファレンス

SKILL.md から参照される詳細情報。禁止 pattern の背景説明・代替手段・Gotchas・Troubleshooting・検証実績をここに集約する。

## 禁止 pattern 詳細

### 下流先取り (child が親より先に main を merge する)

- **やってはいけない例**: parent が main と behind の状態で、`chain-propagate.sh <child-wt> child main` を実行して child に main を先取りさせる
- **害**: 後で親→子伝播する時に、child は「main の変更 + parent 経由の同じ main 変更」を二重に merge する。conflict 頻発、reviewer から見ても history が非直線化して読めなくなる
- **正しい順**: root (parent が main の branch) から順に下流へ伝播する。root が main と同期してから次の branch を変更する
- **gate**: `chain-propagate.sh` の第 4 引数 `grandparent` を渡すと発動。「parent が grandparent と behind なら child を merge しない」で script が exit する
- **例外**: root branch を main 起点で更新する時のみ grandparent なし (or `CHAIN_SKIP_GRANDPARENT_CHECK=1`) で実行する

### 同一 repo での並列実行 / 並列 push

- **やってはいけない例**: 別 terminal で複数 branch の `chain-propagate.sh` を同時に kick する / `&` で背景実行して連射する
- **害**: `.git/index` の write が競合して `fatal: Unable to write index` が発生する。GitHub 側も並列 push で PR base 差分が発散する。中間 branch の history が飛ぶことがある
- **gate**: `chain-propagate.sh` は `.git/chain-propagate.lock` を flock で取る。取れなければ即 exit する
- **正しい実行**: 1 branch ずつ **直列** で実行する。for loop や 1 行ずつ手打ちする

### chain 対象 branch を force push / squash する

- **やってはいけない例**: chain の root/中間 branch に積んだ commit を「整理したい」という理由で squash し、force push する
- **害**: 2 方向に影響が伝播する。(1) 既に GitHub 上の comment 本文が特定 commit hash を参照している場合、squash で hash が変わり参照先が消えるか無関係な内容になる (2) 対象 branch が既に `chain-propagate.sh` で下流へ merge 済みの場合、下流 branch の merge commit は書き換え前の (存在しなくなる) commit を parent として指したままになり、chain 全体の history が壊れる
- **正しい進め方**: force push の前に必ず次の 2 点を確認する。(a) `gh api repos/<owner>/<repo>/pulls/<num>/comments --jq '.[] | select(.body | test("[0-9a-f]{7,40}"))'` 等で、対象 commit hash を本文に含む投稿済み comment がないか (b) 対象 branch が root/中間として既に下流へ伝播済みでないか (`chain-status.sh` で下流 branch の parent commit を確認)。いずれかに該当する commit は squash 対象から外す
- **代替**: 非連続な commit の squash に対話的 rebase (`git rebase -i`) が必要な場合、この harness では使用禁止。安全に squash できないなら squash せず、関連 commit hash を返信文などで並記する方式に切り替える

## Gotchas

### rebase ではなく merge を使う理由

chain PR は force push すると reviewer の approval が消える / URL comment がずれる / 下流 chain の base が空中に浮く。**merge --no-ff で新規 merge commit を積む**方式なら force push 不要で、chain の commit history もそのまま維持される。今回の repo でも既存 chain 全て merge commit 方式で運用されている。

### `fatal: Unable to write index` は retry で解消

大量の worktree で並行に fetch / merge を実行すると index write が競合して失敗することがある。`chain-propagate.sh` は 3 回まで自動 retry する。手動運用時も同じ merge を 1〜2 回打てば成功する。

### worktree path 名と branch 名が一致しないケース

`git worktree list --porcelain` で worktree path と持ち branch を確認する。名前が入れ替わっているときは `git worktree move` で合わせる (直接 swap は不可、一時名を経由する)。

```bash
git worktree move path-a path-a.tmp
git worktree move path-b path-a
git worktree move path-a.tmp path-b
```

### behind=0 でも child 側の base が更新済みとは限らない

`gh pr list --json baseRefName` は PR の設定 base を返す。実際に merge が実行された base の SHA は `origin/<parent>` を fetch し直して `git rev-list --count` で見る。`chain-status.sh` はこの方式を使う。

### 更新後に flaky test が失敗したら再実行する

chain 内で同一 SHA でも fail / pass が分かれる場合は flaky。まず再実行を試す:

```bash
gh run rerun <run-id> --failed
```

同じ test が chain 上流の PR で pass、下流だけ fail するケースも rerun で成功することがある。連続 fail するなら test 側 or code 側の root cause 調査に切り替える。

### root branch (chain の起点) は main を merge した後で下流に伝播する

root が behind=N なら最初に `chain-propagate.sh <root-wt> <root-branch> main` を実行する。root を skip すると下流全部が古い main のままになる。

## Troubleshooting

### `fatal: '<branch>' is already used by worktree at '<path>'`

該当 branch は別 worktree で checkout 中。その worktree に `cd` して作業するか、`chain-propagate.sh` に該当 worktree path を渡す。

### `merge failed (attempt 3/3)`

3 回 retry しても失敗するときは conflict の可能性が高い。手動で `git -C <wt> merge origin/<parent>` を打って conflict marker を resolve し、`git commit` + `git push` する。

### `error: index file smaller than expected`

`.git/index` 破損。該当 worktree で `git reset` で index 再生成する。

## 検証済み動作

- 14 branch (admin 7 + app 7) を 1 run で main → 全 chain 伝播 (2026-07-22 実測、conflict 0、retry 1 回で完走)
- `chain-status.sh 30472-admin-2-reader` で BFS 走査 → 13 downstream pair 出力
