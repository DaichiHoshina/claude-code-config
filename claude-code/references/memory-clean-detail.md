# /memory-clean 詳細仕様

`commands/memory-clean.md` の補足仕様。実装参照用。

## Detection details

### work-context expiry

- regex: `^work-context-(\d{8})-.*\.md$`
- `date -j -f %Y%m%d` で Unix time 化
- `today - N*86400` より古ければ trash 行き (N は fixed 7 日)

### Salvage — 期限切れ work-context の恒久ナレッジ検出

trash candidate の body を scan し、次のいずれかに該当すれば salvage candidate へ分離する (trash 保留):

- MEMORY.md の該当 index 行に hook (`— <参照条件>`) が付いている
- body に恒久 rule 性の語 (「禁止」「必ず」「常に」「注意点」「再発」「してはいけない」) を含む段落がある
- 他 memory file から `[[name]]` で参照されている (suffix match 含む、Cross-ref audit 参照)

`## next-action` の残項目は signal にしない。全 file が非空の同節を含み (実測 24/24、2026-08-16)、未処理かどうかは後続 session の完了を知らないと判定できないため、検出として機能しない。

**昇格済み除外**: signal に該当しても、次のいずれかなら salvage にせず通常の trash candidate に戻す (誤爆の主因は昇格済み内容の引用):

- MEMORY.md の `[promote]` 行が同 topic の昇格を記録している
- hit した段落の要旨が SoT (`rules/` / `guidelines/` / `references/` / `commands/`) に既に存在する (要旨語で grep して確認。2026-08-16 実踏: commands/loop.md 反映済の知見を「SoT 未反映」と誤判定し重複昇格しかけた)
- frontmatter に `metadata.salvage: declined` がある (過去に user が不要と判断済)

**判断の永続化**: `--apply` 時に salvage candidate があれば AskUserQuestion 1 問で一括判断を取る (昇格へ送る / declined / 保留)。declined の file には frontmatter へ `metadata.salvage: declined` を書込み、次回実行から通常の trash candidate に戻す。保留は marker なしで次回も再提示する。

提示形式: 候補ごとに昇格先案 (`feedback-<slug>` / `project-<slug>` / graduate 先) + 根拠 signal を 1 行で添える。昇格の実行は `/memory-save` 相当の手動抽出 or `/promote` で行い、この command は file を移動しない。

### Duplicate detection

1. **Description exact match** (auto): punctuation/whitespace strip 後の同一 string。pair の mtime 比較で古い方を trash
2. **Name prefix match** (提案のみ): name slug `-` split の最初 3 tokens 一致。恒久 file は同 topic の別知見同士 (例: `project-alexa-mcp-*` 2 件) でも一致するため誤爆源で、`--apply` でも trash せず merge 候補の提示に留める
   - 例外: `work-context-YYYYMMDD-*` は prefix match 自体を除外 (同日複数で false positive)

Fuzzy match (Jaccard 0.6 等) 禁止 (false positive 過多)。auto trash は description exact のみ。

### Topic cluster

`feedback-<topic>-*` / `project-<topic>-*` (kebab、`/memory-save` 産) と legacy snake (`feedback_<topic>_*` / `knowledge_<topic>_*` / `writing_failure_*`) の topic part で group。3 file 以上を merge 候補として列挙。

```
[cluster] feedback_no_* (6): feedback_no_derived_literals.md, feedback_no_env_output.md, ...
[cluster] feedback_hook_* (3): feedback_hook_ng_list_pitfalls.md, ...
```

merge は user 手動 (統合前の file を `mv` で trash)。skill は merge を実行しない。

### Small file

`wc -l < <file>` が 20 行未満の `*.md` を list 表示。除外: `MEMORY.md` / `pending-improvements*` / `compact-restore-*`。加えて、frontmatter description があり MEMORY.md に index 済の恒久ナレッジ (`feedback-*` / `project-*` / `user_*`) は、topic cluster に merge 先がある場合のみ列挙する。完結した恒久ナレッジの短さは問題にせず、行数だけを理由に統合や加筆を提案しない。merge は user 判断。

### Orphan / dead link

index (MEMORY.md) と file 実体の対応ずれを両方向で検出する。

**方向 1: orphan** — file は存在するが MEMORY.md 内 link にも他 memory file の `[[name]]` 参照にも現れない。

| 状態 | 対応 |
|---|---|
| 参照 0 + 内容 active rule | MEMORY.md に index 追加 |
| 参照 0 + 内容 obsolete | 手動 trash |
| user_* 系で意図的に未 link | keep (false positive) |

```bash
# orphan 検出 (work-context / MEMORY.md / pending-improvements は除外)
# MEMORY.md link と他 file の [[name]] 参照の両方を見る (どちらかにあれば orphan でない)
for f in *.md; do case "$f" in MEMORY.md|pending-improvements.md|work-context-*) continue;; esac
  n="${f%.md}"
  grep -q "$f" MEMORY.md && continue
  grep -qF "[[$n]]" *.md && continue
  echo "ORPHAN: $f"; done
```

