# Command / Skill Tree (全体見取り図)

全 command (`commands/*.md`) と全 skill (`skills/*/`) の位置関係を 1 file に収めた単一 SoT。作業 flow の幹 1 本と、検証 / 知識 / 保守の 3 根で構成する。詳細 (遷移条件 / resource 対応 / trigger 語) は各 doc に配置し、この file は全体像のみを含む。

**記法 rule**: command / skill 名は必ず code span (`` `name` ``) で書く。`tests/unit/command-tree-coverage.bats` が、全 command / skill 名の code span 登場を検査する。素の文中言及 (review / flow 等の一般語) は登録として数えない。

## 作業の幹 (設計 → 実装 → 出荷)

### 上流: 設計フェーズ

要求の曖昧さに応じて入口を選び、下流へ渡す。入口から先の道順は変更の規模で 3 つの track に分かれる。

| Track | 遷移 |
|---|---|
| 極小 | `/dev` |
| 小さい開発 | `/prd` → `/plan` → `/dev` or `/flow` |
| 大きい開発 | `/prd` → `/sdd-design` → `/sdd-plan` → `/sdd-phase-design` → `/explain` → `/sdd-implement` → `/sdd-review` → `/explain` |

どの track に当たるかの判定と、track ごとの成果物は `design-phase-flow.md` 「Route selection (3 track)」が canonical となる。下の一覧はこの 3 track に登場する command を入口から順に並べたもので、`(大)` は大きい開発だけで使う command を指す。

- `/prepare` — issue / PRD / 関連 doc を読み込み、task の全体像 (要求 `R-n` / 現状 / 未確定点) を chat に整理する (read-only)
- `/brainstorm` — 発散し、対話で要求を限定する (`--debate` で賛否 2 agent)
- `/fact-check` — 案の主張を grep / wc で実測と突き合わせ、採否を判定する
- `/grill` — 確定前の設計案を詰問し、前提の不足を出す (read-only)
- `/prd` — 要件定義 (11-persona review)
- `/sdd-design` (大) — 実装から逆算した仕様書型 Design Doc (受け入れ条件の表 + 決定事項。`--type full` で 12-section)
- `/sdd-plan` (大) — Design Doc を Phase = PR の作業計画書 (Implementation Plan) に分け、対象 / 対象外 / 完了条件を記載する。責務までで実装形は記載しない
- `/sdd-phase-design` (大) — Phase 1 つの実装形 (method / interface / SQL 方針 / TX / テスト観点) を既存 code の調査から決める。単純な Phase は省略する
- `/sdd-implement` (大) — 作業計画書の Phase を 1 つ実装し、完了条件の実行と `/sdd-review` への handoff で閉じる
- `/sdd-review` (大) — 実装した Phase の diff に `/review` を当てる。対象外への変更と `/sdd-implement` の点検表を追加の観点にする。修正するものが無ければ `/explain` へ渡す
- `/sdd-converge` (大 / chain 外) — 全 Phase 実装後に、設計が求めるものと現在の code の差を 4 分類して収束 Phase を作業計画書へ追記する。既定の遷移には入れず、差を確かめたいときに user が発火させる
- 相談: `/fable` — 難所だけ上位 model に助言を求める (定義 file 方針相談は `--consult`)
- 深掘り: `/deep` — 入力の状態から詰問 / 発散 / 妥当性判定 / review 観点を判定し fable で思考を掘る router

### 中央 hub: `/plan`

設計確定後の Phase 分解と実行 mode 判定 (Step 2) を担う。Phase 分解は小さい開発向けで、大きい開発では `/sdd-plan` が同じ役割を担う。実行 mode 判定の方は 3 track のどこからでも使う。簡易判定だけなら `--mode-only` を付ける。Step 0 の guideline 読込は `load-guidelines` が担う。

`/plan` Step 2 が採用する実装 mode:

- inline — 親が直接 Edit する (1 file / 数行、または 3+ file でも各数行)
- `/dev` — developer-agent へ 1 委譲する (1-2 file 単発、または結合の強い 3+ file を直列)
- `/workflow` — deterministic な fan-out / pipeline (7 template: review / migrate / research / understand / judge-panel / scan / loop-until-dry)
- `/flow` — PO / Manager / Dev 階層 + 3 Gates (`--auto` で PR まで全自動、`--parallel` で worktree 並列)
- `/goal` — objective gate (exit code) 到達まで maker-checker で反復する (session 内短期)
- `/loop` — external headless loop (定期実行 / 無人 / >5 iter)
- 実装補助: `/refactor` — 既存 code を再構成する

