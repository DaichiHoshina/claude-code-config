---
allowed-tools: Bash, Read, Grep, Glob, mcp__serena__*
description: git 統合 — commit → push → PR/MR 作成を 1 command でまとめて実行する (mode auto 判定)
argument-hint: "[--pr]"
---

# /git-push - Git integration

Execute commit → push → PR/MR creation in single command.

## Current Git state

!`git status --short`
!`git branch --show-current`
!`git diff --stat`
!`git log --oneline -5`

## Mode detection

**main** (on main branch / `--main`) → commit → push to main ・ **pr** (feature branch / `--pr`) → commit → push → PR ・ **branch** (`--branch <name>`) → sync main → branch 作成 → commit → push → MR/PR。Auto-detect: no args は current branch で判定 (main → `main`, else → `pr`)。

## Options

`--main` / `--pr` / `--branch <name>` / `--draft` (Draft PR/MR) / `-m "msg"` (commit msg 指定) / `--auto-review` (`/code-review` + `coderabbit:code-review` を post-PR create 並列起動、**opt-in, pr mode のみ**、CodeRabbit は external API 課金あり) / `--no-impl-notes` (PR body draft の IMPL_NOTES MERGED.md 消費 skip、pr mode のみ)

## Flow

### Common

1. Check state (`git status --short` / `branch --show-current` / `diff --stat` / `log --oneline -5`)
2. **Writing pre-check** (commit msg 生成前): `references/writing-check-protocol.md` 参照 (対象: commit message、`/git-push` / 直接 `git commit` 共通経路)。連続漢字 5 字以上の複合語は助詞挿入か訓読みで開く (structural warn 最多 pattern の先手 sweep)。Hook (`pre-tool-use.sh`) が `git commit` で block する前に解消する。
   - **直近 block 語との照合**: 初稿を書いた後、`awk -F'|' '/block$/{print $3}' ~/.claude/logs/jp-quality-block.log | tail -n 100 | tr ',' '\n' | sort -u` で直近の block 語 list を取り、初稿に 1 件でも含まれていないか grep する。含まれていたら書き直してから commit する (自分で追加した NG 語を自分の commit で使う事故の再発防止。2026-09-18 実測: 1 session で 5+ 回発生)
3. Uncommitted changes present → analyze diff → generate Conventional Commits msg → confirm w/ user → commit

### main mode

3. `git push origin main`
4. **ai-tools repo only**: `./claude-code/sync.sh to-local` (skip confirm w/ `echo y |`)
5. Display result

### pr mode

3. `git push -u origin <branch>`
4. **IMPL_NOTES detection** (skip on `--no-impl-notes`): `~/.claude/plans/impl-notes/` 配下で current branch (kebab-case 正規化) に一致する `<feature-slug>` dir を探索。複数なら timestamp prefix 最新を選び、`MERGED.md` があれば **Design decisions** + **Open questions** を PR body draft 候補として user confirm step に提示する (auto-insert はしない)。Open questions は `guidelines/writing/pr-description.md` `## 残論点 (Open questions) の書き方` の形式 (各案の利点・代償 + 推奨 + 理由) へ整形してから提示する。No match は silent skip。
4.5. **PR 前 self-review gate** (Go repo のみ): レビュー往復の最頻出 pattern (comment / godoc 削除 45%、test 規約・慣習系 55%) を PR 前に解消するのが目的 (導入根拠と撤退条件: `docs/reports/dev-workflow-base-first-improvement-20260810.md`)。
   - `~/.claude/scripts/check-comment-deletion.sh` を実行し、diff で削除された既存 comment / godoc を PR 作成前に検出する (exit 1 なら削除が意図的か確認し、意図的なら `SKIP_COMMENT_CHECK=1` で再実行して通す)
   - PR の base が main 以外なら第 1 引数に base-ref を渡す (`check-comment-deletion.sh origin/<base>`)。省略すると origin/main と比べるので、release ブランチ自身の差分が削除 comment として誤検出される
   - repo に coding / testing 規約 skill (`go-coding` / `go-testing` 等) や `code-comment` / `review-member` skill があれば、diff への checklist として当ててから PR を作る
   - script 不在の repo 環境では skip + warn 表示

