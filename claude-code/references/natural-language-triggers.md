# Natural Language Triggers

Only high-frequency patterns are interpreted from natural language. For others, use explicit commands (`/commandname`).

全体像 (全 command / skill の配置) は `command-tree.md` に集約する。この doc は自然言語 trigger の対応表に限定する。

## Trigger list

| User input | Command executed |
|------------|----------------|
| "痩せさせて", "不要なもの消して", "設定を棚卸し" | `/general-clean` (実測 → fact-check → 削除候補表) |
| "pushして", "push" | `/git-push --pr` (create branch → PR) |
| "main push", "mainにpush" | `/git-push --main` (push directly to main) |
| "sync push", "push sync" | `/git-push` → `sync.sh to-local` (ai-tools repo only) |
| "syncして", "sync して", "同期して" | `./claude-code/sync.sh to-local --yes` を直接実行する (ai-tools repo only) |
| "全自動で", "autoで", "おまかせ" | `/flow --auto` |
| "横並びで", "同じ修正を" | Multi-repo parallel work |
| "レビュー", "レビューして", "コードレビュー" | `/review` (default, mode auto-detected internally) |
| "PR<番号>レビュー", "<PR-URL>レビュー" | `/review <PR>` |
| "観点全部でレビュー", "ガイドライン全載せでレビュー", "DDD/CA 観点も含めてレビュー" | `/review-full` (guideline 全載せ → `/review`) |
| "codexでレビュー", "セカンドオピニオン" | `/review --codex` |
| "設計レビュー", "敵対レビュー", "設計問い詰め", "アーキテクチャレビュー" | `/review --adversarial` (codex adversarial-review delegation) |
| "深掘りレビュー", "厳しめレビュー", "徹底レビュー", "詳細レビュー" | `/review --panel --codex` (3-lens 並列 + codex 別視点。旧 `--deep` は 2026-07-23 disable 済) |
| "リリース前レビュー", "PR最終レビュー", "全部入りレビュー", "全力レビュー" | `/review --multi <PR>` (4 methods parallel, max cost) |
| "クラウドでレビュー", "ultrareview" | `/code-review ultra` (built-in slash command, cloud parallel, separate billing。`/ultrareview` は deprecated alias) |
| "ブレスト", "設計検討", "アイデア出し", "発散させて", "案を並べて" | `/brainstorm` (interactive design refinement) |
| "並列実行で" | `/flow --parallel` (worktree proposal, PO confirmation required) |
| "Developer 並列で" | `/flow --parallel` (same) |
| "worktree 分けて" | `/flow --parallel` (same) |
| "wt 分けて" | `/flow --parallel` (same) |
| "team で", "agent team で" | `/flow` (force PO/Manager/Dev hierarchy) |
| "分担で", "本格的に" | `/flow` (same, skip lightweight task pre-check) |
| "workflow で", "pipeline で", "多数決で", "fan-out で" | `/workflow` (deterministic fan-out via Workflow tool; 7 templates: review / migrate / research / understand / judge-panel / scan / loop-until-dry) |
| "ループで回して", "回し続けて", "通るまで回して" | `/loop` (gate 明示あり → init→run、なし → 4 条件 pre-check から。≤5 iter 見込みの短期は `/goal` を優先) |
| "定期実行して", "毎朝回して", "cron にして" | `/loop cron` (manual run の Status: done 実績が必須、なければ先に `/loop run`) |
| "夜通しで回して", "無人で回して" | `/loop run --bg` (external headless loop を background 起動) |
| "fableで", "fable に聞いて", "fable で考えて", "fable で相談", "難所なので fable" | `/fable <task>` (難所のみ model override 委譲、"fable に聞いて" は `--consult`) |
| "ブラッシュアップして", "セルフレビュー繰り返して", "磨き込んで" | `/brushup <target>` (実物突き合わせ self-review 反復) |
| "説明して <対象>", "解説して <対象>", "この実装を理解したい" | `/explain <対象>` (実装を理解できる順に chat へ説明する read-only。対象の無い「説明して」は通常の chat 応答) |
| "深掘りして", "掘り下げて", "fableで深掘り" | `/deep <topic>` (fable で掘る router。"深掘りレビュー" は `/review --panel` 優先) |
| "別セッションに送って", "あっちの session に伝えて", "セッションに引き継いで" | `/handoff` (ListAgents で宛先解決 → 自己完結要約を SendMessage) |
| "Slack に送って", "Slack に送って" | `mcp__claude_ai_Slack__slack_send_message` (confirm channel/DM first) |
| "Notion に書いて", "Notion メモして" | `mcp__claude_ai_Notion__notion-create-pages` (confirm parent page first) |
| "PR コメント残して", "レビューコメント残して" | `/post-comment` (PR number/URL required) |
| "レビューする PR ある?", "review queue", "今日のレビュー" | `/review-queue` (他者 PR の候補列挙 → 指摘 draft、投稿はしない) |
| "私のコメントに対応して", "PR コメント対応して", "self review fix" | `/self-review-fix` |
| "自分以外のコメントも対応して", "他の人のコメントも対応して" | `/self-review-fix --others` (review-reply-draft へ委譲、commit と post はしない) |
| "PRコメント読み込んで", "PR読み込んで" | `gh pr view --comments` で最新レビューコメントを取得し、`$MEM/pr_<repo>_<n>_review.md` があれば Read して対応方針を提示する (session 再開時の再指示を定型化) |
| "メンバーからの PR コメント差分", "PR コメント差分", "member 差分" | `pr-review-digest` skill `--chat` |
| "直列で", "sequential で", "順番に", "並列やめて" | `/flow --sequential` (parent が並列不可と判断した時の opt-out) |
| "多数決レビュー", "N 人でレビュー", "lens 別レビュー", "厳密レビュー" | `/review --verifier-panel=N` (3 lens 並列 review) |
| "判定だけ", "mode 判定のみ", "判定して実装しない" | `/mode --judge-only <task>` (実装せず判定結果だけ返す) |
| "staleness だけ", "redundancy だけ", "readability だけ" | `/update-guidelines --only=<axis>` |
| "TDD で", "test-first で", "テスト先に書いて" | `/test --tdd` (RED-GREEN-REFACTOR cycle 強制) |
| "plan して", "設計と実装計画", "phase 分けて" | `/plan <task>` (設計 + Phase 分解 + mode 判定 + plan file 保存) |
| "実行方法選んで" | `/mode <task>` (mode 判定 + 実装。"判定だけ" は `--judge-only` が優先) |
| "dev で実装" | `/dev <task>` (1-2 file を developer-agent に委譲。1 file 単発は inline 優先) |
| "詰問して", "不足を突いて" | `/grill <設計案>` (設計案の前提・未決定点を 6 観点で詰問、read-only) |
| "lint と test" | `/lint-test` (lint + test を bundle 実行) |
| "verify して", "動作確認" | `/verify-once` (実装変更を実際に動かして smoke 検証。精査は `/verify`) |
| "review して直して push" | `/review --push` (`/review` → 全 fix → 再 review → `/git-push --pr`) |
| "memory に保存", "覚えて" | `/memory-save <topic>` (session 知見を `<repo-root>/memory/` に恒久化) |
| "local-docs に書いて", "runbook 作って", "さくっと doc" | `/local-docs` = `/ld` (新規は quick が既定。`_index/new-doc.mjs` で起こし、規範 Read と Polish は `--full` 時のみ。update は skill 側) |
| repo 側 `/spec:design` / `/spec:plan` / `/spec:execute` (repo 側の正この rule dir) で設計書 / 計画書 / 実装を求められた | `/spec-design` / `/spec-plan` / `/spec-dev` へ誘導する (repo 側の出力先 `.claude/docs/` は write 禁止で成果物を保持できない。08-28 〜 09-03 の 32 回発火で file 0 件を実測)。`/spec:review` `/spec:quality` は相談用途としてそのまま使う |
| "Phase n 実装して", "計画書の次の Phase やって", "SPEC 通りに実装" | `/spec-dev <作業計画書 path> --phase <n>` (Phase 1 つを実装し、完了報告で `/explain` を Next に出す) |
| "作業計画書作って", "SPEC に分けて", "PR 構成決めて" | `/spec-plan <Design Doc path>` (Phase = PR の作業計画書。repo template があれば節構成を合わせる) |
| "design doc 書いて", "DD 起こして" | `/spec-design <feature>` (12-section 設計 md を team 共有用に起草) |
| "全体像把握して", "issue 読んで整理して", "タスク理解して" | `/prepare <issue URL / PRD path>` (出典を集めて要求 `R-n` / 現状 / 未確定点を整理、read-only。出口は `/prd` か `/spec-design`) |
| "PRD 書いて", "要件整理して" | `/prd <feature>` (PRD 起草) |

## 規模による入口 (3 track)

上の表は command 名を含む発話を command へ対応づけるもので、規模の判定を経ない。command 名を含まない依頼 (「この bug 直して」「〜機能を追加して」) では、変更の規模で入口が変わる。

| Track | 入口 |
|---|---|
| 極小 | `/dev` |
| 小さい開発 | `/prd` → `/plan` → `/dev` or `/flow` |
| 大きい開発 | `/prd` → `/spec-design` → `/spec-plan` → `/spec-detail` → `/spec-dev` → `/explain` |

判定と track ごとの成果物は `design-phase-flow.md` 「Route selection (3 track)」が canonical となる。上の表のうち `/spec-design` / `/spec-plan` / `/spec-detail` / `/spec-dev` の行は、大きい開発の track にだけ当たる。

## Not interpreted

Inputs not listed above (`修正してpush`, `元に戻して`, `codexで{task}` etc.) are not interpreted from natural language. Use explicit commands (e.g., `/undo`). Avoids misinterpretation and token waste.
