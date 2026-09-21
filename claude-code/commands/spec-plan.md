---
allowed-tools: Read, Glob, Grep, Write, Bash, mcp__serena__*
description: Design Doc から作業計画書 (SPEC) を作る。Phase を意味で切って 1 Phase = 1 PR にし、各 Phase に対象 / 対象外 / 完了条件を書く。repo の作業計画書 template があればその節構成に合わせる
argument-hint: "<Design Doc path | 要件の 1 文> [--out <path>] [--phases <n>] [--update <SPEC path>]"
---

# /spec-plan - Design Doc から作業計画書 (SPEC) を作る

> **Goal**: 実装前に作業を意味のある単位 (Phase = PR) に分け、各 Phase を読めば「何を作れば完了か」が分かる作業計画書を 1 file 出す。実装はしない。**分割の判断はレビューのしやすさを最優先にする** (Step 3 「分割の優先順位」)。
>
> **語の対応**: ここで SPEC と呼ぶのは作業計画書 (Phase = PR) を指す。一般にいう Spec (誰がどの状況で何を達成するかと、受け入れ条件) は Design Doc に記載する。

## When to use (棲み分け)

| Command | Use |
|---|---|
| `/spec-design` | 実装から逆算した仕様書型 Design Doc (受け入れ条件の表 + 決定事項) を作成する。`/spec-plan` の入力 |
| `/spec-plan` | Design Doc を実装単位 (SPEC) に分け、PR 構成と完了条件を決める。責務までを記載し、実装形は記載しない |
| `/spec-detail <path> --phase <n>` | Phase n の実装形 (method / interface / SQL 方針 / TX / テスト観点) を、既存 code の調査から決める。単純な Phase は省略する |
| `/plan` | 実行 mode (inline / dev / flow) の判定と plan file。3 track のうち小さい開発で使い、Phase = PR の作業計画書は作らない |
| `/spec-dev <path> --phase <n>` | 作業計画書の Phase n だけを実装し、`/explain` へ渡す (対象外で停止、完了条件の command で done 判定) |

「作業計画書作って」「SPEC に分けて」「PR 構成決めて」で発火する。Design Doc を作成する線引き (API が増える / DB が変わる / 画面が 2 つ以上変わる) に当たらない小さな変更は、Design Doc なしで要件の 1 文から直接この command に入ってよい。

## Step 1: 入力と template の特定

`--update <SPEC path>` (または「SPEC を直して / 反映して」+ 既存の作業計画書 path) のときは全体を再生成せず、影響 Phase だけを Edit する。運用の詳細は `references/on-demand-rules/spec-plan-phase-anatomy.md` 「`--update` の運用」。

1. 引数が file path なら Design Doc として Read する。spec 型 (`/spec-design` の既定、`references/design-doc-spec-template.md`) なら「受け入れ条件」の表を最初に取り、Phase 分割の材料にする (条件は ID を保持しないので先頭 20 字程度を引用して指す)。各条件をどの test (API test / unit test / 手動) で確かめるかは Design Doc に無いので、この command が Phase の完了条件として書き起こす
2. Phase の候補は Design Doc の Implementation Surface (API / Read / Write / 画面の表) から取り、各行をどの Phase に割り当てるかをこの command で決める。method 名・SQL・呼び出し元はここで決めず、`/spec-detail` が Phase ごとに決める (「method の存在は Design Doc、どの Phase かは SPEC、実装形は詳細設計」)。500 行を超える Design Doc は全文を読まず、見出し一覧から Scope (In / Out) / Goals / Non-Goals / API 一覧 / DB 設計 / UI 変更 / リリース計画 / 既存不具合の修正 の節だけを読む。1 文の要件なら、それを「目的」に置き、Design Doc の該当欄は「未作成」と書く
3. repo root で `.claude/docs/plans/template.md` を探す。あれば節構成をその template に合わせ、無ければ下の Output format を使う。template の節を勝手に減らさず、書くことが無い節は「該当なし」1 行にする。進捗記録 / 振り返り / 品質基準のように実装前には埋められない節は見出しと「実装中に記入」の 1 行だけ保持する
4. 出力先を決める。優先順は `--out` > repo の 1 つ上の dir にある `plans/<issue 番号>/` (例: `<ghq-root>/github.com/<org>/plans/37800/`) > 同じ dir にある `docs/plans/` > `~/.claude/plans/`。`plans/` が既にあれば issue 番号の dir を作成して使い、`docs/plans/` は既存の環境のための後段の候補として保持する (新しく作成しない)。file 名は issue 番号の dir に置くとき `<slug>.md` (番号は dir が保持するので prefix を付けない)、それ以外は `<issue 番号>-<slug>.md`、issue 番号が無ければ `<日付>-<slug>.md`。**worktree で作業しているときの基準は worktree の 1 つ上の dir (`<ghq-root>/worktrees/`) でなく元 repo の 1 つ上の dir で、元 repo の位置は `git rev-parse --git-common-dir` で確認する**。repo 配下 `.claude/**` へは記載しない (write 禁止領域)

