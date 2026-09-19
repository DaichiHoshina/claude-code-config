# chain PR の main merge は上流から順次伝播

`base = main` 以外の PR (chain PR) が並んでいるとき、全 PR に並列で `git merge origin/main` を実行しない。差分肥大の原因になる。

## 原則

- **普段は main merge しない**: chain PR の `base ↔ head` diff は GitHub UI が正しく見せる。差分が古いだけなら merge しない
- **本当に必要なときのみ実施**: conflict 解消 / 重要 security 取り込み / リリース直前の同期など
- 実施するときは **最上流 PR (base=main)** から順に伝播させる。**下流 PR は `git merge --no-ff origin/<upstream-pr-branch>`** で上流 PR の HEAD を取り込む (origin/main ではなく)
- 「全 PR に一括 main merge」は禁じ手。**並列 main merge は禁止**

## Why

base と head が異なる merge commit (同じ main HEAD を取り込んでも直前の commit が違う) を生じさせると、`base ↔ head` diff に「main の数千 commit 分」が紛れ込みレビューが破綻する。過去に chain 5 PR で並列 `git merge origin/main --no-ff` を実行した結果、head PR で `+31516 / -5350 / commits=100` の異常な肥大が発生した。

## 手順 (canonical)

```bash
# 最上流 PR (base=main) — main を取り込む
git switch <upstream-pr-branch>
git merge --no-ff origin/main
git push

# 下流 PR — 上流 PR の HEAD を取り込む (main ではない)
git switch <downstream-pr-branch>
git merge --no-ff origin/<upstream-pr-branch>
git push

# chain が続く場合は 1 段ずつ順次伝播させる
```

## 差分肥大に陥った場合の復旧

各 chain PR の head に `git merge --no-ff origin/<base-pr-branch>` を上流から順次実行する。base と head の merge commit が揃い、`base ↔ head` diff が本来スコープに戻る。

## chain 運用の追加規約 (実案件で確立)

- chain branch への push は **fast-forward / merge commit のみ、force-push 禁止**。下流 branch との整合性を壊す。PR base の付け替え時だけ user 承認の上で rebase + force-push する
- 薄すぎる PR (数十行規模) は上流 PR へ統合する。PR title に `n/N` の chain 番号を付ける
- branch ごとに linked worktree を分離し、修正 commit は「差分が属する層の branch」に入れて base 側から順に下流へ伝播する
- shallow clone の worktree は merge-base が切れて chain merge に失敗する → `git fetch --unshallow` で復旧する
- dev 検証用の巨大 branch は分割 PR 完成後に close し、chain 末端 PR を deploy 起点にする

## chain 構造は必ず gh で確認する (思い込み補正)

chain の branch と PR の対応、および各 PR の base branch を「番号順」「branch 名の連番」から推測しない。番号が飛んでいたり、途中で fork した branch が挟まると、思い込みで別 PR に main-merge を流し込む事故になる。

- 各 PR の branch を `gh pr view <PR> --json headRefName,baseRefName,number,title` で全件確認する。上流から順に列挙して 1 表にする
- branch 名の見た目の連番 (`foo-be-1` / `foo-be-2` / `foo-be-3`) が chain の順序と一致すると仮定しない。base が別の branch を指している例がある
- session の途中で user が「be-2 から」と発言した内容は、番号でなく branch 名として受け取る。同じ番号でも「PR 2 本目」「branch be-2」「Phase 2」が別対象を指す場面がある
- 3 本以上の chain では上流 PR に対して `gh pr view` を全件走らせて 1 度書き起こし、伝播 script (`chain-propagate.sh` 等) の引数はその表から引く

`chain-propagate.sh` の `grandparent` 引数はこの表があってはじめて正しく渡せる。表がないまま推測で渡すと、下流 PR に別 chain の HEAD を混ぜる事故につながる。

## chain 自体を減らす検討

- 通常 PR は `base = main` の独立構成にし、chain は本当に必要なときのみ使う
- chain が常態化するなら spr / graphite などの PR スタック tool 導入を検討する

## 適用範囲

- 全 repo (組織を問わない)
- chain PR を運用する場面
- user 指示で「全 PR に main merge」を要求された場合は、上流から順次伝播の手順を提示してから実行する (並列処理しない)

## 参照

- CLAUDE.md `## Git Merge Prohibition`
- `references/on-demand-rules/worktree-branch-name-match.md`
