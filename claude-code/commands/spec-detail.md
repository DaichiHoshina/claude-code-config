---
allowed-tools: Read, Glob, Grep, Write, Bash, mcp__serena__*
description: 作業計画書 (SPEC) の Phase 1 つについて、既存 code を調べてから実装方法 (method / interface / SQL 方針 / TX / テスト観点) を決める。SPEC を地図のまま保ち、実装形はこの file が持つ
argument-hint: "<作業計画書 path> [--phase <n>] [--out <path>]"
---

# /spec-detail - Phase 1 つの実装方法を決める

> **Goal**: SPEC の Phase n について、既存 code の事実を確かめてから実装形 (method / interface / 契約 / SQL 方針 / TX / 排他 / テスト観点) を決め、`/spec-dev` がそのまま実装できる状態にする。実装はしない。
>
> **語の対応**: ここで SPEC と呼ぶのは作業計画書 (Phase = PR) を指す。一般にいう Spec (誰がどの状況で何を達成するかと、受け入れ条件) は Design Doc に記載する。

**Position**: `/design-doc` (仕様) → `/spec-plan` (Phase = PR 分割) → **`/spec-detail`** (Phase n の実装方法) → `/spec-dev` (Phase n 実装) → `/explain`

## なぜ SPEC と分けるか

SPEC には全 Phase 分が着手前に集まる。実装形まで記載すると、着手しない Phase の method 名と SQL まで読むことになる。SPEC は「どの責務を、どの単位・順序で」の地図に保ち、実装形は着手する Phase の分だけこの file に格納する。

**分離の効果は限定的、行数削減は期待しない。**

- 540 行の SPEC で実装形にあたる「タスク」節は全 Phase 合計 44 行 (8%) だった (2026-09-17)
- 行数の大半は同じ Phase を 2 節に分けて書いた分だが、これも削れる量ではない。7 Phase の SPEC で重複を解消したところ 616 行 → 624 行になり、本体が移動しただけだった (2026-09-17 実測)
- 効果は「着手する Phase 以外の実装形を読まずに済む」点と、次の段落の手戻りの防止になる

method 名・SQL・呼び出し元は既存 code を確かめないと妥当な形が決まらない。上流で決め打ちすると、調査結果と食い違ったときに SPEC ごと書き直すことになるので、Phase に着手する直前に決める。

## When to use (棲み分け)

| Command | Use |
|---|---|
| `/spec-plan` | Design Doc を Phase = PR に分ける。責務までを書き、実装形は書かない |
| `/spec-detail <path> --phase <n>` | Phase n の実装形を決める (この command) |
| `/spec-dev <path> --phase <n>` | Phase n を実装する。詳細設計があれば入力に取る |

「詳細設計して」「Phase n の実装方法を決めて」「実装前に調べて」で発火する。

## Step 0: 省略判定 (最初に行う)

次を全部満たす Phase は詳細設計を書かず、`/spec-dev` へ直行する旨を 1 行宣言して終える。**書かない判断を既定に置く**。器があると埋めたくなるが、埋める価値の無い Phase で 1 file 増やすと、SPEC 肥大を場所を変えて繰り返すことになる。

- TX 境界 / 排他制御 / SQL の条件に判断の分岐が無い
- interface を新設しない (既存 interface の内部実装だけを変える)
- SPEC の 対象 / 対象外 / 完了条件 だけで実装形が一意に決まる

上の 3 条件は DB を扱う実装を想定した語彙なので、script / 定義 file / 文書だけの Phase では 1 つ目と 2 つ目が当たらない。その場合は 3 つ目 (完了条件だけで実装形が一意に決まるか) と、下の「未決の判断があるかどうか」で判定する。

判定するのは**未決の判断があるかどうか**であって、対象 file の数ではない。純粋な rename や機械的な型の置換は、10 file に及んでも判断が無ければ省略する。逆に 1 file でも SQL の条件や TX 境界に選択肢があれば書く (2026-09-17 実踏: file 数を条件に含めていたため、判断の無い 3 file の変更で詳細設計を強制していた)。

migration 単独の Phase と、既存 method の呼び出しだけで完結する Phase はこの条件に当たることが多い。

## Step 1: Phase の scope を読む