**入口の判定 (Design Doc が SPEC を書ける状態か)**: `commands/spec-design.md` 「完了判定」 のチェックリスト 13 項目を Design Doc に当て、満たさない項目があれば Phase 分割に入らず「Design Doc との差分」に記載して `/spec-design --update` へ戻す。特に #12 (Design Doc だけで作業計画に落とせるか) と #13 (実装者が変わっても完成形がズレないか) を満たさない Design Doc から Phase を切ると、Phase ごとに要件を考え直すことになる。あわせて Open Questions (未確定事項) の「決める時点」を見て、「SPEC 作成前」「DD レビュー」の Qn が未決のまま残存していれば Phase を切らず、Qn と確認先を chat に出して止める。

## Step 2: 影響範囲を実物で確かめる

Design Doc が無い 1 文の要件で入ったときは、他の手順より先に**要件が既に実装されていないか**を確かめる (この経路は下の Design Doc 走査手順が使えないので、既存実装の確認がその代わりになる)。
1. 要件に登場する名詞 (script 名 / 機能名 / table 名 / command 名) を語にして `git grep -l` と `ls` を実行する
2. 実在したものは新規作成の Phase を切らず、「既存実装の確認」の節に file 名と行数と test の有無を記載する。Phase は残りの差分だけで切る

Design Doc に記載された API / Query / Command / 画面ごとに、既存 code の置き場所を Serena `find_symbol` / grep で検索し、対象 file と test file を列挙する。**列挙したら、1 件ずつ production の呼び出し経路から到達するかを確かめる**。語句の検索に hit するだけの箇所 (production から呼ばれない method や、別機能の同名の処理) を対象に含めると、到達しない code へ条件を追加する Phase を作ることになる。到達しない箇所は対象から外し、その理由を 1 行記載する (2026-09-20 実踏: 呼び出し元が 0 件の重複解決の SELECT を参照箇所に数え、後続 Phase が削除する code へ条件を追加する計画にした)。

### Change Map (影響範囲の先頭に置く)

**Change Map はシステム構造の中で、今回どこを変更し、どこを変更しないかを示す図とする**。変更しない箱も描き、印の有無で変更の有無を示す。この定義が `対象` 欄との役割の違いを作る (`対象` は触る層だけを列挙するので、触らない層という情報が表に現れない)。**変更しない層も描くことで、「記載漏れ」と「確認したうえで変更不要」を区別できる。**

**実行時の呼び出し経路と同じにする必要は無い**。起動時の設定や型の定義のように、実行時には通過しないが変更が波及しうる箇所も箱にしてよい。3 つの図の役割は次のとおりで、重ならないようにする。

| 図 | 何を表すか | 置き場 |
|---|---|---|
| 振る舞いの図 | 実行時の振る舞い | Design Doc の振る舞いの節 |
| Change Map | 変更が波及する構造 | SPEC の `影響範囲` |
| マージ順序の図 | 実装と merge の順序 | SPEC の `マージ順序と依存関係` |

- mermaid の `flowchart TB` で記載し、**変更する層の label に印 (`★`) を付ける**。印の無い箱が「確認したうえで変更しない層」を表す
- **描く層の決め方**: `resolve-repo-rules.sh --get layers` が値を返す repo はその全層を箱にする。exit 3 (未宣言) の repo は **SPEC から実在を確認できた箇所だけ**を箱にし、**推測で補わない**
- 箱の label は層名と印だけにし、変更の中身と method 名と SQL は箱に入れない。層の数による下限は設けない (記載形式の細目は `references/on-demand-rules/spec-plan-phase-anatomy.md`)

