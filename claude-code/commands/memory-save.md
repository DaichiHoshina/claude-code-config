---
allowed-tools: Write, Read, Bash
description: Quick auto-memory save — 常に恒久ナレッジ化 + promote まで実行される。<topic> で merge/new auto 判定
argument-hint: "[<topic> | exit]"
effort: low
---

# /memory-save - Quick auto-memory save

Save current work state in 1 command。**default (no arg) = clear + 恒久ナレッジ化 + promote**、MEMORY.md 1 行 index prepend + 個別 file に本文 write の 2 段構成で `/reload <topic>` 復元を担保する。CLAUDE.md 規約 (Serena `.serena/memories/` と `~/.claude/projects/.../memory/` への write 禁止) に従う。clear でも個別 file を必ず書く (MEMORY.md 1 行だけでは次 session 復元時に scope 再質問を誘発するため)。肥大化は `/memory-clean` で別途対処する。

> **Helper script 必須**: dest 解決 / name 解決 / MEMORY.md 更新は `scripts/memory-save-helper.sh` 経由 (AI の Write/Edit ばらつき排除)。本体 body の Write のみ AI 側担当。bash heredoc での write は jp-quality / public-repo-guard の Write 検査の対象にならないため禁止。

## Mode 判定 (arg → mode)

| `$ARGUMENTS` | Mode | 動作 |
|---|---|---|
| (empty) | **clear (default)** | topic は AI 決定、復元に必要な内容を行数を気にせず save。続けて恒久ナレッジ化 + promote を必ず実行する |
| `<topic>` (単語) | **auto merge / new** | 同日同 topic file あれば最古に auto merge (質問なし)、無ければ new file。恒久ナレッジ化 + promote は実行しない |

`<topic>` は kebab-case (空白不可)。legacy arg `clear` / `exit` はどちらも default と同義で、動作の差はない。

> **clear と exit を分けない** (2026-08-24 user 決定): 恒久ナレッジ化を task 終了時だけの任意 step にすると、抽出の機会そのものを逃す。抽出は候補 0 件なら数行で終わるので、毎回実行して取りこぼしを無くす方が総 cost が低い。

## Flow (全 mode 共通 3 call: prepare → Write → finalize)

1. **prepare**: session の `<topic>` (kebab-case) と 1 行 `<summary>` を決める。決めたら `bash ~/.claude/scripts/memory-save-helper.sh prepare <topic>` を 1 回呼ぶ。出力 (`key=value` 行) が保存に必要な全 metadata:
   - `dir` = save 先。org 配下 repo は org 作業 memory、それ以外は `<repo-root>/memory/` を helper が自動判定する。出力をそのまま採用し根拠 1 行を chat に記載する (質問しない)。project 階層 CLAUDE.md が auto-memory dir を宣言する場合のみ override する。その場合 `MEMORY_SAVE_DIR=<宣言 path>` を prepare / finalize 両方の呼び出しに前置する。例外: `$ARGUMENTS` が空 + 宣言が競合して dest を限定できない時だけ AskUserQuestion 1 問 (ai-tools / project の 2 択)
   - `merge_target` 非空 = 同日同 topic の最古 file (issue key prefix 無視で match、複数 hit は最古 1 件)。空なら `new_name` を使う (branch 由来の issue key prefix と collision `-2/-3` suffix は解決済)
   - `worktree` / `branch` 非空 = cwd が linked worktree。frontmatter に転記する
2. **body 生成 + Write**: File format 節の形式で生成する。`merge_target` があれば Read して差分追記で上書きし、無ければ `<dir>/<new_name>.md` へ新規 Write する。body は行数上限なしで、文として閉じた読みやすい記述で書く (詰め込みの長文段落にしない)
   - **文体圧縮の禁止**: 容量・肥大 warning への対応を含め、助詞を削る / 一般名詞を英語連結へ縮める圧縮書き換えをしない。memory は次 session 開始時に文体の模範として読み込まれるため、圧縮文は以後の出力文体へ伝播する。減らすときは自然文のまま情報の取捨選択 (削除・統合 = `/memory-clean`) で行う
   - `## task` = session でやったこと。`## progress` = 直近 state・commit・残決定。`## next-action` = 再開手順と user への未回答の質問
3. **finalize**: clear / exit は `bash ... finalize clear <topic> <summary> [commit]` (MEMORY.md 先頭に `[clear]` 行 prepend)。`<topic>` mode は `bash ... finalize topic <name> <topic> <description> [hook]` (index prepend + dedup)。どちらも helper が `/reload <topic>` の pbcopy まで実行する
4. **恒久ナレッジ化 + promote**: clear (default) は次節を必ず実行する。`<topic>` mode は実行せず、候補を見つけたときだけ Report に「恒久ナレッジ候補あり → 引数なしの `/memory-save` 推奨」を 1 行添える (index 行に hook (参照条件) を書きたくなった場合も同じ signal とみなす。参照条件が必要な内容は date prefix の短命 file に置くべきでない)
5. **Report**: 「memory を保存した (index + `<saved-path>`)。`/reload <topic>` を clipboard にコピーした。`/clear` 可」を 1-2 行 chat (systemMessage 非汚染)。恒久ナレッジ化と promote の結果を次節の形式で続ける

