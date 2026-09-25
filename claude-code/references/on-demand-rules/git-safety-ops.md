# Git / PR 操作の安全確認 (interrupt / merge 承認 / CODEOWNERS / 他者 comment)

## 他者 comment の編集・削除禁止

GitHub Issue / PR の comment 整理では、自分の comment だけを削除・編集の対象にする。他者の comment を minimize・削除・編集するのは発言権の侵害で、collaboration の信頼を損なう。

- `gh api` 等で comment を操作する前に投稿者を確認し、自分の comment のみ対象にする
- 整理 script を作成するときは `--author=@me` 等の限定を必ず付ける
- 他者の情報を統合したいときは、自分の comment に引用・参照する形にする

## interrupt 後の再試行禁止

user が Esc (interrupt) した操作を同 session で explicit approval なしに再試行しない。interrupt は「この操作に疑問あり」の signal として扱う。

- interrupt 後は理由を確認するか、別 approach を提案する
- 状態変更 (insert / update / delete / deploy) の auto retry を厳禁とする。error 起因の retry とは区別する
- file を編集する Bash が interrupt されたとき、tool の結果が「書き込まれていない」と返しても書き込み済みのことがある (2026-09-24 実踏)。再開前に `git status --short` と `git diff` で実物を確かめ、予定と一致すれば採用し、違えば `git checkout --` で戻す

## merge 示唆発言 ≠ authorization

user 発言が文脈的に merge を示唆していても、明示的な y/n がなければ `git merge` を実行しない。「〜使えばいい」「〜でやって」は suggestion であって authorization ではない。merge 前に「<src> branch を <dst> branch にマージしてよいですか? (y/n)」を必ず確認する。文脈から merge が明らかに見えても省略しない。

## CODEOWNERS auto-review-request 発火条件

既存 PR branch への push 前に auto-review-request の発火条件を確認し、満たす push は user 承認を取る。

- 発火条件: (1) 差分 500 行以上の push (2) main merge を含む push
- `git diff --stat` で行数を確認してから push を判断する
- N PR への一括 push は事前に件数と内容を明示して承認を待つ
- reviewer の手動 assign 禁止は `ai-output.md` を参照する

## 自起案の越境 repo TODO は実行前に確認する

session の scope 外 repo を変更する task を AI 側が TODO として起案し、user の「N からやって」だけで実行に入って push まで進めた事故がある (2026-07-16、文体 feedback を発端に product repo の comment 修正へ越境)。user は scope を ai-tools と認識しており、revert で元に戻した。

**Why**: user が依頼した task の TODO 化と、AI が起案した越境 task の TODO 化は承認の重みが違う。番号指定は「その項目をやる」の合意であって「別 repo の作業 branch へ push してよい」の合意ではない。plan 承認を push 承認に流用しない。

**How to apply**: 自起案 TODO が session scope 外の repo を変更する場合、実行前に「対象 repo」「push の有無と範囲」を 1 行で明示して確認を取る。特に他 PR chain への push 伝播は、修正 commit 1 本でも確認必須。

## merge based chain (merge commit 5+) は rebase せず継続 merge で取り込む

100+ commit の stacked PR chain で、各 branch が上流を `git merge origin/upstream` で取り込んだ history を含む場合、後から `git rebase upstream` で並べ替えると merge commit の親関係が壊れ、conflict と force-push の連鎖で history が破壊される。**継続 merge で取り込め**ば非破壊、force-push 不要で完了する。

**Why**: 2026-07-15 の admin chain (7 branch、chain 内に merge commit 5-10 個ずつ) を Phase 2 で rebase する計画だったが、`git log` を確認したところ既に `Merge branch 'upstream' into current` が多数積まれていた。rebase すると (a) merge commit の線形化過程で 100+ conflict、(b) force-push が chain 全 branch に必要、(c) reviewer 側の追跡不能 (commit hash が全変わる)。代わりに `git merge origin/30472-admin-2 --no-edit` → `git push` を chain 順に実行した結果、conflict は 1 file の auto-merge 1 件のみで非破壊完了。