個別の判定 (参照件数と Phase 配置、Data Schema の不変条件、ORM 登録、生成物差分、test file の実在確認、画面の repo 特定、Design Doc と code の食い違いの扱い) は `references/on-demand-rules/spec-plan-scope-scan.md` を Read する。

## Step 2.5: repo 規範を Phase に引き当てる

`~/.claude/scripts/resolve-repo-rules.sh <Phase の対象 file>...` を Phase ごとに実行し、返った rule を「実装への指針」に記載する (exit 3 なら manifest 未設定なので「該当 rule なし」として進む。schema は `references/on-demand-rules/repo-rules-manifest.md`)。記載形式・rule 該当時の扱い・glob の例外は `references/on-demand-rules/spec-plan-phase-anatomy.md` 「Step 2.5 repo 規範の引き当て」を Read する。

## Step 2.6: 領域 memory を引き当てる

Design Doc の対象領域 (ディレクトリ名や table 名から取る。例: `oripa` / `payment` / `shipment`) を語にして memory index を grep し、hit した file を Read する。既知の trade-off と実装世代の地図がここにあり、読まないまま Phase を分けると判断済みの制約を作業計画書が取り消してしまう (`grep -niE '<領域語>' "$(bash ~/.claude/scripts/memory-save-helper.sh resolve-dir)/MEMORY.md"`)。読み方 (index 位置、上限、DD との食い違いの扱い、記載形式) は `references/on-demand-rules/spec-plan-phase-anatomy.md` 「Step 2.6 memory 引き当ての細部」を Read する。

## Step 3: Phase を意味で切る

Phase 分割の前に、Design Doc の主要な操作 (発送依頼、注文確定 等) ごとの処理順序を「処理フロー」節に番号付きで書き出す (Phase の対象・依存関係・Read/Write の洗い出しの元にする)。変わる手順には Change Map と同じ `★` を付け、担当 PR を 1 行で添える (変わらない手順も書き、印の有無で「確認したうえで変更なし」を区別する)。**分割の優先順位**: 本番を壊さない merge 順序は前提条件で、その範囲の中でレビューのしやすさを最優先に切る。判断が競合したら上の項目を採り、下の項目を諦めた理由を PR 分割計画に 1 行書く。

Phase が 3 つ以上になったら、`references/purpose-traceability.md` に従い「目的と実装の対応」を作る (2 つ以下なら作らない)。

- **作る条件・記載形式**: Phase 3 つ以上のときだけ作る。この SPEC で初めて `Context → Purpose → 受け入れ条件 → Phase` を対応づけ (Design Doc には置かない)、Purpose ごとに節を分け、Context 1 文 + 表 (`| 分類 | 条件 | 担当 Phase |`) で記載する。入力に無い文脈は推測せず `文脈: 未記載` とする
- **禁止**: Mermaid の図は作らない (受け入れ条件と Phase の対応は 1 段の多対多で、表の「担当 Phase」列がそれを示す。図にしても表に無い情報が増えない)。同じ図は詳細設計にも置かない (`/spec-detail` Step 3 の「受け入れ条件と担い手の対応」「契約」「テスト観点」が同じ内容を扱う)

1. **reviewer がその PR だけで採否を決められる**。diff と PR 本文だけで正しさを判断でき、他の PR の diff を開いたり実装者に意図を聞いたりせずに済む
2. **1 PR = 1 目的で、変更行数が小さい**。test 抜き 400 行を上限、200 行前後を目安にする。目的の違う変更 (機能の追加と既存の不具合の修正、実装と rename) を 1 本の PR に同居させない
3. **reviewer が見慣れた形にそろえる**。層切りか縦切りか、既存挙動を変えない PR への印の付け方は repo の慣習に合わせる。慣習どおりに切ると 1 か 2 を満たせないときだけ慣習から外れ、外した理由を記載する
4. **実装の作りやすさ**。上の 3 つを満たす切り方が複数あるときの決め手にする

