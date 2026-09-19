# Boris-style mapping

Boris Cherny 流 ([howborisusesclaudecode.com](https://howborisusesclaudecode.com/)) と公式 best practice ([code.claude.com/docs/en/best-practices](https://code.claude.com/docs/en/best-practices)) の主要 tip を ai-tools 既存機能に照合する。実装方針が異なる箇所は「方針差」列に明記する。

## 取り込み対応表 (2026-06-20 初回照合 14 件 + 2026-07-13 再照合 5 件 + 2026-08-12 再照合 4 件 + 同日公式 doc 再照合 4 件)

| Boris / 公式 tip | ai-tools 既存機能 | 方針差 |
|---|---|---|
| Worktree 並列 (5 instance default) | `/flow` (parallel forced ON, N=formula 駆動) | 5 fixed でなく formula 算出。`references/PARALLEL-PATTERNS.md`。Boris 本人は worktree でなく複数 git checkout 派 (local 5 + remote 5-10 session、worktree はチーム他 member の流儀。2026-07-13 deep-research 確認) |
| compact 後に core rule 再 inject | `hooks/session-start.sh` の source=compact 分岐 | 同方針 (PostCompact は context を注入できない) |
| PostToolUse auto-format | `hooks/post-tool-use.sh` (gofmt / prettier 含む) | 同方針 |
| SessionStart で動的 context 注入 | `hooks/session-start.sh` (既存) | 同方針 |
| auto mode (classifier permission) | `permissions` allow/deny + autonomous default | classifier 利用なし、ENV / settings 静的判定 |
| `/btw` で context を汚さず質問 | CLAUDE.md `Context Management` 明記済 | 同方針 |
| `/clear` 推奨 (2 回失敗時) | `hooks/user-prompt-submit.sh` 150 / 350 msg warn | msg count + 連続失敗の検出を加えた二段構成 |
| Plan → Implement 分離 | `/plan` → `/dev` / `/flow` | 同方針。Boris は task の約 80% を plan mode 起点にし、plan 合意で成功率 2-3 倍、合意後は auto-accept edits へ二段遷移 (2026-07-13 確認) |
| Adversarial review (fresh context) | `/review` Stage B = reviewer-agent 委譲 | 同方針 |
| Stop hook で verify を確実に実行 (bash + Go / TS / Py) | `hooks/stop-verify.sh` (opt-in、`STOP_VERIFY_ENFORCE=1`、言語別 runner 自動判定 + 不在は graceful skip) | opt-in。Boris の用途 (test 失敗時に完了報告を止めて修正継続) と一致を 2026-07-13 に確認 |
| perspective-diverse verifier panel | `/review --verifier-panel=N` (default OFF、N=3 で 3 lens correctness / consistency / boundary fan-out + 多数決) | opt-in、token N 倍 cost |
| institutional memory (訂正→CLAUDE.md) | auto-memory + `@path` import + retrospective | 同方針 |
| fan-out workflow orchestration | `/workflow` (Workflow tool で deterministic pipeline / parallel / 多数決を script 化、6 テンプレ提供) | `/flow` (PO/Manager/Dev) と直交。review / migrate / research / understand / judge-panel / scan の軽量 fan-out 用 |
| objective stop-condition loop (`/goal`, Ralph Wiggum guard) | `commands/goal.md` (maker-checker 分離 + objective gate 必須 + hard stop 3 種) | Loop engineering 14-step canonical は `references/loop-engineering.md` |
| `/loop` / `/schedule` (cadence loop) | `commands/loop.md` + `scripts/loop.sh` (external headless loop) + `scripts/install-loop-cron.sh` (launchd) | schedule は manual run 実績 (Status: done) を有する loop のみ許可 (MVL 順序 enforcement) |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` で早期 auto-compact | 採用しない。手動 「>40% → /compact」 rule (CLAUDE.md) を維持 | 値は model context 上限で cap されるため 200k 級では無意味。公式も 1M context model 以外は未設定を推奨 ([env-vars docs](https://code.claude.com/docs/en/env-vars.md)、2026-07-13 確認) |
| PR comment `@.claude` → CLAUDE.md 自動更新 | `/retrospective` + `/promote` (知見 → CLAUDE.md / skill 昇格 flow) | PR comment 起点でなく session 起点。昇格先を CLAUDE.md 限定にせず skill / rule も採用する |
| verify → simplify → ship (`/go` pattern) | `/review --push` (review → fix → 回帰 check → push) + code-simplifier agent | 同方針。simplify は必須 step でなく必要時のみ |
| `claude agents` control plane / `--teleport` / `--name` / `/color` | 対象外 (CLI product 機能で config 化する要素がない) | — |
| adversarial review 2 段構成 (初回並列 review → 反論専任 5 subagent が false positive を除外する) | 未採用。`/review --verifier-panel` は lens 直交 + 多数決型で構造が異なる | 将来候補。verifier-panel の需要実績が現れてから第 2 波反論 stage の追加を判断する (2026-07-13 deep-research 確認) |
| model 世代ごとに prompt を「全削除 → 必要分だけ復元」する ablation (Opus 5 で system prompt 80% 削除。「model は過度な指示では機能しない」) | CLAUDE.repo.md `Definition File Token Saving` + `/update-guidelines` (staleness 検査) | 同方針 (指示最小化)。2026-08-12 に行数超過の全定義 file (command 1 + SKILL.md 4) を上限内へ削減し違反 0 にした。model 世代起点の一括 ablation 第 1 波は Claude 5 family (Fable 5) 到来を trigger に同日実施した。auto-load 群 (CLAUDE.global.md 148 行 + rules 計 400 行) を harness native 重複の観点で監査し、削除 0 で確定: thinking-principles / minimize-questions は Claude Code harness の system prompt が同旨 (結論先行 / turn 完結 / 自律実行 / 質問抑制) を native 搭載するが、Codex `AGENTS.md.example` / Cursor `ai-tools-thinking.mdc` / agents Universal core との 4 点同期 canonical (`thinking-principles-sync.bats` が 7 section + anchor を contract 固定) のため維持。CLAUDE.global.md は環境 fact / user 決定 / incident guard 主体で harness 重複なし。「全削除→復元」の literal 適用は multi-tool 共有 prompt には行わない方針を確定 (Startup School 2026 講演) |
| シンプル prompt + 自動検証 loop で数日〜数週間の長期実行 (Electron app の Swift 書き換え実験、2 週間以上継続) | `/goal` (objective stop-condition + maker-checker) + `references/loop-engineering.md` | 同方針だが時間 scale が違う (ai-tools の loop は session〜日単位)。週単位実行は Opus 5 の長時間実行能力前提の実験段階のため、取り込みは成果公開待ち (2026-08-12 確認) |
| Code Review 機能 (PR ごとに agent team が deep review。Anthropic 社内で review bottleneck 解消の実績) | `/review` (comprehensive-review) + `/code-review ultra` (cloud multi-agent) | 同方針。既に両輪あり追加対応不要 (2026-08-12 確認) |
| Claude Code 2.1.0 新機能 (agent / skill frontmatter への hooks 直書き、skill の forked context / hot reload / `/` 起動) | `claude-update-fix` skill で差分検出 → 安全分のみ auto-apply する既存 flow で合わせて更新 | 更新済。2.1.0 機能群は `/claude-update-fix` の既存 run で判断済 (`references/CLAUDE-CODE-OPPORTUNITIES.md`)、2026-08-12 に VERSION を stable 2.1.221 へ bump (2.1.221 は全件 bugfix で config 影響なし)。frontmatter hooks 採用時は 🔒 frontmatter 改変禁止 rule との整合判断が必要 |
| Interview 型 spec 作成 (AskUserQuestion で自分をインタビューさせ SPEC.md 保存 → fresh session で実装) | `/prd` Phase 1 interview (`commands/prd.md`) | interview 部分のみ対応済。SPEC.md 相当の永続化は `--out` 指定時のみ (default は chat 出力で persist しない)、fresh session への移行導線も未確立。/plan の investigation fresh-session gate が近い機構を有するため緊急性低と判断し見送り (2026-08-12 公式 doc 照合) |
| reviewer への過剰指摘抑制 (「correctness と要件に影響する gap だけ flag せよ、残りは optional 扱い」) | `references/on-demand-rules/review-noise-discard.md` (discard 7 分類 + 維持対象定義) + reviewer-agent の diff-scale gate / 過剰申告防止 | 同方針。既存 filter が公式 tip の 1 行指示より詳細で追加対応不要 (2026-08-12 確認) |
| 部分 compact (rewind menu の Summarize from here / up to here) | `references/checkpoint-rewind.md` (rewind menu 6 択 + guided summary + /clear 後 previous session entry + symlink skip 制約を反映済) | 同方針。未着手だった「up to here」変種を含め公式 [checkpointing doc](https://code.claude.com/docs/en/checkpointing) と全項目照合し反映完了 (2026-08-12 確認) |
| session 命名 (`/rename`) を branch のように workstream 単位で使う運用 | `references/session-management.md` (/rename 運用を 5 箇所で定義済) | 同方針、追加対応不要 (2026-08-12 確認) |

## 関連 memory

- 2026-07-13 deep-research workflow で 19 source / 71 claims → 3 票反証検証で 22 claims confirmed、本表の再照合 5 件はその結果
- 2026-08-12 再照合 4 件の source: [YC Root Access インタビュー (2026-07-27 Startup School)](https://www.ycrootaccess.com/p/boris-cherny-building-claude-code) / [X: Claude Code 2.1.0](https://x.com/bcherny/status/2009072293826453669) / [X: Code Review](https://x.com/bcherny/status/2031089411820228645)