4.6. **comment 語彙 self-review (skip 不可)**: skill の判定を根拠にしない。`git diff <base>...HEAD -- '*.go' '*.ts' '*.vue' '*.tsx' '*.js'` から `^\+\s*(//|#|--|/\*)` で新規追加 comment を全部拾い、1 件ずつ「reviewer がこの句を読んだとき『X とは?』と問い返す語がないか」を確かめる。焦点は次の 3 型で、guideline (`guidelines/writing/code-comment.md` 「状況を自作の名詞句に縮めない」) の該当例と照合する。
- 状況を短い自作の名詞句に縮めた句 (「〜化」「〜側」「〜局所」「両方の値」「片側」「残留」「共有点」「最小構造」等)
- 対処側のラベルだけで目的が書かれていない句 (「〜として固定する」「〜局所で定義する」「〜対象」等)
- 業務用語・設計用語 (没収 / grandfather / 最低サポート / 不整合 等) を初出で括弧説明なしに使った句

3 型に当たったら書き直すか、その comment 自体を消す (guideline 「review」 で意味を問われた comment)。書き直しは skill の OK 判定を目安にせず、自分が「読み手は句の外から補わずに状況を復元できるか」を口に出して確かめる。skip する option は用意しない (skill 採点と reviewer の反応がズレる場合があると 2026-08-24 の PDCA で確定した。commit `de097eac` / `d6cd4382`)。
4.7. **未返信 review comment の件数表示** (branch に open PR が既にあるときのみ): `gh pr view --json number,reviews` で PR 番号を取り、`gh api repos/{owner}/{repo}/pulls/<n>/comments` の inline comment のうち自分の返信が付いていない thread 数を 1 行で表示する (「未返信の review comment が N 件あります。対応は `review-reply-draft` / `/self-review-fix`」)。block も自動返信もしない。4.5 (comment 削除検出) / 4.6 (comment 語彙) とは別軸で、追加 push の時点で未対応の指摘に気づく材料を出すのが目的。`gh` 不在や GitLab は skip。
4.8. **節構成と title の印**:
   - **節構成**: repo に `.github/pull_request_template.md` があればその節をそのまま使って body draft を組み、無ければ `guidelines/writing/pr-description.md` 「テンプレ (repo template が無い場合)」の節を使う。確認してほしい点は `## レビュー観点` (節が無ければ `## 実装概要` の冒頭)、挙動の変化は `## 影響範囲` の 1 行目、連続する PR の何本目かは `## 背景` か `## 備考` へ記載する (「chain」は外向き text に書かない) (`guidelines/writing/pr-description.md` 「節への配置」)
   - **「変わらない」の判定**: 下記いずれかに当たれば diff は「変わらない」。作業計画書 (SPEC) に「既存挙動:」の列があればそれを正とする

     | パターン | 確認方法 |
     |---|---|
     | 新規 symbol の production 参照が 0 件 | `grep -rl` で呼び出し元なし |
     | I/F 変更だけ | diff を目視 |
     | migration だけ | diff を目視 |
     | 削除だけ | diff を目視 |
     | flag で守られている | 「<flag 名> を ON にした時だけ変わる」と書く |

   - **title の印**: 「変わらない」と判定したら title に repo の印 (`[確認不要]` 等。repo の直近 merged PR の title で慣習を 1 度確かめる) を付ける。判定に迷う diff は「変わる」と決めつけず、変わる箇所を 1 つ書いて user に見せる