- Design Doc にリリース計画 (DB → admin → ユーザー UI のような段階) があれば、Phase の順序はそれに従う。無ければ「merge しても本番が壊れない順」で並べる
- 1 Phase = 1 PR。BE と FE が別 repo のときは Phase を共通にし、repo ごとに PR 1 本ずつとする (PR 分割計画に repo を記載する)。Phase 名は「サイズ取得機能を追加する」のように、merge 後にユーザーか運用者ができることで記述する
- 切り方 (縦切り / 層切り) は優先順位 3 に当たるので、repo の慣習を先に測って決める。同じ機能領域の直近の merged PR を `gh pr list --search "<issue 番号 or 機能名>" --state merged` で 5 本程度引き、title と diff の層 (pkg だけ / svc と adapter だけ 等) を見て、層で積む慣習なら層切りを既定にし、reviewer の指摘 (memory の review feedback を含む) があればそれに従う。慣習が無い repo だけ縦切りを既定にする
- 層で積む慣習で dead code first の雛形が使える repo は `references/on-demand-rules/spec-plan-phase-anatomy.md` の「Dead code first 雛形」を Read する。**PR 分割計画の冒頭に flag の判断を 1 行記載する**: 雛形を採るなら `- flag: <flag 名> (配線 PR で OFF、有効化 PR で ON)`、採らないなら `- flag: 使わない (理由: <1 文>)`。この 1 行が雛形を採ったかどうかの印で、`spec-gate.sh` の behavior 判定は「変わる」が 3 本以上のとき、この行の内容で FAIL と WARN を分ける
- 縦切りを既定にした場合、model だけ / query だけ / usecase だけ の層切りは例外条件をすべて満たすときだけ許す (条件と DB migration の扱いは `spec-plan-phase-anatomy.md` 「縦切りを既定にした場合の層切り例外」)
- Design Doc の In Scope に「既存不具合の修正」が同居していれば、ユーザーから見える挙動が別なので独立した Phase にし、新機能の Phase より前に置く
- **PR の見出しは `### PR #N: [Phase 名]` だけにする**。依存 / branch / 既存挙動 / 想定変更行数は見出しに詰め込まず、直下の箇条書きに 1 項目 1 行で記載する (見出しに 4 項目を並べると、Phase 名がどこまでか読み取れない)。Phase = PR 見出し 1 つに、次の 6 項目 (目的 / 対象 / Read/Write / 対象外 / 完了条件 / 実装への指針 / 動作確認手順) を直下に記載する。**対象 / 対象外 / 完了条件** は見出し直下に置く。各項目の書き方・PR 見出しの深さ (H3/H4)・「PR 分割計画」と「実装計画」節の重複防止は `references/on-demand-rules/spec-plan-phase-anatomy.md`。Phase 名は対象を目的語にした 1 文 (「サイズ選択の参照を有効な行に限定する」でなく「取り消されたサイズ選択を参照から除く」)
- Phase が 3 つ以上なら、PR 分割計画に依存の向きとマージ順序を書き、`guidelines/writing/stacked-pr-chain.md` の chain 運用を前提にする
- Design Doc に「不変条件の担い手」の表があるとき (制約を削除または緩める変更)、「外した後の担い手」を実装する Phase を同じ計画書に置き、制約を削除する Phase との前後関係をマージ順序の節に記載する。**担い手を先に merge する順序を既定にする**。順序ごとに記載する内容が違うので取り違えない
  - 担い手が先のとき (既定): 2 つの Phase の間は制約と担い手の両方が守るので、同日 merge にしない。「担い手を先に有効化し、次の Phase で制約を撤去する」と記載する。**この区間を「保険が無い」と記載しない** (risk の向きが逆になる)
  - 制約の削除が先のとき: 2 つの Phase の間は担い手が不在なので、同日 merge にするか、その期間を何が守るかを明記する。既定から外れる理由も 1 行記載する
表の「外す制約が防いでいた場面」は、担い手 Phase の完了条件で同時実行 test として引き当てる
- PR 分割計画の各 PR に「想定変更行数 (test 抜き)」を記載する。Step 4 の 400 行点検はこの値で行い、値が無い計画書は点検できていない扱いにする。見積の規則 (参照 chain との突き合わせ、1/2 判定、除外 pattern) は `references/on-demand-rules/spec-plan-phase-anatomy.md`
- `--phases <n>` は上限であって目標ではない。意味の単位が n 未満ならそのまま少なく出す

## Step 4: 自己点検 (write 前)

