# warn-log-weekly.sh

hook / review skill が出力する warn log を週次で集計する script。fable 助言「効果測定を先に整えろ」への対応として 2026-07-21 に導入した。

## 目的

- どの hook / perspective が発火しているかを可視化する
- 死に log (4 週間 Δ=0) を検出して剪定判断する
- 急増 pattern を早期に検出し、誤爆か有効かを切り分ける
- 追加 hook / rule / skill perspective 提案時の判断材料にする (実測ゼロなら追加しない、CLAUDE.md 「Compounding Engineering」)

## 集計対象 log (2026-08-23 時点)

| log | 発生元 | 意図 |
|---|---|---|
| `review-pattern-warn.log` | hook (write-checkers.sh の subtest-parallel / migration-safety / churn 等) | 対象 project 特化 review pattern |
| `bundle-violation-warn.log` | hook (task-agent-checkers の delegate bundle 違反) | agent 並列化違反 |
| `sequential-fire-warn.log` | hook (agent-guard の Agent 逐次発火検知) | agent 並列化違反 |
| `hook-errors.log` | 全 hook の `exec 2>>` 先 (raw stderr) | hook 自身の実行時 error |

log 追加時は `TARGET_LOGS` 配列を編集して反映する。comment 体言止め (`comment-style-warn.log`) と comment 行数 (`comment-quantity-warn.log`) は書き手 hook ごと廃止済 (b33e28da / 4b641115) のため 2026-08-23 に対象から外した。

`hook-errors.log` だけは TARGET_LOGS でなく専用 section で出す。行に timestamp が無い raw stderr なので週次の集計対象の区間に含まれず、記載すると全行が毎週「今週分」に数えられて Δ が壊れる。現在 file を message 別に数える snapshot (top 10) として、weekly summary の末尾に付ける。

### log 別 format

| log | format 種別 | 行構造 |
|---|---|---|
| `review-pattern-warn.log` | `bracket_pipe` | `[TS] session \| pattern \| detail \| detail2` |
| `bundle-violation-warn.log` | `pipe_nobracket` | `TS \| session \| pattern \| detail` |
| `sequential-fire-warn.log` | `pipe_nobracket` | `TS \| session \| pattern \| detail` |

集計は pattern 別で、`pipe_nobracket` は `dev_count=N` / `counter=N` のような値違いをまとめて key 名 (`dev_count` / `counter`) に正規化するため、breakdown ではなく total と Δ を見る log になる。

format 分岐の実体は `warn-log-weekly.sh` 内の `log_format()` と `_TS_PAT_EXTRACT` が正であり、本表が古くなったらそちらを見る。未知の basename を渡すと `log_format()` は `bracket_pipe` を返す。

## 出力

- 保存先: `~/.claude/logs/warn-log-weekly-YYYYMMDD.txt`
- 内容: log 別の (this / last / Δ) と this week の pattern 別 breakdown、末尾に interpretation hints

## 実行

- 手動: `bash <repo-root>/claude-code/scripts/warn-log-weekly.sh`
- 週次自動: `./scripts/install-warn-log-weekly-cron.sh --enable` で launchd plist (`~/Library/LaunchAgents/com.daichi.warn-log-weekly.plist`) を配置・有効化する (毎週月曜 10:00 実行、cron log は `~/.claude/logs/warn-log-weekly-cron.log`)

## 判断基準 (定期集計を見た時の対応)

- 特定 pattern が Δ で急増: 該当 pattern の直近 3 hit を目視で確認する。誤爆なら hook 側の pattern を調整、有効なら「block 昇格 or 単独 rule 化」を検討する
- `hook-errors.log` の同一 message が蓄積している: hook 自身の実バグ (format 文字列の誤用 / file 不在 guard の不足 等)。行数でなく message 単位で解消する
- 4 週続いて Δ=0 の log: hook が壊れているか、rule が既に body に染み込んで発火機会が無い。前者なら修正、後者なら剪定 (log 追加を保持する意義がなくなっている)
- 特定 pattern が total の 80% 超: 他の check が目立たなくなっている signal。頻度上位を block に昇格させて他 pattern を見えやすくする

## 関連

- 発生元 hook: `<repo-root>/claude-code/hooks/lib/write-checkers.sh` / `lib/task-agent-checkers.sh` / `lib/agent-guard.sh`
- 関連 skill: `skills/comprehensive-review/references/diff-hygiene.md` (今後 review 側 log も対象化する余地)
- 関連 memory: 対象 project 側の auto-memory dir 配下 `review-lens-pending-promotion.md` (4 週後の昇格判断でこの script の集計を使う)
