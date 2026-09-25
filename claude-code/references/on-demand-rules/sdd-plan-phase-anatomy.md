# /sdd-plan の PR 見出し 6 項目と行数見積の詳細

`commands/sdd-plan.md` Step 3 の PR 見出し直下 6 項目 (対象 / Read/Write / 対象外 / 完了条件 / 実装への指針 / 動作確認手順) の書き方と、想定変更行数の見積規則、`--update` の運用。本文は「6 項目を PR 見出し直下に置く」までに絞り、記述の粒度と NG pattern はここで持つ。

## impl-form 判定 (Step 4 の自己点検)

`spec-gate.sh` の `impl-form` は次を判定する。

- 対象節: 完了条件を除く全節 (処理フロー・既存への影響・マージ順序・リスクと対策も含む)
- 対象語: method / constructor 名、先例の `file:line`、`go generate` や `git grep` での確認手順、TODO comment の位置。作業計画書では責務の言葉に戻す (`/sdd-phase-design` が Phase ごとに決める)
- 対象外: 完了条件の test 名と判定 command はそのまま記載してよい
- 記述の直し方: 処理フローの手順は entry point の名前でなく操作の名前で記述し、既存への影響の根拠列は調査した位置でなく影響の有無を記述する
- `impl-form-bare` の WARN: 括弧を伴わない識別子の一覧で、型名や field 名も同じ形で発生するため FAIL にしていない。列挙された語を 1 つずつ見て、method 名なら責務の言葉に戻し、それ以外なら保持する

## Step 2.5 repo 規範の引き当て

- 記載するのは rule の file 名と、その Phase で適用される制約の 1 行 (命名: interface / method / entity の付け方、型: nullable や ID の型、層: どこに置くか、error: sentinel や status の対応、test: file 名と build tag)。rule 本文は転記しない
- 実装者はこの一覧の rule を着手前に Read する (`/sdd-implement` Step 1)
- 当たる rule が無い対象 file (新規 dir 等) は「該当 rule なし。隣接する <dir> の実装に合わせる」と記載する
- 全 Phase に当たる rule (`**/*.go` 等) は「影響範囲」の節に 1 回だけ記載し、Phase には差分の rule だけ記載する (14 Phase に 12 行ずつ書くと読めない)
- glob に当たらないが file 名の慣習が違うだけの rule (応答を `response.go` でなく `view.go` に置く等) は当たる扱いで記載し、rule 側の glob を修正する PR 文案を chat に出す
- glob に当たるが内容が対象外の rule (他 context 所有の table の話等) は記載しない

## Step 2.6 memory 引き当ての細部

- org 配下の repo では index が repo ごとの sub dir にある (例: `<ghq-root>/github.com/<org>/memory/<repo>/MEMORY.md`)。resolve-dir が返す dir に `MEMORY.md` が無ければ 1 つ上の階層の index を確認する
- hit 行の description で採否を決めず、本文を開く。読む上限は 3 file で、4 件以上 hit したら `**地図**` や `**入口**` の印が付いた行を優先する
- 読んだ内容が Design Doc と食い違ったら、Step 2 と同じ判定表で「DD へ戻す」か「差分表に保持して進む」を決める。memory は書かれた時点の事実なので、file 名や flag は現物で確かめてから採用する
- Phase の「実装への指針」に、適用される制約を rule と同じ形式で 1 行ずつ書き、file 名を絶対 path で添える (`/sdd-implement` Step 1 の実装者と developer-agent がそのまま Read する)

## `--update <作業計画書 path>` の運用

`--update <作業計画書 path>` (または「`作業計画書を直して` / `反映して`」+ 既存の作業計画書 path) のときは全体を再生成せず、Design Doc の変更点 (Implementation Surface の行、受け入れ条件の文言、決定、確定した Qn) を列挙し、影響する Phase の対象 / 完了条件 / タスクだけを Edit する。

- 冒頭の日付の行 (作成日 等) の直下に `最終更新: <YYYY-MM-DD HH:MM> (<変えた内容 1 句>)` を 1 行置く。既にあれば値を上書きし、行を増やさない。時刻は `date '+%Y-%m-%d %H:%M'` で取る
- 入口判定 (未決 Qn) は再実行して結果を入口判定の節に書き換える
- 「Design Doc との差分」は DD に書かれた項目を消す
- 表の cell は prettier の padding で文字列一致が成立しないので、行の key (PR 名 / Phase 名) で当てるか Edit 後に prettier を改めてかける
- 影響する Phase に `<作業計画書の basename>-phase<n>.md` が既にあれば、その file の冒頭へ「無効 (作業計画書更新後。`/sdd-phase-design` で改めて作成する)」と 1 行書き、本文は書き換えない。この 1 行が無いと `/sdd-implement` が更新前の契約をそのまま実装する