Write した後に `~/.claude/scripts/spec-gate.sh <path>` を実行し、FAIL 0 を確かめる (各 PR の想定変更行数、400 超の分割しない理由、branch 名、実装形の混入を機械で判定する。branch 名の形まで判定するのは repo が `branch_pattern` を宣言しているときだけで、未宣言の repo は名前があるかだけを判定する)。以下は書く前の目視点検。

次を 1 つでも満たさなければ Step 3 に戻る。先頭の 2 つは分割の優先順位の 1 と 2 に対応するので、他が全部成立していてもこの 2 つを満たさない Phase は切り直す。

- 各 Phase が、その PR の diff と説明文だけで正しいか判断できる。判断に他の PR の diff を読む必要があるなら、切り方か説明を修正する (依存する PR の「merge 後にできること」を前提として記載するのはよい)
- 各 Phase の想定変更行数 (test code を除く) が 400 を超えない。超える Phase は目的か依存の単位で切り直し、それでも超えるときだけ Step 3 の例外条件を満たす interface 境界で層切りする (file 数を減らすための分割は別問題で、ここでは行数だけを判定する)
- 各 Phase を単独で merge しても本番が壊れない (壊れるなら Phase の切り方が層になっている)。各 Phase の完了条件が command で判定できる。完了条件に記載した test file が実在するか、「新規作成」と記載されている
- **完了条件の引用を Design Doc の原文と 1 件ずつ照合する**。数だけでなく文字列が一致しているかを確かめ、一致しない行は原文へ差し替える。要約や言い換えのまま引用の体裁にすると、実装者が期待値を取り違える。原文に NG 用語辞書へ当たる語が含まれるときは、言い換えず backtick で囲む
- fixture の行の構成、SQL の句、画面要素の名前が SPEC に残存していない。いずれも `/spec-detail` が Phase ごとに決めるので、SPEC 側は「条件 N 件を区別できる fixture を新規作成する」までにする
- 完了条件を除く全節に実装形が混入していない (`spec-gate.sh` の `impl-form` が判定する。判定対象の節、`impl-form-bare` の WARN の扱いは `references/on-demand-rules/spec-plan-phase-anatomy.md` 「impl-form 判定」)
- 各 Phase の対象外が空でない
- **同じ実測値を 2 つ以上の節へ転記していない**。参照箇所の数のように複数の節で必要になる値は、正本の節を 1 つ決めて他の節はそこを参照する。**参照する側は値を書き写さず、正本の節名だけを記載する** (「正本は〇〇」と書きながら値も併記すると、正本を更新したときに併記した側が古い値のままになる)。合計を記載するときは内訳から計算し直した値にする。転記した値は片方だけ更新されて食い違う (2026-09-20 実踏: 参照箇所の数が 3 つの節で 10 / 7 / 6 に割れ、古い 2 つは 12 日前の計画書の文言のまま残存していた)
- **`影響範囲` の先頭に Change Map があり、変更しない層も箱になっていて、変更する層の label に `★` が付いている** (`spec-gate.sh` の `change-map` が節と mermaid の有無を判定する)。`layers` 未宣言の repo で、SPEC から確認できない層を推測して箱にしていない
- **`処理フロー` に `★` の付いた手順があり、その手順の末尾に担当 PR が添えてある** (`spec-gate.sh` の `flow-mark` が判定する)。印の無い手順は挙動が変わらない手順を指す
- Phase の合計が Design Doc の API / 画面 / Query / Command の数と一致する (不足も余剰も無い。責務の数で数え、method 名では数えない)。spec 型なら受け入れ条件の全行と、Design Doc が PRD の番号で参照している条件の全部が、いずれか 1 つの Phase に割り当てられている (割り当て不足は Design Doc 側の不足なので `/spec-design --update` へ戻す)。層切りした途中 Phase は「担当条件: なし」でよく、この点検の対象から外す。Design Doc が無い 1 文の要件では数を突き合わせる相手が無いので、代わりに Step 2 の「既存実装の確認」を読み直し、実在すると確かめたものを新規作成する Phase が残存していないかを確かめる
- Phase が 3 つ以上のとき「目的と実装の対応」があり、その表の条件と Phase が本文の受け入れ条件と Phase を過不足なく参照している。表にだけ存在する条件や Phase が無い。**表の条件の数を Design Doc の受け入れ条件の数と突き合わせる**。表が多いときは SPEC 側で条件が増えているので、`/spec-design --update` へ戻すか受け入れ条件から削除するかを決める。分類にまとめたときは、分類名が Design Doc の受け入れ条件の語と一致しているかも確かめる
- **「目的と実装の対応」に Mermaid の図が無い**。この節は表だけにする (`references/purpose-traceability.md`)。3 PR 以上のとき、依存の向きが書かれている
- 制約を削除する Phase があるとき、「外した後の担い手」の Phase が同じ計画書にあり、2 つの間隔がマージ順序の節に書かれている
- 各 PR の直下の箇条書きに「依存:」「branch:」「既存挙動:」「想定変更行数:」の 4 行があり、PR 分割計画の冒頭に `- flag:` の 1 行がある。dead code first の雛形を採った (flag を使う) ときは「変わる」の PR が 2 本以下である (3 本以上なら flag の置き場所を修正する)。flag を使わないときは本数を点検せず、理由の 1 文があるかを確かめる。既存挙動を変えない PR の title に repo の印 (`[確認不要]` 等) を付ける前提を PR 分割計画に 1 行記載する