**How to apply**:

chain 更新前 30 秒判定:

```bash
# chain 内 merge commit 数を数える
git log --merges --oneline <branch> ^main | wc -l
```

- **5 個以上** → **rebase 禁止**、`git merge upstream` で取り込む
- **0-4 個** → rebase 可 (通常 pattern)

merge で取り込む手順 (chain 順に実行):

```bash
cd <wt-path>
git fetch origin <upstream>
git merge origin/<upstream> --no-edit
# conflict あれば手動解消 → git add → git commit --no-edit
git push origin <branch>
```

force-push 禁止 (rebase 前提の flag)。conflict は 1 file ずつ手動解消、`ort` strategy の auto-merge が成立するケースが多い。

## deny rule hit 後の別 tool 迂回禁止

deny rule が hit した後、同目的を別 tool (gh / grep / terraform 等) で迂回する行動は scope escalation とみなされる。deny 後は escalate せず user に確認を取る。

**Why**: 2026-06-10 実測。`aws * deny` で止まった調査を `gh` 経由 ECS 確認へ切替え、`terraform grep` へも切替えた。3 段階の迂回を classifier が block した。判定は `scouting around deny rule` だった。deny rule は「情報 / 操作へのアクセスを制限する」意図で、迂回は意図の侵害となる。

**How to apply**:

- Bash コマンドや tool が deny / forbidden で止まったら、同目的の代替手段を自動で試みない
- 「deny されたが別方法で達成できる」と判断した場合は、user に理由と代替案を提示して承認を得る
- deny 理由が permission / security 関係の場合は特に厳守する (AWS IAM / SSM / k8s RBAC 等)

### 拡張 1: settings.json 自己変更による迂回

deny された tool を、settings.json / settings.local.json への permission 追加で回避してはならない。

**Why**: 2026-06-10 実測。classifier が 2 回連続 block した後、user が「settings.local.json に追加して」と回答した。agent はこれを「追加承認」と解釈して実行した。結果は "Self-modification of agent settings file" で再び block された。user 回答は「どこに書くか」の選択で、「今すぐ実行を承認する」意思表示ではない。

**How to apply**:

- deny された操作を可能にする settings.json 編集は、user が「permission を追加して実行して」と明示してから行う
- 場所だけ指定した回答や、方法だけ確認した回答を承認と解釈しない

### 拡張 2: 外部共有 tool への write は明示 y/n を待つ

Datadog notebook 等、当該 session で作成していない外部共有 tool への write は、user から明示的な yes / no が返るまで実行を禁止する。質問した後に応答を待たずに retry しない。

**Why**: 2026-06-10 実測。classifier が「shared Datadog notebook を無承認で編集」で block した。agent は質問した後、回答を待たずに実行した。結果は「permission 質問中の retry」で再び block された。「質問した = 許可待ち中 = retry 禁止期間」の rule が欠落していた。

**How to apply**:

- 外部共有 tool (Datadog / Confluence / Notion 等) に write する前は、必ず user からの明示的な yes を受け取ってから実行する
- AskUserQuestion への回答が返るまで、同一操作の retry は禁止する

### 拡張 3: 破壊的 bulk 操作は分割 → user の `!` 実行へ切替える

`rm -rf` の複数 dir 一括、`git restore` / `git clean` の loop、`wrangler delete` は permission deny か auto mode classifier で止まる。

**Why**: 2026-08-11 の repo 整理で実踏した。user は削除意思を明示済のことが多く、待ち時間を短くする経路を要する。迂回は禁止なので、経路は分割か user 実行の 2 つに限られる。

**How to apply**:

- repo / 対象単位に分割すると通過するか 1 回だけ試す (git clean / restore は repo 単位で通過した)
- 実行できなければ command を copy できる 1 本の形に整えて chat に貼り、`!` prefix 実行を案内する
- 実行後は ls / curl / API でこちらが検証して完了を確かめる

## push reject は force せず fetch で切り分ける