1. 引数の path を作業計画書として Read し、`--phase` の Phase 見出し 1 つだけを取る。`--phase` 省略時は詳細設計がまだ無い最初の Phase を選び、Phase 名を 1 行宣言する
2. その Phase の 目的 / 対象 / Read/Write / 対象外 / 完了条件 / 実装への指針 を scope として採用する。**他 Phase の内容を含めない**。2026-09-16 より前の SPEC は 1 つの Phase を「## PR分割計画」と「## 実装計画」の 2 節に分けて書いているので、PR 見出しだけでは 対象 / 対象外 / 完了条件 がそろわない。`grep -n "^### Phase <n>" <SPEC>` で「## 実装計画」側の同じ Phase を探し、両方を合わせて scope とする (2026-09-17 実踏)
3. 「実装への指針」に列挙された repo 規範 (rule file) を Read する。列挙が無ければ `~/.claude/scripts/resolve-repo-rules.sh <対象 file>...` で取得する (exit 3 なら該当なし)。**読む上限は 3 file** とし、この Phase の判断に当たるもの (TX なら database、排他なら concurrency、命名なら言語の rule) を優先する。8 file 返ることがあり、全部読むと Phase 1 つの詳細設計に見合わない (2026-09-17 実踏)。命名 / 型 / 層 / error / test の制約は、この Step で読んだ rule が SoT になる
4. SPEC が Step 2.6 で引き当てた領域 memory の file を Read する (列挙があれば絶対 path でそのまま)

## Step 2: Code Investigation (事実確認に徹する)

Phase の責務が **現在どこでどう実現されているか**を実物で確かめる。ここでは実装方法を決めず、事実だけを集める。

- 対象責務の現在地 (package / file / method)。Serena `find_symbol` / `get_symbols_overview` を使い、file 全体は読まない。**Serena の active project は session の起動 dir で決まり、session 内で切り替えられない**。対象 repo と違う project に bind されていると `FileNotFoundError` を返すので、そのときは `git grep -n "^func "` と `grep -n` で代替し、「Serena 不在のため grep で調査した」と成果物に 1 行注記する (2026-09-17 実踏)
- 呼び出し元の一覧と件数 (`grep -rl` の file 数を数える)
- 依存する interface / 型 / 外部 API / DB
- 関連する既存 test の場所。あわせてその repo の test の書き方を 1 つ確かめ、file 名の規約と build tag と実行 command を転記する
- 変更時に注意が必要な箇所を確認する。JOIN 経由の参照、COUNT クエリ、cache、batch、非同期の処理、監査ログ、ORM の table 登録が対象になる
- SPEC と実物の食い違い

集めた事実は成果物の独立節にしない。実装の判断を変えるものだけを Step 3 の該当項目の下位 bullet に書く。schema の列挙、memory の path、呼び出し件数は、判断を変えないなら書かない。

**調査は AI が行ってよいが、結果の責任は実装担当者が負う**。返した method 一覧と件数は、採用する前に user が確認する前提で記載する。「AI が調べたから正しい」とはしない。

食い違いの扱いは `/spec-plan` Step 2 の判定表に従う。endpoint / field / flag / table / 画面の不足や形の違いは `/design-doc --update` へ戻す。Phase の切り方が変わる規模の食い違い (参照が 10 file を超える等) は `/spec-plan --update` へ戻す。実装経路の詳細だけの違いはこの file に記載して進む。

## Step 3: 実装方法を決める

Step 2 の事実を踏まえ、**記載する価値のある項目だけ**を記載する。判断の無い項目は節ごと作らない (「変更なし」で節を埋めない)。

- 担当する受け入れ条件と、それを担う型 / 操作の対応 (SPEC の完了条件が受け入れ条件を引用しているときだけ)。条件 1 行につき担い手を 1 つ書く。担い手が決まらない条件は実装形がまだ足りていないので、空欄のまま進めず Step 2 の調査へ戻る
- 対象 package / layer、Query か Command か
- interface と method (新設 / 既存の内部実装を変える / 既存の呼び出しを変える のどれか)。名前は Step 1 の repo 規範に従い、根拠にした rule file 名を 1 行添える
- 入出力の型
- 処理フロー (順序か分岐があるときだけ、番号付きで)
- Transaction 境界 / 排他制御 (判断があるときだけ)
- DB 更新条件と SQL 方針。条件の付け方と付ける場所を書き、**SQL 全文は書かない**。JOIN 経由と COUNT にも同じ条件を付けるかどうかの判断をここで決める
- Validation / エラーハンドリング (既存のどの経路へ合わせるか)
- 既存処理との関係 (差し替え / 併存 / 呼び出し変更)
- 契約 (この Phase で型か公開 method を新しく作るときだけ)。**不変条件** (インスタンスが成立している間ずっと満たす条件) / **事前条件** (呼び出し側が満たす条件) / **事後条件** (正常終了時に提供側が保証すること) を 1 行ずつ書き、**それぞれをどこで守るかを添える** (constructor / factory / usecase / DB の制約)。単独の値の範囲は型の内側で守れるが、2 つの値の関係 (割引が元の価格を超えない等) と複数レコードの整合性は型の内側だけでは守れないので、守る場所を分けて書く
### テスト観点