## PR 見出しと節構成

- PR 見出しの深さは repo template が H4 で書いていてもよい。`spec-gate.sh` は H3 と H4 の両方を PR 見出しとして数える
- 「PR 分割計画」と「実装計画」を別節に分けず、PR 見出し 1 箇所へ本体を統合する (重複防止)
- repo template が両方の節を保持するときは、Step 1 の「節を勝手に減らさない」を優先して**節は両方保持し、6 項目の本体は PR 見出しの直下にだけ記載する**。「実装計画」側は Phase 見出しと「PR #N を参照」の 1 行で終える。**行数は減らないので、削減を見込まない** (実測は `spec-flow-episodes.md`)

## 6 項目の書き方

- **対象**: 触る層とその責務を、設計の語彙で記述する。repo の層名 (Entity / Model / Reader / Writer / Command / Usecase / Handler 等) と責務 1 行の形にする。
  - **file path は書かない**: 「`pkg/reader/oripa_order_size_selection.go`: 単件 / 複数の取得」でなく「Reader (サイズ選択): 論理削除されたサイズ選択を除いて返す」と記載する
  - **責務は対象を目的語にする**: 「何を返すか / 何を保つか」で記述する。作業の手順 (「参照を限定する」「条件を追加する」) や保存の形 (「有効な行」「列」「JOIN」) を主語にしない。前者は `/sdd-implement` が決める作業、後者は `/sdd-phase-design` が決める実装形で、どちらも読み手が Design Doc の受け入れ条件と対応づけられない
  - Design Doc の Data Schema にある table 名と column 名は、その語のまま記載してよい
  - file path は `/sdd-phase-design` Step 2 が実物で実在を確かめてから Step 3 の「変更対象 file」に記載するので、作業計画書に転記すると未検証の推測が残存する
  - 層の数は影響の広さを示すので、必要なら「影響ファイル数: N」の見込みだけを添える
  - **層と責務の一覧は mermaid の図にする** (`flowchart LR`、1 node = 層名 + `<br/>` + 責務 1 行、呼び出しの向きを矢印で結び、table は円柱 node にする)。PR 本文の「変更箇所と責務」節へそのまま転記する

- **PR 本文の「責務」と「変更箇所と責務」**: PR 本文には「責務」と「変更箇所と責務」の 2 節を置き、作業計画書から次のように転記する。作業計画書側に新しい項目は増やさない
  - 責務: 「この PR で行うこと」に目的を 1 行、「この PR で行わないこと」に対象外を 1 行で書く
  - 変更箇所と責務: 対象の mermaid 図をそのまま置く

- **Read/Write**: この Phase で必要になる Query / Command を、責務 1 行で列挙する。
  - 対象を目的語にする: 「論理削除されたサイズ選択を除いた単件取得と一覧取得」の形で書き、「単件取得の SQL に条件を追加する」のような作業の手順にしない
  - method 名・シグネチャ・SQL は書かず、`/sdd-phase-design` が Phase ごとに決める
  - Design Doc の Implementation Surface に無い責務はここで新規と明記する
  - 既存の呼び出しだけで完結する Phase は「新規なし。既存の <責務> を呼ぶ」と書く

- **対象外**: 隣接するが次 Phase へ送るもの。空にしない

- **完了条件**: test 名 / lint / 特定 API の response のように command で判定できる形。
  - build / test / lint は変更 package に限定して書く (`go build ./pkg/model/...` のように)。repo 全体の `./...` は hook が止めるか時間がかかる
  - 「異常系がテストされている」で止めない
  - spec 型なら担当する受け入れ条件を文の引用で列挙し、各条件をどの test で確かめるかをここで決めて書く
  - **引用は Design Doc の文言をそのまま転記し、backtick で囲む**。NG 用語辞書の検査は backtick の内側を対象外にするので、上流の語を言い換えずに転記できる
  - 辞書に合わせて引用を変形すると、読み手が Design Doc と照合できなくなる
  - `/sdd-implement` はこの引用を完了報告に返す
  - **fixture の行の構成はここに記載せず、`/sdd-phase-design` の「テスト観点」が Phase ごとに決める** (担当二重化の実踏は `spec-flow-episodes.md`)

