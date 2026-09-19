---
allowed-tools: Bash, Read, Write, Edit, Agent, AskUserQuestion, TaskCreate, TaskUpdate
description: Auto-memory housekeeping (trash / prune / audit)。`--import=<src>` で他 repo 取込、`--apply` で実行。
argument-hint: "[--apply] [--import=<src-dir>]"
effort: low
---

# /memory-clean - Memory housekeeping (auto-memory)

自 memory の housekeeping と、他 repo memory からの汎用 knowledge 取込を **1 command で完結**させる。**Memory dir auto-detect**: `<repo-root>/memory/` を優先、無ければ project の projects-memory dir (動的解決、`scripts/memory-save-helper.sh:_resolve_memory_dir` と同方式) を fallback。

> **Housekeeping guard**: mv (trash) / prune / 自動修正の対象は `<repo-root>/memory/` 配下のみ。projects/memory dir は fallback 検出時も scan (read) のみで、mv / rm / write はしない。対象には `work-context-*.md` だけでなく `/memory-save` が生成する `feedback-<slug>.md` / `project-<slug>.md` (恒久ナレッジ) も含む。ただし `exit` 産 file は日付 prefix を保持しないため trash 候補の対象外で、duplicate / orphan / cluster / xref-audit の対象にのみなる。

> **Policy**: `mtime` を value proxy にしない。auto delete は work-context (date prefix で短命明示、salvage 候補は保留) と description exact dup のみ。name prefix 一致は候補提示に留める (恒久 file 誤爆防止)。
>
> **No rm**: `.trash-YYYYMMDD-HHMM/` に `mv` (3 世代 retain) で rollback path 確保。**No style compression**: 容量削減の手段は削除・統合 (trash / prune / merge) に限り、本文を助詞落とし・英名詞連結の圧縮文体へ書き換えて token を減らすのは禁止 (肥大 warning 対応時も同じ)。memory は session 開始時に文体の模範として読み込まれるため、圧縮文体が以後の出力へ伝播する。
>
> **Out of scope**: Serena symbol DB → `/serena-update-fix`。Serena `.serena/memories/` 触禁止。

## Arguments (2 種のみ)

| arg | 動作 |
|---|---|
| (none) / `--dry-run` | 候補表示のみ、変更なし (default) |
| `--apply` | dry-run 結果を実行 (trash + MEMORY.md prune + 表記揺れ自動修正) |
| `--import=<src-dir>` | 他 repo memory (例: `<ghq-root>/github.com/<org>/memory/`) から汎用 knowledge を抽出して ai-tools に反映。`--apply` 併用で元 file 削除 + cross-ref 差替も実行 |

**他の細かい挙動は全て default 有効化** — flag で覚えなくて良い。

- `work-context` 7 日超 → trash 候補 (自動)。恒久ナレッジ signal を含む file は salvage 候補へ分離し、trash 保留 + `feedback-` / `project-` 昇格を提案
- MEMORY.md 先頭の `[clear]` entry は当日分 + 直近 3 件を超えた分 → prune 候補 (自動、file なし行のため trash 不要)
- MEMORY.md 8KB / 100 行超 → 肥大 warning (prune 後も超過なら chat で報告)。ただし index 行は file 数に比例して増えるのが正常なので、超過の内訳が link 行なら削減対象にしない
- MEMORY.md orphan / dead-link / index 未登録 (実 file はあるが link が無い) → 検出 (自動)。未登録は `--apply` で「## 未分類 (reindex)」章へ追記
- 恒久 memory 全 file の cross-ref の kebab ↔ snake 表記揺れ → 検出 + `--apply` で自動修正
- 削除済 memory への `[[..]]` 参照 → canonical 差替候補 / `{{deleted:}}` 記号化候補として提示
- topic cluster / small file / graduate 候補 → 提案表示 (auto merge しない)。small は merge 先 cluster がある場合のみ列挙 (完結した恒久ナレッジの短さは問題にしない)

## Flow

### Stage 1: dry-run (default、常に実行)

1. Memory dir 検出 (auto-detect)
2. **Auto-delete 候補列挙**:
   - `work-context-YYYYMMDD-*.md` で 7 日超 → trash candidate。恒久ナレッジ signal (detail 参照) を含む file は salvage candidate へ分離
   - MEMORY.md 先頭 `[clear]` entry の当日分 + 直近 3 件超過分 → prune candidate
   - `description` exact match → duplicate candidate (新 mtime keep)。name prefix 3 tokens 一致は提案のみ (`--apply` でも trash しない)
   - frontmatter `description` 欠落 → rescue candidate
