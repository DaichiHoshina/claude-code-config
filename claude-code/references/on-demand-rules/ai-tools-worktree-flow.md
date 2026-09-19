# ai-tools worktree 作業フロー (main 直接作業の禁止)

ai-tools repo では **main で直接作業せず、worktree を切って隔離作業する**。main の直接編集は config (hooks / commands / skills) を sync 経由で即 live に影響させかねない。検証前の壊れた状態が混入するのを防ぐ。dir 名と branch 名の一致規約は `worktree-branch-name-match.md` を参照する。

## 定着手順

1. main に未 commit 変更があれば `git stash push -u -m "<desc>" <files>` で一時的に移動し、main を clean にする。**移す対象は自分が編集した path だけに限定する** (`<files>` 省略の全移動は禁止)。由来の分からない差分が含まれていたら、別 session が作業中の疑いがあるので移さず止まって user に確認する (`git-safety-ops.md` 「同一 checkout を複数 session が触るとき」)
2. `EnterWorktree` (または `git worktree add ../ai-tools-wt-<topic> -b <topic>`) で wt を作成する
3. wt で `git stash apply` を実行し (drop でなく apply、main 側に stash を保持して保険にする)、作業と検証を済ませて commit する。commit 直後に `git log -1 --format=%H` で HEAD が進んだか確かめる (staged が空の commit は exit 1 で終わり、hook 出力に紛れて成功と読み違えやすい)
4. main への反映は元 repo 側で `git merge <wt-branch> --ff-only` を実行する。元 repo の main は別 worktree が checkout しているため、wt 内から `git checkout main` はできない。必ず元 repo path で操作する。**merge の直前に `git branch --show-current` が main であることを確認する** (cron の無人 repair が共有 checkout を別 branch に切り替えているタイミングがあり、気づかず merge すると別 branch へ入る。2026-08-23 実踏)。**commit と merge を同じ Bash call に連結しない** (wt で `cd` した call の続きで merge すると cwd が wt のままで `Already up to date` の no-op になり、直後の `git worktree remove` で cwd が消えて exit 128 になる。2026-08-30 に同 session で 2 回実踏)。merge 以降は元 repo の絶対 path で `cd` し直した別 call で始める
5. ff-only merge 時に元 repo の未 commit 差分が衝突したら、wt commit と内容の一致を `diff` で確かめてから `git checkout --` で破棄する (一致確認は必須、破壊操作)
6. `git push origin main` を実行し、live 反映が必要なら `./claude-code/sync.sh to-local --yes` を続ける
7. 後始末では不要 stash を drop し (`git stash list --format='%gd %H %gs'` で ref と SHA を確かめてから `git stash drop 'stash@{n}'`)、commit が main に含まれることを `git branch --contains <sha>` で確かめてから `git worktree remove` + `git branch -d` で wt を削除する。`hooks/worktree-remove.sh` が `~/.serena/serena_config.yml` から実体の消えた project 登録を削除するので、手で消す必要はない (hook が実行されない経路で削除したときだけ、次回 worktree を削除する時にまとめて掃除される)

## 注意点

### 運用方針

- PR は基本不要で、ff-only の main 直接マージ運用とする (user 合意 2026-05-31)
- `git merge` / branch 削除は通常 user 確認が必須の破壊操作だが、この repo の wt フローは合意済みパターンとして確認不要とする
- **`/promote` の文章 SoT 統合は main 直編集を許す** (2026-08-26 決定)。`rules/` / `guidelines/` / `references/` / CLAUDE.md 系への 1-3 行の追記は、隔離しても防げる事故がなく worktree 往復の cost に見合わない。ただし `hooks/` / `scripts/` / `lib/` / `skills/` / `commands/` を変更する promote は通常どおり worktree を切る。どちらの場合も統合先 file を `grep -rl <file名> tests/` で逆引きして bats を実行してから閉じる (文章 SoT にも本文を grep する contract test と 3 tool の drift 検出 test が掛かっている)。canonical: `commands/promote.md` Step 4b / 4c

### worktree を切る前