完了条件の test をどう組むかと、mutation check で壊す条件を 1 つ決めておく。

- **fixture 条件**: fixture / test data を新規作成するなら、SPEC の完了条件が引用する条件の数だけ区別できる行 (依頼 / レコード) を列挙する。複数の条件を同じ行で確かめるなら、それが区別不能な状態 (例: DB 上は同じ「対応する行が無い」状態になる) であることを理由として記載する。条件の数より行が少ないまま「fixture を 1 本追加する」とだけ記載すると、実装者はその記述だけでは完了条件を満たす test を書けない (2026-09-14 実踏: 受け入れ条件 8 件に対し fixture が依頼 2 本しか用意していなかった)
- **mutation check**: 契約を記載した Phase では、3 条件のそれぞれに対応する test を 1 つずつ指す (1 対 1 で対応しないものは、その理由を 1 行記載する)
- 変更対象 file (Step 2 で実在を確かめたもの)
- 図を置くときは、同じデータの新旧 2 行など観測できる場面を中心にする。箱の label は「1件取得」「管理画面の件数」のように場面名にし、method 名と SQL は図の下の箇条書きへ出す。関数名と SQL 条件を箱に書いた図は読み手が追えない
- 既存 PR があるときは計画を正とする。計画と PR の差は 1 節に留め、PR の SQL を調査メモへ転記しない

## 既存 detail file の rewrite (再発火 / 見た目の改善依頼)

同じ Phase について `/spec-detail` が再発火する場面がある。command 更新後の再実行、または「図を足したい」「AC 表記でなく平文にしたい」等の見た目の改善依頼が典型で、実装済みか未実装かにかかわらず起こる。

- 出力 file が既に存在するときは、上書き前に既存 file を Read し、記載済みの調査結果と判断を残すか捨てるかを判定する。実装済み Phase の rewrite で調査結果を捨てると、着手時に既に決まった判断を書き直すことになる
- rewrite の主目的が「読み手が理解しやすい形にする」なら、実装判断の中身は保ちつつ、順序 / 図 / 見出しだけを差し替える。Code Investigation の独立節は残さない。判断そのものを書き直すなら、既存判断を書き換える理由を冒頭に 1 行残す
- 受け入れ条件を AC-N 番号で引用していた記述を平文へ書き換えるときは、番号を消すだけでは意味が抜ける。SPEC の完了条件の文言をそのまま引いて、担い手 (method / SQL / 排他) との対応を残す
- 図を足すときは観測できる場面を箱にする。経路の分岐が 3 本以上でも、method 名と SQL を箱に書いた図は置かない

## Step 4: 出力と handoff

- 出力先は `--out` > SPEC と同じ dir の `<SPEC の basename から拡張子を除いた名前>-phase<n>.md`。repo 配下 `.claude/**` へは書かない (write 禁止領域)
- 冒頭は SPEC の path と Phase 名。実装方法から始める。Code Investigation の独立節は置かない
- 分量は 100 行程度を目安にする。上限ではないので、超えるときは判断の無い節が残存していないかを 1 度確認し、削るものが無ければ超えてよい。目安を大きく超えるときは Phase 自体の大きさを疑い、`/spec-plan --update` で Phase を割るかを検討する
- Next command を 1 行だけ記載する: `/spec-dev <SPEC path> --phase <n>`。`--out` で SPEC と別 dir へ出力したときは、この行に詳細設計の絶対 path も添える。`/spec-dev` は SPEC と同じ dir しか検索しないので、添えないと詳細設計を見つけられないまま止まる
- 実装に進まない

## Guard

- 実装しない。code を編集しない
- SPEC と Design Doc を編集しない。不足があれば `--update` の経路へ戻す
- 他 Phase の実装方法を先に決めない (1 回 1 Phase)
- Step 2 の調査結果を「AI が確認済み」として扱わない。user の確認を前提に記載する
- 省略判定に当たる Phase で file を作らない

## Related

- `commands/spec-plan.md` — 入力の作業計画書を作成する。Phase は責務までで、実装形は保持しない
- `commands/spec-dev.md` — この file を入力に実装する
- `commands/design-doc.md` 「完了判定」 #11 — 関数名 / SQL / file 名を Design Doc に置かない判定。行き先はこの command
- `references/design-phase-flow.md` — 遷移全体
- `references/on-demand-rules/spec-flow-episodes.md` — spec 系の実踏エピソード