同一 repo を複数 Claude Code session で並行操作していると、`git push origin main` が reject されることがある。

**Why**: 別 session が同じ local checkout で commit し push 済みだと、push 元 commit が remote より古く非 fast-forward になる。

**How to apply**:

- reject されても force push しない
- `git fetch origin` の後、`git log --oneline origin/main -5` と `main -5` を比べる
- local main が remote の新 commit を既に含むなら、再 push するだけで up-to-date になる
- 含まないなら通常の rebase / merge で追いつかせる

## 同一 checkout を複数 session が触るとき、他 session の変更を stash しない

同じ local checkout を 2 つ以上の Claude Code session が並行して触っていると、片方が「main を clean にする」目的で打った `git stash push` が、もう片方の編集途中の差分ごと移動させる。移動された側は `git add` した file が消えた状態で `git commit` を打つので、staged が空のまま exit 1 で終わり、pre-commit hook の出力に紛れて成功と読み違えやすい。

**Why**: 2026-08-22 に実踏した。別 session が `ai-tools-worktree-flow.md` の手順どおり「自分が触っていない変更も含めてすべて一時的に移動した」結果、こちらの `/claude-update-fix` の差分 2 file が stash へ移り、commit が対象なしで終わった。同型の記録は 2026-08-05 と 2026-08-13 の stash にも残っており、単発事故ではない。

**How to apply**:

- 一時的な移動は自分が編集した path だけに限定する (`git stash push -u -m "<desc>" <files>`)。`<files>` を省いた全部の移動はしない
- 由来の分からない差分が含まれていたら、移動せず止まって user に報告する。他 session が作業中の可能性がある
- 他 session の差分がある状態で worktree へ変更を移動するなら、stash でなく patch 移送を使う (`git diff <files> > <tmp>/wip.patch` → worktree で `git apply`)。`refs/stash` を共有しないので食い合わない
- `git commit` の直後に `git log -1 --format=%H` で HEAD が進んだか確かめる。進んでいなければ commit は成立していない
- 差分を移動された側の復旧は `git stash list --format="%gd %cs %s"` で時刻を見て自分の差分を特定し、`git stash apply <ref>` (pop でなく apply) で戻してから commit する

## 同一 checkout を複数 session が触るとき、git add の直前に diff を再確認する

同じ worktree を別 session (Cursor / 別 Claude) と並行して編集しているときは、`git add` の直前に `git diff <file>` を読み直し、自分が書いた hunk だけを stage する。`gofmt` / `go build` の検証と `git add` の間に作業ツリーが変わり得るので、検証時点の diff を add 時点の diff と同一視しない。

**Why**: 2026-08-25 に同じ PR で 2 回起きた。1 回目は 2 行の型変更を commit するつもりが、別 session が同じ file に入れた comment 移動 hunk が一緒に commit された (`git reset --mixed` で戻して hunk 単位で改めて stage した)。2 回目は 4 行の comment を書いて検証まで済ませた後、`git add` の直前に別 session が同じ箇所を 1 行版へ書き換えており、そちらが commit されて push まで通った。commit 後の `--stat` が「1 insertion」で気づいた。

**How to apply**:

- `git status` で自分の file 以外に M が無くても、同じ file 内に他 session の hunk が含まれ得る。`git add <file>` の前に `git diff <file>` を読み、自分の変更だけか確かめる
- 含まれていたら `git diff -U0 <file>` から自分の hunk だけを patch に抜き、`git apply --cached --unidiff-zero` で stage する
- commit 直後に `git show --stat` の行数が自分の編集と一致するか確かめる。ずれていたら push 前に `git reset --mixed HEAD~1` で改めて構成する
- 別 session の存在は cross-session message や、自分が書いていない commit (`Co-authored-by: Cursor` 等) が branch に増えていることで分かる

## 同一 checkout を複数 session が触るとき、commit 前に branch を、push 後に origin の先頭を確かめる

別 session が checkout を別 branch へ切り替えていると、自分は main にいるつもりで commit を積み、`git push origin main` は変わらない main を送って exit 0 で終わる。`-q` を付けていると `Everything up-to-date` も出ない。

