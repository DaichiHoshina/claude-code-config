---
allowed-tools: Read, Bash
description: context を復元する - compaction 後に CLAUDE.md と auto-memory を再読み込みする
argument-hint: "[topic]"
effort: low
---

# /reload - Context Restore

Use after compaction (conversation compression) or when saying "continue". Restore context from auto-memory + 直近 work-context 本文。

> **Automation**: compact 直後は `session-start.sh` (source=compact) が復元手順を自動注入する。手動 `/reload` は compact 以外の context 復元でだけ必要になる。PostCompact hook は context を注入できない仕様なので復元経路には使わない。

> **vs session-start.sh**: session-start runs auto at session start with memory load. `/reload` is **post-compaction re-restore** only.

> **設定同期後には使わない**: `/reload` は memory を復元するだけで、起動中 session が保持している command / skill / guideline / plugin の指示を更新・破棄しない。command / skill / agent の定義 file は sync 後の次の呼び出しから反映される (2026-09-05 実測。再起動は不要)。CLAUDE.md や rules のように session 開始時に注入される資産を変更した場合は `/clear` または session 再起動を使う。

> **CLAUDE.md compliance**: Serena `.serena/memories/` は read/write 禁止。`~/.claude/projects/.../memory/` は参照しない (2026-06-26 廃止)。compact-restore は `<repo-root>/memory/` にあり、read + rm のみ行う。

## Usage

```bash
/reload                                          # fallback chain (compact-restore → MEMORY.md → 直近 work-context)
/reload work-context-20260629-foo                # 名指し fast path (<repo-root>/memory/<name>.md)
/reload foo                                      # prefix match、無ければ MEMORY.md の [clear] foo entry を取得する
```

`/memory-save` (全 mode) が pbcopy する `/reload <topic>` が paste されると名指し経路で復元する。どの mode も個別 file を作成するため通常は step 1-3 の Read で復元する。個別 file を保持しない旧 clear 保存分のみ MEMORY.md の `[clear] <topic>` entry を直近 state の source として取得する (名指し fast path step 4)。`/memory-save` が生成する恒久ナレッジ (`feedback-<slug>.md` / `project-<slug>.md`) も日付 prefix なしの通常 file なので、`/reload <slug>` の step 2 (`<repo-root>/memory/<arg>.md`) でそのまま復元できる。

## Task Execution

Auto-execute the following:

### 1. CLAUDE.md は Read しない (skip)

`~/.claude/CLAUDE.md` と project CLAUDE.md は harness が毎 context に自動注入するため、Read すると二重読みになる (約 20KB/回 の無駄)。restore 対象は auto-memory のみとする。

### 2. Restore auto-memory

`$ARGUMENTS` (topic / name) が指定された場合は **`$ARGUMENTS` を最優先で Read** し、指定が無いときだけ fallback chain に降りる。

最初に dest を解決する: `MEM=$(bash ~/.claude/scripts/memory-save-helper.sh resolve-dir)` (org 配下 repo / worktree → `<ghq-root>/github.com/<org>/memory/<repo>/`、それ以外 → `<repo-root>/memory/`。`/memory-save` と同じ解決)。以下 `$MEM` はこの値。