**方向 2: dead link** — MEMORY.md が `[...](name.md)` で link するが link 先 file が実在しない (trash 済み / 手動削除の残骸)。該当 index 行を prune する (`--apply` 対象、trash 送りではなく MEMORY.md 行削除)。

```bash
# dead link 検出 (link 先 file 不在)
grep -oE '\]\(([a-z][^)]+\.md)\)' MEMORY.md | sed -E 's/\]\(|\)//g' \
  | while read l; do [ -f "$l" ] || echo "DEAD-LINK: $l"; done
```

> work-context を trash 送りにした後は MEMORY.md prune (flow Stage 2 step 4) で link 行が消えるが、過去に手動削除された file の link が残存すると dead link 化する。dry-run で両方向を必ずチェックする。

### Legacy dir inflow — 廃止領域への書き込み検出

対象: `~/.claude/projects/*/memory/*.md` (auto-memory、2026-06-26 廃止) と `<ghq-root>/github.com/**/.serena/memories/*.md` + `<ghq-root>/worktrees/**/.serena/memories/*.md` (Serena memory、write 禁止)。`.trash*` 配下は除く。

- 判定: mtime が前回 run の stamp (`~/.claude/logs/launchd/memory-clean.log` の最終行日時) 以降、無ければ 30 日以内
- 出力: `<path> <mtime> <description 先頭 60 字>` を 1 行ずつ。件数 0 なら「廃止領域への流入なし」と 1 行
- 扱い: Stage 2 (`--apply`) でも mv / rm しない。SoT (`<repo-root>/memory/` または org memory) への移行は同名 / 同趣旨 file との突き合わせが必要なため user 判断とし、salvage 候補と同じく AskUserQuestion で聞く
- 根拠: 2026-08-28 の点検で、廃止済みの auto-memory dir に 7/14〜8/21 の 51 file が書かれていたことが判明した (`<ghq-root>/CLAUDE.md` の write 禁止が守られていなかった期間)。live memory から `[[name]]` で 30 名 / 100 箇所超が参照されていて、dead ref の主因になっていた。32 本を org memory へ移行して解消

### Cross-ref audit — `[[name]]` の scope と分類

対象は恒久 memory 全 file (`feedback-*` / `project-*` / `user_*` / legacy snake)。work-context と `.trash-*/` 内は履歴保持のため修正対象外 (参照元としての scan はする)。

監査は **抽出 → 解決 → 分類** の 3 段で進める。段を省略すると、次段が正しくても誤爆する。

**抽出条件**: `[[...]]` の見た目を含む text のうち、次を満たすものだけを cross-ref 候補にする。満たさないものは候補に入れず、件数だけ dry-run へ出す (通知せずに対象外にすると検出器の不足が見えなくなる)。

1. 中身が slug 形状 (`^[A-Za-z0-9][A-Za-z0-9_-]*$`) に一致する。空白 / 引用符 / `$` / `.` / `/` を含むものは候補外
2. fenced code block の外にある。`awk '/^```/{f=!f} !f'` で fence 内を除いてから検出する
3. 行内の code span の外にある。同一行で `[[...]]` の左に現れる backtick が奇数個なら span 内とみなす

条件 1 を欠くと bash の `[[ ... ]]` test 構文を参照と誤認する (2026-09-07 実踏: `[[ -f path ]]` 等 4 箇所を `{{deleted:}}` へ置換して破壊し、backup から復元した)。条件 2-3 を欠くと、記法を説明する placeholder (`` `[[name]]` `` / `` `[[link]]` ``) が毎回 dead 候補として上がり続ける。

**slug 解決の順序**: 抽出した `[[name]]` の実体判定は次の順で照合し、どこかで hit した時点で「実体あり」として監査を終える。

1. frontmatter の `name:` 値 — canonical。memory 仕様上 slug は kebab で、file 名が legacy snake のままでも `name:` は kebab で書かれている
2. file 名 stem (`<name>.md`)
3. file 名 suffix (`*-<name>.md`) — work-context は date prefix 付き file 名を短縮名で参照することがある (実例: `[[loadtest-report-jp-loop]]` → `work-context-20260719-loadtest-report-jp-loop.md`)
4. org 側 memory dir (`<ghq-root>/github.com/<org>/memory/**`) の同 3 段 — 保存先が scope で 2 dir に分かれているため、ai-tools 側 memory は org 側 slug を `[[name]]` で普通に参照する (実例: `[[vpn-meet-quality-issue]]` → `_org/vpn_meet_quality_issue.md` の frontmatter `name:`)。org 側は read のみで、修正は参照元の ai-tools 側 file に当てる
5. SoT 配下 (`<repo-root>/claude-code/` の `rules/` / `guidelines/` / `references/`) の file 名 stem — 昇格した知見は memory から消えて SoT に配置されるため、memory 側の参照は SoT の slug を指したままになる (実例: `[[thinking-principles]]` → `rules/thinking-principles.md`、2026-09-07 時点で 5 箇所)。memory dir だけを見ると、生きた参照を dead と数える