3. **整合 audit**:
   - orphan (MEMORY.md にも他 file にも参照されない孤立 file) / dead-link (MEMORY.md link 先 file 不在) を検出。index 未登録は `bash ~/.claude/scripts/memory-save-helper.sh reindex` で別軸に見る (`[[cross-ref]]` が 1 つでもあると orphan 判定を免れ、index に含まれない file を検出できない。2026-08-24 に 63 件を実測)
   - **廃止領域への流入検出**: `~/.claude/projects/*/memory/*.md` と各 repo の `.serena/memories/*.md` (worktree 含む) に mtime が前回 run 以降の file があれば、file 名と mtime を「廃止領域への書き込み」として報告する (mv / rm はしない、移行は user 判断。detail 参照)
   - 恒久 memory 全 file の `[[name]]` cross-ref を検査: 表記揺れ (fixable) / canonical 差替候補 / `{{deleted:}}` 記号化候補 / 未作成 marker (note のみ、detail 参照)
4. **提案候補**:
   - topic cluster (`feedback_<topic>_*` snake 表記 または `feedback-<topic>-*` kebab 表記 (`/memory-save` 産) が 3 file 以上)
   - small file (<20 行)
   - graduate 候補 (ai-tools 配下 `rules/` `guidelines/` `references/` へ分離しやすい heuristic)
5. chat 出力 → exit、変更なし

### Stage 2: `--apply` (自 memory 反映)

dry-run 列挙再実行 → 表示 → 実行。

1. trash dir `mkdir memory/.trash-YYYYMMDD-HHMM/`
2. expired work-context (salvage candidate 除く) / description exact dup の older → `mv`
3. salvage candidate があれば AskUserQuestion 1 問で一括判断 (昇格へ送る / declined / 保留)。declined は frontmatter へ `metadata.salvage: declined` を書込み次回から通常 trash 候補へ。AskUserQuestion が tool 一覧に無い環境 (deferred 一覧未掲載 + ToolSearch 未 hit) では chat で同じ選択肢を提示して返答を待ち、無人 session では保留扱いにする (この file 内の他の AskUserQuestion も同じ fallback)
4. description rescue: body line 1 先頭 80 字 → frontmatter 書込 (body 不変)
5. MEMORY.md prune: trashed file link 行削除 / dead-link 行削除 / 超過 `[clear]` 行削除 / rescue 済 file 無 link なら 1 行 append。続けて `bash ~/.claude/scripts/memory-save-helper.sh reindex --apply` で未登録を追記する (既存の章立てと登録済み行は触らないので、分類は後から人手で移動する)
6. cross-ref: 表記揺れは `sed` で自動修正、canonical 差替 / `{{deleted:}}` 記号化は候補提示のみ (`--apply` でも auto 適用しない、user 判断)
   - **候補は slug 形状 (`^[A-Za-z0-9][A-Za-z0-9_-]*$`) かつ code span / fenced の外にある `[[...]]` だけに限定し、修正前に slug 解決を frontmatter `name:` → file 名 stem → file 名 suffix の順で確認する**。前者を欠くと bash の `[[ ... ]]` を参照と誤認して記号化し、後者を欠くと `name:` に hit する正しい参照を snake へ書き換えて壊す (detail の Cross-ref audit が canonical)
7. trash rotation: `.trash-YYYYMMDD-HHMM/` を 3 世代 rotation で最古削除する。promote 用の named 保存用 dir (`.trash-*-promote/`) は作らない。昇格した知見の本体は SoT (rules / guidelines / references) の commit にあり、復元は git 履歴で足りる (user 決定 2026-09-05、旧 dir 6 つは同日に削除済)。MEMORY.md の `[promote]` 行には SoT 側の commit sha だけ保持する

> **cluster / small / graduate は --apply 対象外**、提案表示のみ。

### Stage 3: `--import=<src-dir>` (他 repo memory 取込)

`--import` 指定時のみ実行。