5. `gh pr create` / `glab mr create` (auto-detect remote)
5.5. **writing check (PR body)**: `references/writing-check-protocol.md` 参照 (対象: PR body draft)。加えて次の 2 つを検査してから作成・編集する (`guidelines/writing/pr-description.md` §抽象度の線引き。`gh pr edit` での追記も同じ検査を通す)。(a) body draft の `## 実装概要` より前の範囲を `grep -cE 'ALGORITHM=|LOCK=|FOR UPDATE'` で数え、1 件でも hit したらその根拠を `## 実装概要` の下位の項目か `###` の見出しへ移す。(b) body draft 全体を `grep -nE 'Error [0-9]{3,5}|SQLSTATE|exit [0-9]{2,3}'` で探し、hit した行に日本語の説明が無ければ「何が起きるか」を日本語で書き、番号は括弧で添える形に直す。PR body の issue/PR URL は `gh issue view` / `gh pr view` で番号存在を事前検証する (`references/on-demand-rules/ai-output.md` `## URL / Issue & PR Number Validation`)。
6. Display PR/MR URL
7. **Auto-review** (`--auto-review` only, GitHub only, default OFF): `/code-review:code-review <PR#>` と `coderabbit:code-review` を `Bash run_in_background:true` で並列起動 → `BashOutput` で順次完了確認。成功は PR comment 投稿を user に表示、失敗は tool 名 / exit code / stderr tail 10 行を表示 (PR 作成自体は成功扱い)。GitLab/`glab` 環境は skip + warn 表示。

### branch mode

3. Refresh main → create branch (`git stash` → `checkout main && pull` → `checkout -b` → `stash pop`)
4. Same as pr mode 3-7

## Remote judgment

```bash
git remote get-url origin | grep -q "gitlab"   # GitLab → glab, else gh
```

**Judgment impossible** (`git remote get-url` fail / origin unset): stop at push stage, guide "remote unset — run `git remote add origin <url>`". Skip PR/MR create.

## Commit message

Conventional Commits format: `<type>(<scope>): <subject>`

## PR description

**Canonical**: `guidelines/writing/pr-description.md` (ai-tools, all-repo priority). 該当する section だけを残し、本文全体を抽象的な日本語の bullet + インデントでミニマルに記載する (canonical 「既定形」)。`Closes #XXX` linking / anti-patterns / review-response 規約は canonical を参照する。この command の writing check (step 5.5) は `references/writing-check-protocol.md` と `PRINCIPLES.md` の「文章生成の不変条件」に従う。

**Testing section honesty (canonical 補足)**: Verified → specific commands + results (`go test ./... pass, staging p99: 320ms`). Unverified → no fabrication, state explicitly (`Not run — docs-only` / `Manual only — ...` / `N/A — build config only`).

## Jira ticket link

Post-push/MR-create, if Jira ticket ID in commit msg or branch name, auto-comment MR/PR URL to ticket w/ `mcp__jira__jira_post`. ID not detected: warn only, push/MR create success (Jira integration is auxiliary, don't block main flow).

Auto-comment body は `references/on-demand-rules/ai-output.md` と `PRINCIPLES.md` の「文章生成の不変条件」に従う。PR URL と確認済みの変更概要だけを自然な日本語で伝え、`Conclusion` / `Reason` / `Next action` label、未確定の reviewer、作業工程を補わない。

## Cautions

- force push forbidden。**amend push flow**: user が「amend push」「amend して伝搬」等と指示したら、amend までを AI が行い、push は `! git push --force-with-lease origin <branch>` の copy-paste 行を提示して user 実行に委ねる (`!` prefix で出力が会話に入る)。deny rule の別 tool 迂回はしない。amend 対象 commit が push 済みかつ chain の上流 branch なら、下流 merge の parent 参照が壊れるため amend せず理由を報告する
- Pre-commit user confirm required
- Behind remote → propose pull

## Error handling

No changes → "Already up to date" で終了 / reject (conflict) → `git pull --rebase` を提案 / stash pop fail → conflict 表示 + 手動解消を誘導 / Auth error → SSH key / token 確認を誘導 / PR/MR create fail → push 済 branch URL を表示 / Auto-review fail → PR 作成は成功、review error は warn のみ (PR URL は既に表示済)

ARGUMENTS: $ARGUMENTS