次 session では session-start hook が MEMORY.md の read を促す (自動注入ではない。実作業を始める時だけ AI が read する)。明示復元は `/reload <topic>` (fallback chain: `commands/reload.md`)。

## File format

```yaml
---
name: <kebab-case-slug>
description: <one-line summary>
metadata:
  type: project
  worktree: <abs-path>   # optional: prepare の worktree= 非空時のみ転記
  branch: <branch-name>  # optional: worktree と対で記録
---

## task               # 必須
## progress           # 必須
## next-action        # 必須
## files              # optional (空なら省略)
## project            # optional
## last 3 messages    # optional
## skill              # optional
```

3 必須のみで完結可、短 session は 10 行台で OK。

## 恒久ナレッジ化 + promote (clear mode で常時実行)

Flow を全て実行した後、session の task 情報を恒久ナレッジへ昇格させ、config 化がふさわしいものは `/promote` まで続ける。

1. **恒久ナレッジ候補を抽出**: 次 session 以降も有効な知見だけ採用する。基準は `references/memory-usage.md` 「Recording Targets」 と同じ: misbehavior 再発防止 / non-obvious success / repo から導出できない制約・決定。進捗・commit hash・一時状態は除外 (work-context 側が担当する)。候補 0 件なら step 2-4 を skip し報告に含める
2. **恒久 file write** (候補 1 件 = 1 file):
   - **命名**: `feedback-<slug>` (挙動修正・作法) / `project-<slug>` (project 制約・決定)、日付 prefix なし
   - **除外の記載**: 「実測したうえで入れないと決めた」型の否決判断は必ずここへ記載する。work-context は 7 日超で trash へ移るので、そこに置くと同じ対策を後から入れ直す (例: 2026-08-23 に実測付きで否決した caffeinate ラップを 08-29 に入れ直した)
   - **merge 方針**: 同趣旨の既存 memory があれば merge する
   - **body 構成**: fact + `**Why:**` + `**How to apply:**` の構成で記述する (行数上限なし)
   - **Tier B routing (必須)**: write 先は本文を stdin で渡して `bash ~/.claude/scripts/memory-save-helper.sh resolve-permanent-dir` で解決する。social-hit term (canonical: `rules/public-repo-private-data-block.md`) を含めば `references-private/org-knowledge/` (Tier B)、含まなければ Tier A。org 作業 memory (git 管理外) が dest なら helper が移動を自動 skip する
3. **MEMORY.md 更新**: Tier A に write した file のみ `bash ... finalize topic <name> <topic> <description> [hook]`。Tier B は index 化しない (auto-load 対象外の raw 保管)
4. **promote 実行**: step 2 で write した file のうち config 化 (CLAUDE.md / rule / guideline / skill / command) がふさわしいものを `/promote <memory-file>` で**自動起動する** (案内で終わらせない)。判定は下表。該当 0 件なら skip して報告に含める

   | 内容 | 扱い |
   |---|---|
   | 全 session 共通の作法 / 禁止事項 / 判定基準 | promote 起動 (CLAUDE.md / rule / guideline へ) |
   | 特定 repo・特定 issue の制約や決定 | memory に置いたまま。promote しない |
   | 再現可能な手順が固まっていて 3 回以上使う見込み | promote 起動 (skill / command へ)。ただし新規 skill / command / hook の新設は `references/on-demand-rules/toolchain-lifecycle.md` の lifecycle gate を先に通す |
   | 1 回きりの気付き / まだ再現していない仮説 | memory に置いたまま。promote しない |

   promote は `commands/promote.md` 「Auto invocation via memory-save」 に従い、SoT への Edit 直前の 1 回だけ確認を取る。複数 file が候補なら 1 file ずつ順に実行する
5. **Report**: clear の報告に「恒久ナレッジ N 件 (`<file名>...`)」と promote の結果 (統合先 file / 見送り理由) を追記する

## Fallback

| Scenario | Action |
|----------|--------|
| memory dir 不在 | helper が `mkdir -p` |
| Write 失敗 | body を chat 出力、manual save 案内 |
| Helper script 不在 | inline で `<repo-root>/memory/` write + MEMORY.md 手 prepend (warn 表示) |
| name collision (new file 時) | helper `prepare` が `-2/-3` suffix で解決済 |
| 同日 exact match 複数件 | `merge_target` = 最古 1 件、他は無視 |
| finalize (index 更新) を省略した | 本文 file だけ残り index に含まれない。`/memory-clean` が index 未登録として検出し、`memory-save-helper.sh reindex --apply` で「## 未分類 (reindex)」章へ追記する |

ARGUMENTS: $ARGUMENTS