- worktree の前提は「未編集の状態から切る」こと。main を編集済みなら branch commit 方式に切替える (`worktree-branch-name-match.md` の後退手順 (B))
- **git 管理外の file を変更する task では worktree を切らない** (2026-07-26 / 2026-07-27 実踏)。gitignore 対象 dir (`/memory/` 等) と untracked file は worktree にコピーされないため、切っても対象が存在せず何も起きない。worktree 判断の前に対象の tracked 状態を確かめる。ignore なら `git check-ignore -v <path>`、初 commit なら `git status --short` の `??` prefix で見る。どちらも main で直接編集する
- **未 push commit があると diverge する** (2026-07-11 実踏)。worktree を origin/main から分岐させると、local main の未 push commit を含まない branch になり、`--ff-only` merge が fail する。対処は 2 つある。(a) wt を切る前に push しておく。(b) 発生後なら wt commit を main へ `git cherry-pick <sha>` する (行が重ならなければ clean に入る)
- **`git worktree add` の path は絶対 path で書く** (2026-07-20 実踏)。相対 path は cwd 基準で解決されるため、cwd が `<repo>/claude-code` のサブ dir だと `../ai-tools-wt-<name>` が `<repo>/ai-tools-wt-<name>` (repo 内部) にネストして作られる。3 手いずれかを守る: (1) 絶対 path で書く (`$(git rev-parse --show-toplevel)/../ai-tools-wt-<name>` を展開した実 path) / (2) Bash tool call の先頭で `cd <repo-root> && git worktree add ../...` と repo root への `cd` を必ずセット / (3) 作成後に `git worktree list` で actual path を verify してから mv 等を続ける

### stash の扱い

- **他 session が同じ checkout で作業している疑いがあるときは stash を使わない** (2026-08-22 実踏)。`refs/stash` は repo 共有で、全部を移動させると相手の編集途中の差分まで移動させる。変更を wt へ移動するなら patch 移送に切り替える (main 側で `git diff <files> > <tmp>/wip.patch` を取り、wt で `git apply` する)。移動された側は `git stash list --format="%gd %cs %s"` の時刻で自分の差分を特定し、`git stash apply <ref>` で戻す
- `git stash drop` は **ref を省いた形だけ** permission deny される (`stash@{0}` を無条件で消すため)。ref を明示すれば AI が実行できる (2026-08-23 実測、`git stash drop 'stash@{0}'` が成功した)。打つ前に `git stash list --format='%gd %H %gs'` で対象の ref と SHA を確かめる。stack は worktree 間で共有され、位置は他 session の push でずれる。`git stash clear` は stack を全消しするので使わず、必要なら user に依頼する。deny された command を別 tool で迂回するのは引き続き禁止 (deny-rule no-escalation)

### worktree 内での作業

- **worktree 内 file に Serena 編集 tool を使わない** (2026-07-13 / 2026-07-18 実踏)。Serena の project root は main repo 固定のため、relative_path が main 側に解決されて main を誤編集するか、成功報告しつつ worktree に反映されない silent fail になる。worktree では絶対 path の Read/Edit/Write を使い、subagent への delegation prompt にも同じ制約を明記する。誤編集した場合は patch 移送で復旧する (main 側で `git diff` を取って `git checkout --` で戻し、worktree で `git apply` する)
- **worktree 内で bats 全体を実行しない** (2026-07-19 実踏)。cwd-guard hook が test fixture の固定 path (`/tmp/x.go`) への Edit を「worktree 外への直接編集」と誤検知し、無関係な hook test が数十件まとめて `not ok` になる。大量 fail を見たら、fail 内容に cwd-guard の block 文言が含まれるか確かめる。含まれるなら実装の regression ではないので、main repo 側で同じ test を実行して切り分ける

### merge / push の前

- **ff-only merge は必ず元 repo path へ cd してから実行する** (2026-08-21 に同日 2 回、2026-08-29 にも同日 2 回実踏)。2026-08-29 の 2 回は commit と merge を 1 つの Bash call に `&&` でつないだせいで、cwd が worktree のまま `git symbolic-ref` の main 確認で失敗した。commit までと merge 以降は別の call に分け、merge 側の call は元 repo path の `cd` から始める。worktree 内で `git merge <wt-branch> --ff-only` を打つと自 branch への merge になり「Already up to date」で成功に見えるが、main は未反映のまま。その直後に worktree remove まで進むと cwd 消失で後続 command も fail する。復旧は元 repo で merge をやり直す (branch が保存されていれば commit は失われない)
- **ff-only merge と `git push origin main` を同じ Bash call に `&&` でつながない** (2026-09-05 実踏)。merge が「Not possible to fast-forward」で失敗しても、`| tail` で包んだ merge は exit 0 に見えて push が続き、別 session が main に積んだ未 push commit を自分が push する。merge の結果 (HEAD が wt commit に進んだか) を確かめてから、push は別 call で打つ。merge が fail したときは別 session の commit が main に含まれているので、`git log -3 main` で内容を見てから自分の commit を `git cherry-pick <sha>` する
- **ff-merge / push の前に `git symbolic-ref --short HEAD` で main 確認** (2026-08-23 実踏)。cron-auto-repair 等の headless 実行が元 repo に fix branch を checkout したまま終わることがあり、main のつもりの merge が別 branch 上に入る。症状は上と同じ「Already up to date」「Everything up-to-date」。`main` 以外が返ったらどの process が checkout したか確かめてから `git checkout main` で戻す。復旧は該当 branch を origin へ reset し、自分の commit を main へ cherry-pick する