- **実装への指針**: Design Doc の決定のうち完成形を変えないものをここに記載する (例: 判定処理を 1 つにまとめて共用する、論理削除を発送依頼のキャンセル処理と同じ transaction で行う)。Design Doc には置かない。Step 2.5 で引き当てた repo 規範の一覧「rule file 名: この Phase で適用される制約 1 行」もここに置く。
  - 先例 file:line、method / constructor 名、TODO comment の位置、`go generate` や `git grep` での確認手順のような具体的な作業項目はここに記載せず、`/sdd-phase-design` が Phase ごとに決める (着手前に全 Phase 分を記載すると読めない量になる)

- **動作確認手順**

## Dead code first 雛形 (層で積む慣習の repo)

層で積む慣習で、かつ各 PR が main へ直接 merge され、既存挙動を変えない PR に印 (`[確認不要]` 等) を付ける慣習があれば、`dead-code-first-pr-chain.md` の 10 段の雛形を既定にする。

- 呼び出し元のない実装 (model / repository / usecase / 公開関数) を「既存挙動: 変わらない」で先に並べる
- 配線 PR (flag OFF) と有効化 PR (flag を true にする 1 行) を最後に置く
- 置き換え前の code と flag の削除 PR を chain の末尾に予約する
- 「既存挙動: 変わる」PR は chain 全体で 2 本以下 (有効化と、flag で隠せない画面) を目安にし、3 本以上なら flag の置き場所を再検討する
- この雛形では下の層切りの回数制限 (1 機能 1 回) を適用しない (main に入った dead code は挙動を変えず、削除 PR の期限で残存を受けるため)
- PR 分割計画の各 PR 行に「既存挙動: 変わらない / 変わる (<flag 名> ON のとき)」を書き、Step 4 でその本数を点検する

## 縦切りを既定にした場合の層切り例外

model だけ / query だけ / usecase だけ の層切りは、次の例外条件をすべて満たすときだけ許す。DB migration だけの Phase は従来どおり最初の 1 つに限って許す。

- 切る面が既存の interface か、その Phase で定義する interface である (実装上の理由で仮の境界を作らない)
- 接続先の Phase が同じ計画書内で確定している (計画書外の将来利用のための先出しは `guidelines/writing/stacked-pr-chain.md` Section 3 の YAGNI 違反と同じ扱いで不可)
- 途中 Phase 単体で完了条件を command で判定できる (実装側の unit test を完了条件にする)
- 途中 Phase は担当する受け入れ条件を保持せず「担当条件: なし (Phase k で接続)」と記述し、接続する最後の Phase が受け入れ条件と「merge 後にできること」の Phase 名を保持する
- 層切りは 1 機能あたり 1 回 (interface 1 面) までとし、マージ順序の節に「接続 Phase が merge されないときは途中 Phase を revert する」と期限を記載する (dead code first の雛形を採ったときはこの回数制限を外し、期限だけ記載する)
- repo に feature flag の機構があれば、flag で縦切りのまま小さく merge する案を先に検討し、層切りは flag が使えないときの手段にする

## 想定変更行数の見積 (test 抜き)

- 対象 file の現行行数 (`wc -l`) は上限の根拠にならない。追加・変更する行の見込みを記載し、根拠を 1 行添える
- 見積は、参照 chain の「PR 1 本あたりの平均行数 (test 抜き)」× 今回の PR 本数と比べる。1/2 未満なら、各 PR の根拠 (近い実績 × 変更面の比) を再検討して書き換えるか、下回る理由を 1 行記載する
- 理由を記載する前に、参照 chain に新規ページや一覧 API の再設計が含まれるかを見て、含まれていて今回が既存拡張だけなら目安を 1/3 に下げてよい (毎回同じ理由文を記載しない)
- 数字だけを上げて 1/2 を越えさせない
- test と生成物の除外 pattern は固定する: `_test.go` / `testdata` / `fixtures` / `*.spec.*` / `*_mock*` / `mock_*` / dir 名 `mock/` / `swagger*` / `swag/` / `*.d.ts` / `*.gen.*`
- この pattern は参照 chain の集計と自分の見積の両方に同じく当て、400 行の点検も同じ基準 (手書き行数) で行う
- 根拠の無い数字は Phase 1 の実装後に実測と比べられない