## Output format (template が無いときの骨格)

```markdown
# 作業計画書: [機能名]

## 関連ドキュメント
- Design Doc: [path または 未作成]

## 目的

## 目的と実装の対応 (Phase が 3 つ以上のときだけ、`references/purpose-traceability.md` に従う)

## 影響範囲
### Change Map (構造の中の変更境界。mermaid の flowchart TB。変更しない箱も描き、変更する箱の label に `★` を付ける)
### 既存実装の確認 (Design Doc が無い 1 文の要件のときだけ書く)
### 対象ファイル / ディレクトリ (層と責務。file path は `/spec-detail` へ送る)
### テスト対象
### Design Doc との差分

## 処理フロー
[主要な操作ごとに番号付きの手順。今回の変更で挙動が変わる手順の先頭に `★` を付け、末尾に担当 PR を添える (例: `★ サイズを選択する — PR #3 で発送依頼の transaction の内側へ移動する`)。印の無い手順は変わらない]

## PR 分割計画
- flag: [使わない (理由: 1 文) / <flag 名> (配線 PR で OFF、有効化 PR で ON)]
### 計画外の PR (実装中に見つかる不具合 / 既存の欠け / review 後の見た目調整。目安は実装 PR の 3 割)
### PR #1: [Phase 名]

- 依存: なし
- branch: [...]
- 既存挙動: 変わらない
- 想定変更行数: [N] (根拠: [近い実績 × 変更面の比を 1 行])
**対象**: [層と責務。file path は書かない]
**Read/Write**: [責務 1 行で列挙]
**対象外**:
**完了条件**:
**実装への指針**: [完成形を変えない決定 + Step 2.5 で引き当てた rule]
#### 目的
#### タスク (責務の単位。file:line / method 名 / TODO comment 位置は `/spec-detail` が決める)
#### 動作確認手順

### PR #2: [Phase 名]
(PR #1 と同じ構成。既存挙動は「変わる (<flag> ON のとき)」の形で記載する)

### マージ順序と依存関係
```

## Step 5: 出力と handoff

- 作業計画書を Step 1 の出力先に Write し、path を chat に出す。分割に迷いが残るときは相談用の文を 3 行以内で添える。冒頭に PR 数と目安日程 (着手から最初の PR まで数日以内) を記載し、team 共有用の文を chat に 3 行以内で出す。着手後に想定と違えば手を止めて `/spec-plan` を再実行する
- Next command を 1 行記載する: `/spec-detail <path> --phase 1` (`/spec-detail` Step 0 の省略判定に当たる Phase なら `/spec-dev <path> --phase 1`)。作業計画書の末尾に「各 Phase は `/spec-detail` で実装方法を決めてから `/spec-dev` で実装し、`/explain` で差分の説明を受けてから PR 作成と次 Phase へ進む」を 1 行添える
- 実装に進まない。`/spec-dev` 以降は実装経路に戻す

## Read-only (作業計画書以外)

記載するのは作業計画書 1 file だけで、code / Design Doc / repo 配下 `.claude/**` を編集しない。Design Doc に不足があれば「Design Doc との差分」に記載して user に戻す。

## Related

実踏エピソード: `references/on-demand-rules/spec-flow-episodes.md` (他の参照先は本文中に記載済み)