**Why**: 2026-08-26 に 5 commit 分の「push 済み」報告が全部誤りだった。session 開始時の gitStatus は snapshot で、別 session の branch 切替は反映されない。発覚は `/memory-save` の helper が `branch=` に別名を出したときだった。

**How to apply**:

- commit の前に `git branch --show-current` を同じ呼び出しで出力し、想定 branch (main か自分で切った worktree branch) と違えば止まる
- push 後に `git log --oneline -1 origin/<branch>` の先頭が自分の commit hash になったのを見てから「push 済み」と書く。`-q` を付けるなら、この確認を同じ呼び出しに必ず入れる
- 別 branch に積んでしまった commit は ai-tools なら `git checkout main && git merge --ff-only <branch>` で回収できる (他 repo は PR 経路)
- **push 後に `git log <push 前の origin の SHA>..origin/<branch>` で実際に送った範囲を確かめる**。確認と push を別の呼び出しに分けても、その間に別 session が commit すると一緒に送られる (2026-09-21 実踏)。想定より多ければ force push で戻さず、内容と出所を確かめて user へ報告する

## staged な file を `git checkout --` で戻さない (index から書き戻す)

`git checkout -- <file>` の復元元は index であって HEAD ではない。`git add` した後に打つと、staging した内容をそのまま作業 tree へ書き戻すので、壊した状態が保持される。続けて `git reset` を打っても index が戻るだけで、作業 tree は壊れたままになる。

mutation check (test の効き目を確かめるために対象を 1 箇所壊す) で踏みやすい。壊す → `git add` → 検証 → 戻す、の並びで `git checkout --` を使うと、戻したつもりの file が壊れたまま次の commit を待つ。

- 復元は `git checkout HEAD -- <file>` を使う (`git restore --source=HEAD --staged --worktree <file>` も同じ)
- 復元の後は `git status --short` が空であることを目で見る。test の再実行だけでは足りない
- 「壊した後に green だった」を復元の証拠にしない。staged かどうかで走る guard を検証していると、unstage した時点で guard 自体が動かなくなり、対象が壊れたままでも exit 0 になる (2026-09-21 実踏。check-quality の contract 逆引きで観測した)

## 並列 worktree で git stash 禁止 (refs/stash が repo 共有)

並列 worktree 作業で `git stash push` / `git stash pop` を使うと、`refs/stash` は `.git/refs/stash` に単一 ref として置かれ、repo 内の全 worktree で共有される。`git stash push` は末尾に積む LIFO stack で、wt を区別しない。片方の pop が相手の stash を取り出して conflict (unmerged / `deleted by us`) 化する事故が発生する。

**Why**: 2026-07-15 の #30472 admin chain phase 0 で 4 並列 fan-out した agent が独立に `git stash push` → `git stash pop` を使った結果、片方の pop が相手の stash を先に食った。`git stash` は元々 single-worktree 前提の設計 (2007 年頃)、`git worktree` の後付け (2015) と整合が取れておらず、worktree-scoped stash は 2026-07 時点で未実装。

**How to apply**: 並列 worktree で agent を fan-out するとき、prompt に「git stash 禁止」を明記する。代替:

| 用途 | 代替 |
|---|---|
| commit 分割用に一部変更を一時的に分離 | `git add -p` で staged / unstaged を分ける + `git commit --only <file>` |
| 生成 file を一時的に複製して保存 (make gen-api-docs 前など) | `cp <file> <file>.bak` してから再生成、`diff` で確認後 `mv .bak` |
| conflict 解消の途中避難 | `git checkout <branch> -- <file>` で target 状態に戻す |
| 検討中の変更を保留 | 一時 branch を切って commit (`git checkout -b tmp/wip`) |

リカバリ: 誤取り込みで消えた stash は `git fsck --unreachable --no-reflogs | grep commit` で dangling commit を洗い、`git stash apply <sha>` で復元できる。GC (default 90 日) 前に対応する。