```text
If $ARGUMENTS non-empty (名指し fast path):
  # step 4 は個別 file を保持しない旧 clear 保存分 (MEMORY.md 1 行 entry のみ) の互換
  1. Read $MEM/work-context-*-<arg>.md (glob で日付 suffix 吸収、`ls -t | head -1` で最新 1 件)。
     候補列挙が必要な場合も `ls -t ... | head -3` + `wc -l` の総件数だけ出す (広い topic は 100 file 級 hit するため全列挙を context に入れない)
  2. 上記 hit しなければ $MEM/<arg>.md (拡張子なし指定でも .md 補完) を Read
  3. まだ不在なら $MEM/ から prefix match で 1 件 Read。$MEM が <repo-root>/memory 以外 (org 側) の場合は
     <repo-root>/memory/ (汎用知見) も同順で探索 (memory file は SoT 適用外、Read OK)
  4. **旧 clear (個別 file なし、MEMORY.md 1 行 entry のみ) の互換**:
     clear_line=$(bash ~/.claude/scripts/memory-save-helper.sh find-clear-entry "<arg>")
     [ -n "$clear_line" ] && この 1 行を直近 state の source として採用 (topic / summary / commit)
  5. Step 1-3 で file が取れた場合、または Step 4 で clear_line が取れた場合、
     さらに B/C/E 段 (MEMORY.md 全体 / 直近 work-context 本文 / pending-improvements) も Read で補完
  6. Step 1-4 すべて該当なしなら fallback chain に降りる

Else (fallback chain、上から順に評価、ヒットしたら次 step も並行実行):
  A. compact-restore (pre-compact hook が書く一時 file、保存先は $MEM に依らず ai-tools 固定)
     latest=$(ls -t <repo-root>/memory/compact-restore-*.md 2>/dev/null | head -1)
     [ -n "$latest" ] && Read "$latest" && rm "$latest"  # 累積防止
  B. MEMORY.md (index、`/memory-save clear` が 1 行 entry を prepend する SoT)
     Read $MEM/MEMORY.md (400 行まで。index は全 memory file を記載するので行数が file 数に比例して増える。
     200 行で切ると末尾の分類済み章と「## 未分類 (reindex)」章が消える)
     先頭 1-3 行で当日 [clear] entry の <topic> / <summary> / <commit> を確認
  C. 直近 work-context 本文 (clear-aware — B 段と source を一致させ、古い本文を「直近 state」と誤読しない)
     mem_latest=$(head -1 $MEM/MEMORY.md 2>/dev/null | grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' | head -1)
     wc_file=$(ls -t $MEM/work-context-*.md 2>/dev/null | head -1)
     # wc_date は比較のため mem_latest と同じ YYYY-MM-DD 形式に合わせる
     wc_date=$(basename "$wc_file" 2>/dev/null | grep -oE '20[0-9]{2}[0-9]{2}[0-9]{2}' | sed -E 's/(....)(..)(..)/\1-\2-\3/')
     if [ -n "$wc_file" ] && [ "$wc_date" = "$mem_latest" ]; then
       # 同日 → 本文が直近 state の SoT。全件 Read はしない (日 5-9 file で 25KB 超)
       Read "$wc_file"
       ls -t $MEM/work-context-${wc_date//-/}-*.md | tail -n +2 | head -3  # 名前のみ 3 件まで列挙し /reload <topic> へ誘導 (総件数は同 glob の wc -l で別途 1 行出す)
     else
       # 本文が B 段より古い → 主 source は MEMORY.md [clear] entry 群。本文は補助として 1 件のみ Read し、summary で日付乖離を明示する
       [ -n "$wc_file" ] && Read "$wc_file"
     fi
  D. $MEM が <repo-root>/memory 以外 (org 側) の場合のみ追加 (汎用知見の index も見る)
     Read <repo-root>/memory/MEMORY.md (400 行まで、work-context の Read はしない)
  E. pending-improvements (未処理 item を surface)
     Read <repo-root>/memory/pending-improvements.md (存在すれば)
```

`$ARGUMENTS` 経路は `/memory-save` が pbcopy した `/reload <topic>` を検出するための fast path。個別 file があれば直接 Read、無ければ MEMORY.md の `[clear] <topic>` entry を source とする。

### 2.5 Worktree 復帰 (work-context に worktree field がある時のみ)

Step 2 で Read した work-context の frontmatter に `metadata.worktree` があれば実行する (無ければ skip):

1. **dir 存在 + cwd 不一致** → Bash で `cd <worktree>` する (cwd は Bash call 間で永続)。`git branch --show-current` が frontmatter の `branch:` と一致するか確認し、不一致なら切替せず warn を 1 行出す (wt 内 branch 切替禁止 rule と整合)
2. **dir 不在** → 「worktree `<path>` は削除済み (merge / cleanup 済の可能性)」と 1 行報告して cwd を維持する。main 側で `git log --oneline -3` を実行して merge 済かを補足する
3. 切替した場合の注意: session の permission scope / Serena active project は起動 dir 基準のまま変わらない。wt 作業を長く続けるなら「wt dir で session を再起動すると permission / Serena も一致する」と 1 行添える

### 3. Restore Summary

Report summary to chat (4 block 固定):

- **Loaded**: Read した memory file の list (compact-restore / MEMORY.md / work-context / pending-improvements)。同日の未 Read work-context は file 名のみ添えて「`/reload <topic>` で個別復元可」と 1 行案内する
- **直近 state**: MEMORY.md 先頭 [clear] entry (B 段) を主 source に task / progress / next-action を 3 行で要約する。work-context 本文 (C 段) が B 段最新 entry より古い場合は「本文は `<wc_date>` 時点、以降は MEMORY.md entry `<日付>` を参照」と日付乖離を明示し、古い本文を最新扱いしない
- **未処理 item**: pending-improvements.md から「進行中 / 保留」item を抜粋 (該当なければ「なし」)
- **Next action**: user 指示待ち、または直近 state (B 段が新しければ B 段、同日なら work-context) の next-action をそのまま提示
- (step 2.5 で worktree 切替 / 不在検出があった場合のみ) **Worktree**: 切替先 path + branch、または削除済みの旨を 1 行追加

## "Continue" Alternative

Use `/reload` instead of "continue":
- Prevents post-compaction context loss
- Full restore from auto-memory + 直近 work-context 本文
- Immediate resume of interrupted work

ARGUMENTS: $ARGUMENTS