1. `<src-dir>` 配下 subdir を列挙 (`_org` / project 別 dir 等)
2. subdir ごとに `explore-agent` を並列 fan-out (parallelism = subdir 数、max 4 = explore1-4 の hard cap。超過分は wave 分割)。各 agent への prompt:
   - **explore contract 必須** (canonical: `agents/explore-agent.md` 「Prompt contract」、欠落は hook が block): `run_id` (fan-out で共有) / `scope_id` (subdir 名) / `expected_count` (並列数) / `target` (worktree_path・branch・head full SHA) / `anchor_evidence` (path:line か path#symbol を 1-3 件) / `paths` / `questions` / `excludes` / `stop_when` / `budget_class` を prompt 先頭に記載する
   - 全 file を read、**汎用性 high の候補**を抽出
   - **除外基準**: 社内 product 名 / 個人名 / 会社名 / 固有 path を含む / 既存 ai-tools rule と重複 / 単発 incident log
   - 既知知識として `<repo-root>/claude-code/CLAUDE.global.md` / `rules/*.md` / `guidelines/writing/*.md` / `<repo-root>/memory/feedback_*.md` を渡す
   - 出力: 候補 file / 提案先 / 汎用化後の要旨 (常体 plain JP) / 汎用性 confidence / 伏字化対象
3. Tier 分類して chat に一覧表示:
   - **Tier A**: `rules/` `guidelines/` に独立 file / 独立追記
   - **Tier B**: 既存 file への追記型 (差分小)
   - **Tier C**: `memory/` の feedback として保存
4. `AskUserQuestion` で採用 tier 選択 (1 括採用 / 段階採用 / 個別選抜)
5. `--apply` 併用時:
   - 対象 tier の各 file を canonical 反映 (`Write` 新規 or `Edit` 追記)、伏字化を適用
   - 元 file 削除: `rm <src-dir>/<subdir>/<file>` (**注**: `<src-dir>` は別 repo 領域のため ai-tools の `.trash-*/` mv 対象外、`rm` を意図的に使う。削除前に Step 4 の `AskUserQuestion` 承認で必ず user 確認を経ている、承認済 file のみ削除する)
   - 元 repo の MEMORY.md index prune: 削除 file の行を `sed` で除去
   - 生きた feedback からの dead cross-ref 修正: 削除 file への `[[name]]` 参照を ai-tools canonical 参照に差替
   - work-context / .trash 系 log 内の dead ref は履歴保持のため触らない
6. 完了後、反映 file 数 / 削除 file 数 / cross-ref 差替数を chat に出力

## Out of scope (auto-delete しない)

- `MEMORY.md` 本体 (prune edit のみ)
- `compact-restore-*.md` / `.trash-*/` 中身
- `metadata.protect: true` の memory
- salvage candidate の work-context (昇格 or 破棄は user 判断。declined 記録済 file は次回から通常 trash 候補に戻る)
- **mtime 30 日 stale auto-delete 禁止** (`untouched ≠ valueless`)
- cluster / small file / graduate 候補 (提案のみ)
- `--import` の canonical 差替 / `{{deleted:}}` 記号化 (提案のみ)

## Example

```text
$ /memory-clean
[memory-dir] <repo-root>/memory/
[dry-run] enumerate only, no file changes
[work-context-expired] 10 files (>7d) / [salvage] 3 (恒久ナレッジ signal あり、trash 保留)
[duplicate] 0 / [description-missing] 0
[orphan] 3 files (index 未登録) / [dead-link] 2 (link 先 file 不在)
[xref-audit] fixable(表記揺れ) 5 / canonical 差替候補 3 / {{deleted:}} 記号化候補 11
[small <20] 18 files / [graduate] 2 candidates / [legacy-dir] 0 (廃止領域への流入なし)
Run: /memory-clean --apply で trash + MEMORY.md prune + 表記揺れ自動修正を実行
```

`--import` 時は上記に import-scan (explore-agent fan-out) + Tier A/B/C 候補数が加わる。

## Fallback

| Scenario | Action |
|---|---|
| memory dir 両方 missing | "memory dir not found" 報告して exit |
| trash dir 作成失敗 | abort + chat 報告 |
| frontmatter parse 失敗 | file skip、warnings 追加 |
| mv permission denied | file skip、warnings 追加 |
| 全候補 0 | "nothing to clean" exit |
| `--import=<src-dir>` の dir 不在 | "import src not found" 報告して exit (自 memory 側の他処理は継続) |

## When to use

- 月次 cleanup / MEMORY.md 100 行超 + session start 重い時
- `/retrospective` 後
- 他 repo memory から汎用 knowledge を分離したい時 (`--import=<src-dir>`)

## Related

- `/memory-save` — memory 追加
- `/reload` — memory reload
- `/retrospective` — retrospective
- `/serena-update-fix` — Serena MCP update (memory 独立)
- `rules/public-repo-private-data-block.md` — `--import` 時の伏字化 canonical

詳細仕様 (Detection logic / Graduate heuristic / Rollback) → `references/memory-clean-detail.md`

ARGUMENTS: $ARGUMENTS
