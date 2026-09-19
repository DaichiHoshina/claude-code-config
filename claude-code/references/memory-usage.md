# Memory Usage Guide

保存先は `<repo-root>/memory/` の一本 SoT (Claude Code のみ write、Codex / Cursor は symlink 経由で read-only 共有)。

| Memory | Purpose | Auto-loaded |
|--------|---------|------------|
| auto-memory (`<repo-root>/memory/`、`.gitignore` 済) | 汎用 work-context (進捗) + 汎用の恒久ナレッジ (feedback / project / user / reference) | session-start hook が「実作業開始時に `MEMORY.md` を read せよ」と指示する (hook 自身は本文を注入しない)。個別 file 本文は `/reload <topic>` で明示復元する |
| private raw 保管 (`~/.claude/references-private/org-knowledge/`) | project 固有名詞を含む恒久ナレッジ (Tier B) | auto-load しない。作業時に必要 file だけ on-demand read。canonical: `memory-relocation-pattern.md` |
| Serena memory | write 禁止 (`.serena/memories/`)。過去分の read は可だが新規保存には使わない | — |

`compact-restore-*.md` は pre-compact hook が `<repo-root>/memory/` へ出力する一時 file で、compact 後の session-start (source=compact) が read + rm する使い捨て経路になる (恒久ナレッジとは別物)。AI が rm を省略して保持された分は、次の pre-compact が 1 日超のものを削除する。

## Modes (`/memory-save`)

| Mode | 用途 | 書込先 |
|------|------|--------|
| `clear` (default、無引数) | session 終了時の状態を保存する (task / progress / next-action) | `work-context-YYYYMMDD-<topic>.md` + MEMORY.md 1 行 index |
| `<topic>` | 同日同 topic の作業を集約する | 同上 (auto merge / new) |
| `exit` | task が完全に終わった時に呼ぶ。clear の全処理をした上で恒久ナレッジを抽出する | 上記 + `feedback-<slug>.md` / `project-<slug>.md` |

詳細 flow は `commands/memory-save.md` を参照する。

- **Task Diary**: `/memory-save` を明示提案するのは以下のいずれかに当てはまる時のみ。それ以外は `~/.claude/logs/task-diary.log` への自動蓄積で足りる
  - 3 file 以上を変更した
  - 非自明な設計判断を伴う refactor をした
  - incident response をした

## Recording Targets (Compounding Engineering)

misbehavior だけでなく **non-obvious な成功パターン**も記録対象にする。再現性を確保するための改善を蓄積する考え方になる。

config 側 (CLAUDE.md / skill / hook) を主保存先とし、auto-memory は補助にする。理由は、auto-memory が Claude の自動判断で書かれ古くなりやすいのに対して、config 側は明示的で再現性が高い点にある。

| Type | Example | Primary storage | Supplementary | Write method |
|------|---------|----------------|--------------|--------------|
| Misbehavior (再発防止) | 同じ path error、想定外の file 削除 | CLAUDE.md / skill / hook | `feedback-*.md` (`/memory-save`) | User Edit / Claude auto |
| Non-obvious success (再現用) | 試行錯誤で当てた非標準 approach | CLAUDE.md / skill | `feedback-*.md` (`/memory-save`) | User instruction / Claude |
| Project constraint / decision | repo から導出できない制約とその理由 | `project-*.md` (`/memory-save`) | — | Claude auto (clear 時に常時) |
| Transient work state | 進行中 session の進捗・再開手順 | `work-context-*.md` (`/memory-save` clear/topic) | — | Claude auto |

**Write path notes:**

- **CLAUDE.md / skill / hook**: user が直接 Edit するか、同一会話内で「CLAUDE.md か該当 skill を更新して」と指示された時に Claude が追記する
- **auto-memory (`<repo-root>/memory/`)**: `/memory-save` が全 mode で個別 file を作成する。`exit` mode のみ `feedback-*` / `project-*` の恒久 file を追加抽出する。再現可能な手順や全 session 共通 rule は `/promote` で config 側へ昇格させ、memory 側は削除する
- **housekeeping**: `/memory-clean` が `<repo-root>/memory/` 配下 (work-context / feedback / project 問わず全 file) を対象に trash / prune / 表記揺れ修正をする (`commands/memory-clean.md` 参照)

config で再現できることは skill / CLAUDE.md を優先する。memory は再現しづらい文脈や進行中の状態を保つ場所として使う。

## Relocation pattern (背景、optional)

auto-memory dir が encoded path で人間には読み取りにくく、project をまたぐと散逸しやすい。この問題への対処として、auto-memory dir をやめて project / org / user の scope 別に repo 配下や user 私物 dir へ集約する pattern がある。auto-load は失うが、user-readable / git 管理可能 / 横断検索が容易という利得を取る考え方になる。`<repo-root>/memory/` への一本化はこの pattern の適用結果になる。詳細: `memory-relocation-pattern.md`。