実装中の葉 skill: `context7` (library API の最新 doc 取得) / `code-comment` (comment 品質)。

### 下流: 出荷フェーズ

- `/review` — code review する (skill 実体: `comprehensive-review`)
- `/review-queue` — 他者の open PR を待ちが長い順に列挙し、1 件の指摘 draft を file に記載する (投稿は user。「今日のレビュー」)
- `/self-review-fix` — 自分が PR に投稿した未対応 review comment に修正 commit + 返信で対応する (`--others` で他者 comment を review-reply-draft へ委譲)
- `/git-push` — commit + push + PR 作成 (`--pr`)。ai-tools の live 反映は `./claude-code/sync.sh to-local --yes` を直接実行する

## 検証の根

実装物の品質を確かめる独立系で、幹のどの段階からも呼べる。

- `/lint-test` — lint + test を一括で実行する
- `/verify-once` — DoD bundle を 1 発で検証する
- `/test` — test を実行 / 追加する
- `/brushup` — 対象 file の自己レビューを収束まで反復する
- `/jp-fix` — 日本語出力の品質を修正する (command が工程を担当し、`skills/jp-fix` は完了応答の gate と起動手順だけを担当する分担)
- `/jp-lint` — jp-quality hook と同じ辞書検査を既存文書へ後追い適用して修正する
- `/review-text` — 内容を知らない第三者レビュアー視点で問題箇所だけを列挙する (read-only、書き直しは `/jp-fix` へ)
- `/norm-apply` — writing 規範を checklist 化して既存 doc 群へ実測適用する (retrofit)
- 障害時は `/diagnose` (debug 支援) → skill `root-cause` (5 Whys) の順で掘る

## 知識・出力の根

作業成果の保存と共有を担う。出力先の使い分けは `work-output-routing.md` を参照する。

- `/explain` — 読み手が理解できる順に chat で説明する (read-only)。実装前は作業計画書の Phase の設計を、実装後は code の詳細を説明する
- `/post-comment` — GitHub issue / PR へ進捗を報告する
- `/handoff` — 作業要約を別 session へ引き継ぐ / 依頼を送る
- skill `local-docs` / `/ld` — 調査ログ / RCA を local HTML 化する (新規は `/ld` の quick が既定、`--full` で規範 Read + Polish)
- `/memory-save` — auto-memory へ即時保存する (`/memory-clean` で整理する)
- `/promote` — memory 知見を CLAUDE.md / skill へ昇格する
- `/retrospective` — session を振り返り、改善を提案する
- `/onboard` — project 初回の context を収集して memory 化する
- `/reload` — compaction 後に CLAUDE.md + memory を再読込する

## 保守の根

config / 環境自体の手入れを担う。

- `/claude-update-fix` / `/serena-update-fix` — tool update に合わせて更新する
- `/update-guidelines` — guideline の鮮度と冗長性を点検する
- `/sleep-review` — 夜間 pipeline の提案を朝に仕分けする
- `/general-clean` — 設定資産の未使用・重複を実測して削除する棚卸し

## 直接起動 skill (command を経ない入口)

- `chain-pr-update` — stacked PR chain を最新 main へ順に伝播する (「chain 更新」)
- `pr-review-digest` — 自分の PR への他者レビューを日次集約する (「PR コメント digest」)
- `review-member` — team メンバーの review 傾向を lens に当てる pre-PR self-review (「レビュアー観点で見て」)
- `review-reply-draft` — 未返信 review comment へ code 根拠付き返信 draft と修正案を作る (「返信 draft 作って」)
- `writing-knowledge` — 書く種別を判定して writing 規範を 1〜2 file だけ読む (「文章執筆」「書き始める」の着手前)

## 詳細 pointer

| 知りたいこと | 参照先 |
|---|---|
| 設計フェーズの遷移条件 / 3 track の選択 | `design-phase-flow.md` |
| command ごとの rule / skill / agent 対応 | `command-resource-map.md` |
| 自然言語 trigger の全 list | `natural-language-triggers.md` |
| 実行 mode の判定表本体 | `commands/plan.md` Step 2 |
| /workflow と /flow の比較 | `commands/workflow.md` |