file 名だけで照合すると、`user_dev_workflow.md` (frontmatter `name: user-dev-workflow`) への `[[user-dev-workflow]]` を「snake への表記揺れ」と誤分類し、**正しい参照を壊す方向へ自動修正する** (2026-08-18 実踏: 3 件を sed で書き換え、backup から復元した)。legacy snake の file 名と kebab の `name:` が併存する限りこの誤爆は再発するため、照合順 1 を省略しない。

上の 5 段のどれにも hit しなかった `[[name]]` だけを dead とみなし、実体の所在で分類する:

| 実体の所在 | 分類 |
|---|---|
| memory dir にある (`-` ↔ `_` を入れ替えると slug に hit する) | 表記揺れ → `--apply` で自動修正 |
| `.trash-*/` にある (trash 済) | `{{deleted:}}` 記号化 or canonical 差替候補 (提示のみ)。記号化してよいのは抽出条件を満たし、かつ解決 5 段すべてに不一致だった候補に限る |
| SoT 側に昇格済 (rules / guidelines / references に同内容) | canonical 差替候補 (提示のみ) |
| どこにも無い | 未作成 marker とみなし note のみ。削除も記号化もしない (書く価値の目印として正当) |

**自動修正の適用条件**: 表記揺れの `--apply` は上表の 1 行目に該当した参照だけを対象にする。加えて sed は hit した file を名指しで当て、`*.md` 一括には当てない (一括適用は同名 pattern を含む無関係 file まで書き換える)。修正前に対象 file を trash dir へ backup し、修正後は「修正前 slug の残存 0」ではなく「参照先が解決すること」を検証する。残存件数だけを見ると、frontmatter `name:` に hit していた正しい参照を「未修正」と誤読する。backtick を含む行を書き換えたときは、件数の確認に加えて差分を目視する (code span 内を書き換えると、残存 0 でも本文の記法が壊れる)。

**誤爆したときの切り分け**: 監査が正しい参照を壊したら、修正する前に抽出 / 解決 / 分類のどの段で起きたかを決める。段を取り違えると、無事だった段へ条件を追加して再発を防げない (`rules/thinking-principles.md` Section 7 の heuristic と gate の切り分けと同型)。実踏は 2 件ある。

- 2026-08-18 は解決段だった。frontmatter `name:` を照合せず file 名だけで判定し、正しい参照 3 件を snake へ書き換えた。対処は照合順 1 の明文化
- 2026-09-07 は抽出段だった。bash の `[[ ... ]]` を参照と誤認し 4 箇所を記号化した。分類表も解決順も正しく動いていたので、修正する対象は抽出条件だった

### Graduate — memory → ai-tools 分離

| memory パターン | 分離先 |
|---|---|
| 汎用 rule (secret / writing / git / db / security) | `rules/<topic>.md` |
| writing guideline / 文体規範 | `guidelines/writing/` |
| design / architecture knowledge | `guidelines/<area>/` |
| ツール仕様 / 参照資料 / 履歴 | `references/<topic>.md` |
| Serena artifact (codebase_structure / suggested_commands 等) | `.serena/memories/` 復元 or archive |

heuristic 検出:
- `knowledge_` prefix → references 候補
- `writing_failure_` prefix → guidelines/writing 候補
- `feedback_no_*` で「禁止 rule」性質 → rules/ 候補
- description / body に「rule」「禁止」「常に」「必ず」→ rules 候補
- Serena 標準 file 名 → Serena memories 候補

`--apply` 時は自動 move しない。`graduation-candidates.md` manifest を trash dir に書出のみ → user 手動 merge。

### Description rescue

frontmatter `description` 欠落 file:
1. body line 1 先頭 80 字 (`#` `-` `*` strip) を description に
2. `--apply` で frontmatter 書込 (body 不変)
3. MEMORY.md 反映

## Rollback

```bash
MEM=<repo-root>/memory  # または ~/.claude/projects/.../memory
ls -t $MEM/.trash-*/
mv $MEM/.trash-YYYYMMDD-HHMM/foo.md $MEM/
```

3 世代 retain で直近 3 batch 復元可。rotation の削除対象は `.trash-YYYYMMDD-HHMM/` で、promote 用の named 保存 dir は作らない (昇格先の SoT commit が復元点。2026-09-05 に旧 `.trash-*-promote/` を全て削除した)。
