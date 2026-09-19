---
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, AskUserQuestion, mcp__serena__*
description: 実装から逆算した仕様書型 Design Doc (spec) を md で書く。振る舞いを受け入れ条件の表で固定し、/spec-plan の入力にする
argument-hint: "[topic | --prd <path> | --update <path>] [--out <path>] [--type spec|full] [--dry]"
---

# /design-doc - 実装から逆算した仕様書型 Design Doc

> **Goal**: Design Doc は、完成形だけでなく、その変更を構成する API・Read / Write・画面・必要なシステム能力まで整理し、SPEC で PR 単位の実装計画へ分解できる状態にする文書。SPEC はその変更面を Phase = PR・層と責務・完了条件へ具体化する文書。file / method / SQL は `/spec-detail` が書く。短く言えば「Design Doc = PR 分割できる粒度までシステム変更面を設計する文書、SPEC = その変更面を実装順と PR へ具体化する文書」(user 決定 2026-09-05)。完成条件は「Design Doc だけを読んだ人が、実装詳細を知らなくても『何を作れば正解か』を判断できる状態」。

> **語の対応**: ここで SPEC と呼ぶのは作業計画書 (Phase = PR) を指す。一般にいう Spec (誰がどの状況で何を達成するかと、受け入れ条件) は Design Doc に記載する。

## Design Doc と SPEC と詳細設計の境界 (canonical)

| Design Doc に記載する | SPEC に記載する | `/spec-detail` に記載する |
|---|---|---|
| 背景・課題 / 目的 / 要件 | Phase = PR と実装順序 | 変更 file / 関数・メソッド / SQL / Interface |
| 期待する振る舞い / API・DB・UI の変更 (何が増え、何が変わるか) | 触る層とその責務 | 契約 / TX / 排他 |
| 制約 / 非対象 / Acceptance Criteria | 完了条件 (どの test で確かめるか) | test の実装方針 |
| 設計上の重要な決定 (完成形を変える決定) | 処理の置き場や共用の仕方 (完成形を変えない決定) | migration 手順 / code レベルの詳細 |

判定基準は「それが変わったとき完成形が変わるか」。関数名や処理の分け方が変わっても完成形が同じなら Design Doc の外側になる。ただし **method の「存在」は Design Doc、どの Phase で作るかは SPEC、method の「実装形」は詳細設計**。「発送手続き中の注文が指定サイズを採用しているか判定する Read が必要」までは Design Doc に記載し、その method 名・SQL・呼び出し元は `/spec-detail` が記載する。Design Doc に PR1 / PR2 のような分割は記載しない。

**Position**: `/prepare` (全体像) → `/prd` (要件) → `/design-doc` (仕様 = spec) → `/spec-plan` (Phase = PR 分割) → `/spec-detail` (Phase n の実装方法、省略可) → `/spec-dev` (Phase 実装) → `/explain` (Phase の差分を理解)

> 遷移条件と skip 判断: `references/design-phase-flow.md`

## Design philosophy (Read only)

規範本文はこの command に格納しない。着手前に `skills/writing-knowledge` 判定表の DesignDoc 行 (`guidelines/writing/design-doc-protocol.md` 「spec 型 DD」) と `references/design-doc-spec-template.md` を Read する。`--type full` のときだけ `references/design-doc-template.md` (12 節) を使う。repo に Design Doc の template (例: `.claude/docs/design/template.md`) があれば節構成はそちらに従い、spec 型の要素は規範 「repo が DD template を保持するとき」 の位置へ差し込む。

## 逆算の原則と読みやすさ (canonical は規範側)

逆算の 4 原則 (完了の定義から始める / 実装者が迷う点だけ決める / 検証できない仕様は書かない / 後段へ渡せる形にする) と「user が仕様を理解できる文章」の書き方は `design-doc-protocol.md` 「spec 型 DD」 が canonical。この command は手順と gate だけを扱う。

## Input interpretation (ARGUMENTS からの自動分岐)

| Detection | Condition | Effect |
|------|------|------|
| update mode | 「直して / 更新 / 書き直し」+ `.md` path | `--update <path>` 相当。既存の受け入れ条件の文を保ち、差分だけ Edit する |
| derive mode | 「PRD から」「〜を元に」+ PRD `.md` path | `--prd <path>` 相当。PRD の `1.5 decision rationale` (Q1-Q5) は再評価せず転記する (`Source: <PRD path>` を付ける) |
| full mode | `--type full` または「12 節で」「フル版で」 | 12 節 template。spec 節 (受け入れ条件 / 決定事項) は `3.2 Acceptance criteria mapping` に置く |
| new mode | 上記なし | 通常 flow (Step 1 から) |

path があって fix keyword が無いときだけ AskUserQuestion で `--prd` / `--update` を 1 問で確かめる。それ以外は推奨即決で進める (`rules/minimize-questions.md`)。

## Flow

| Step | Action |
|------|------|
| 1. Input identify | `--prd <path>` > topic 引数 > `git log/diff` から推定。対象が特定できないときだけ 1 問 |
| 2. Load guidelines | `skills/writing-knowledge` DesignDoc 行 (`design-doc-protocol.md`) + `references/design-doc-spec-template.md`。`guidelines/writing/long-form-doc.md` は冒頭 Writing Context 節 + 構造ゲート適用節だけ Read する |
| 3. Analyze code | `mcp__serena__*` で既存の振る舞いと影響範囲を確かめる。論点ごとに次を行う: <br>- **先例の数え方**: schema / API / 命名の決定ごとに repo の先例を数える (同じ役割の列名: 無効化は `disabled_at` か flag か、順序は `sort_order` か `display_order` か、識別子の UNIQUE の範囲、sub-resource の一覧を親の応答に同梱するか別 endpoint にするか)。schema dump か migration を grep して「候補 A n 件 / 候補 B m 件」を出し、多数派を既定にする (外れるときだけ決定事項に理由を記載)。先例は規範に無い慣行を取り込むためのもので、多数派が常に正しいわけではない (user の判断で覆せる)。「現状こうなっている」は実物で裏取りし、推測には【要確認】を付ける<br>- **既存 endpoint 拡張時**: 現状の error 応答の形 (validation 違反の HTTP status と body) を Current State に書き、Appendix B で変えるなら「既存挙動の変更」として受け入れ条件 5.1 へ記載する。拡張する usecase を共有する別の入口 (CSV 一括更新 等) を列挙し、新しい制約がそこにも適用されるなら Non-Goals の入口か受け入れ条件に記載する<br>- **DB / endpoint の実在確認**: DB の列と制約 (NOT NULL / UNIQUE / FK) は API の validate から推定せず、schema dump か migration file で確かめる。Implementation Surface へ記載する endpoint は route 定義 (handler の `Route` / `r.GET` 等) で実在を確かめ、無いものは「新規」、1 件取得と一覧のような形の違いは実物の形で書く |
| 3.5. Structure gate と骨子 | draft 前に `PRINCIPLES.md`「文書全体の読みやすさ」を当て、見出しの役割と所有する主張を決める (`long-form-doc.md` 「構造ゲート適用」)。<br>- **骨子の内容**: template の項目ごとの記載する / 記載しない と理由 1 行、各節の主張 1 行、Implementation Surface の合計 (数と新規・既存拡張の別。endpoint は route で確認済みのもの。table は新規 / 列追加の別と一意制約の範囲まで)、受け入れ条件の件数 (PRD 書き戻し / DD の境界)、決定事項の見出しと却下案、Non-Goals、未確定事項と確認先。user の判断が必要な項目にも推奨を記載しておき、問いは投げない。箇条書きと表だけで出し、文体は整えない<br>- **待ち方**: 骨子を 1 画面で chat に出し、user の差分を待ってから本文へ進む (user 指示 2026-09-05: 骨子を決めずに本文から書いた DD は 4 回書き直しになった。問答方式は同日に試して往復が長いため不採用)。user は差分だけ返し、「OK」なら本文に入る<br>- **待てない場合の代替**: user の返答を待てない context (autonomous mode、別 session からの依頼、`--dry` 以外の非対話実行) では推奨のまま本文に進み、骨子と「未確認のまま進んだ」旨を DD 冒頭の注記 (blockquote) に記載して user が後から差分を返せるようにする (2026-09-06 別 session 依頼で待てなかった) |
| 4. 受け入れ条件を先に記載する | Step 3 の結果と入力から、受け入れ条件を表で列挙する (`#` の通し番号は読みやすさのためだけで、本文や後段から引用しない。PRD の条件は PRD の番号で参照し、DD には PRD に無い条件だけを記載する)。ここで user に「この条件で完了とみなしてよいか」を確かめる (最大 1 問、拮抗する条件があるときだけ) |
| 5. 本文を逆算で埋める | spec template で記述する。決定事項では次の 3 論点を毎回検討し、複数案が実際にあったものだけ小見出しで記載し、自明なものは表に 1 行で保持する (4 bullet の小見出しを機械的に増やさない): 他 context の master を参照するか独自に保持するか (Step 3 で bounded-context の lint 設定、例 `.golangci-bounded-context.yml`、を確かめる)、既存 endpoint の拡張か新設か (却下案を 1 つ以上)、1:N の入力を平坦な形式 (CSV / 一括 API) でどう表すか (登録と更新の両方。更新側を対象外にするなら Non-Goals に入口を記載する)。決定を追加する・変えるたびに Implementation Surface へ戻り、その決定で増える endpoint / Read / Write / 画面 / table を表と合計 1 行へ追加する。各節は「どの受け入れ条件を満たすための説明か」を書き手が答えられる状態にし、どの条件にも対応しない節は削る。見出しや決定事項に条件の番号を引用しない。repo の DD template があっても、記載することの無い節は作らない |
| 6. Quality gate | まず `~/.claude/scripts/dd-gate.sh <path>` を実行し、FAIL 0 まで修正する (合計と表の行数、未確定の残存、決定表の cell 長を機械で判定する。WARN は理由を記載して保持してよい)。次に下の **完了判定** を全て満たすまで Edit で修正する (最大 2 loop)。満たせない項目は【要確認: 何を / 誰が決める / いつまで】として「未決事項」に集める |
| 7. Write file | `--out` > repo の 1 つ上の dir を `ls` して既存 DD の置き場 (例: `docs/DesignDocs/<context>/`。既存 DD と同じ context の dir に置く) > repo の 1 つ上の dir の `docs/design/` > `docs/design/` > `design/` > current。file 名は `YYYY-MM-DD_<slug>.md`。repo 配下 `.claude/**` へは書かない。`--dry` は chat 出力のみ |
| 7.5. writing check | `references/writing-check-protocol.md` (対象: design doc file、`--dry` は draft text) |
| 8. Handoff | Next command を 1 行出す: `/spec-plan <path>` |

## 完了判定 (Step 6 の gate = SPEC を作成する前のチェックリスト)

「SPEC を作成する前に、何を作るかが十分に固定できているか」を見る (user 決定 2026-09-05)。全項目を満たしたら Design Doc レビューへ出し、OK なら `/spec-plan` に進む。1 つでも満たさなければ Step 4-5 に戻る。

| # | 項目 | 満たす状態 | 機械で確かめる方法 |
|---|---|---|---|
| 1 | 背景・課題 | なぜこの変更が必要か説明できる (PRD にあれば参照でよい) | — |
| 2 | 目的 | この開発で何を実現したいのか一文で言える。**誰の、どの状況が変わるのかを同じ 1 文に含める**。あわせて「この DD で決める範囲」を 1-2 文で記載し、レビュアーが見るものを最初に掴める | Overview の 1 文目に行為者 (運営 / 出品者 / 購入者 等) と状況が発生している。1 文目と 2 段落目 |
| 3 | 対象範囲 | 何を変更するのか分かる。Implementation Surface に API (種別 Read / Write、新規 / 既存拡張、責務)、必要な Read / Write の能力 (新規 / 既存)、画面 (FE 側の logic の有無)、DB (新規 table / 既存 table の列追加を 5 列表で) が表で整理され、SPEC が PR 単位に分解できる | Implementation Surface の合計 1 行と 5 表 (Current State の直後に置き、endpoint 名と画面名と table 名で記載する。DB 変更が無いときも Data Schema に「DB 変更なし」の 1 行)。**見出し名と 1 列目の header は `references/design-doc-spec-template.md` のとおりに記載する**。`### Backend API` の 1 列目は `endpoint`、`### Frontend` の 1 列目は `画面` で、能力の 2 表は `### Required Read Capabilities` と `### Required Write Capabilities` にする。`dd-gate.sh` はこの見出しと header で表を特定するので、`### API` や `### 画面` のように言い換えると表 0 行と判定される。合計 1 行の各数は表の行を `grep -c` で数えて書く (header 行と区切り行を除く。列名の「新規 / 既存」が hit に含まれる)。**`Read n / Write n` が指すのは Backend API 表の種別列の内訳**で、能力の表の行数は「Read の能力 n」のように別の語で書き、合計 1 行では API の内訳より後ろに並べる (`dd-gate.sh` は最初に現れた `Read n` を採用する)。**Frontend 表の行は変更がある画面だけにし、画面の変更が無いときは表を作らず合計 1 行に「画面 0」と記載する** (Data Schema の「DB 変更なし」と違い、「変更なし」の行を追加すると合計と行数が食い違う)。endpoint の新規 / 既存拡張と形 (1 件取得 / 一覧) が route 定義と一致する |
| 4 | 非対象 | 今回やらないことが分かる。空にしない | Non-Goals が 1 行以上 |
| 5 | 期待する振る舞い | 正常系だけでなく主要な条件分岐 (境界 / 失敗時 / 同時実行 / 再送) も分かる | 各受け入れ条件に境界か失敗時の記述 |
| 6 | Acceptance Criteria | 実装後に「完成した」と客観的に判定できる。「〜のとき、〜が〜になる」の形で、真偽が決まる | 各受け入れ条件に対応する振る舞いの節がある (本文に番号は書かない)。PRD と同じ条件を DD に書き直していない |
| 7 | 外部から見える変更 | API / DB / UI の変更が整理され、変更が無い場合も「変更なし」と分かる | — |
| 8 | 既存仕様との関係 | 何を維持し、何を変えるのか明確 (PRD から変えた点は「PRD と違う点」と明記し、書き戻す) | 「PRD に書き戻す要件」の表 |
| 9 | 重要な設計判断 | 複数案があり得る部分について、どの方向にするか決まっている。却下案と理由がある。未確定事項 (Qn) に依存する決定は「暫定決定」と明記し、Qn と矛盾して見えないようにする | 設計判断の節 |
| 10 | 制約・前提条件 | 後方互換、性能、既存データ、リリース条件が書かれている。切替を伴うなら flag の型 (code 定数型が既定) と有効化 PR、撤去の条件が Release の節にある | 決定事項の「受け入れる制約」列、Release の節 |
| 11 | 実装方法に寄りすぎていない | 関数名、SQL、file 名、処理の置き場、詳細な実装順序を記載していない。「reader に ExistsXXX を追加」「この SQL を使う」「この file を変更」は詳細設計 (`/spec-detail`) 側で、SPEC にも記載しない | - **機械検出方法**: 受け入れ条件 / 振る舞い / 決定事項の節を grep し、backtick / path / `.go` `.vue` / HTTP status の hit が 0<br>- **許可される記載範囲**: Implementation Surface には endpoint 名と画面名と table / column 名 (Data Schema の 5 列表)、Appendix B には field / HTTP status を記載してよい<br>- **禁止対象**: file path / 関数名 / SQL / DDL 全文はどこにも記載しない (「一覧は具体名、判断は抽象」が team の慣習。2026-09-05) |
| 12 | Design Doc だけで SPEC を書き始められる | 「結局何を作るんだっけ」を追加確認しなくても作業計画に落とせる。未決事項は推奨を暫定決定として決定事項に置き、Open Questions の表は「暫定決定 / 再レビューの条件 / 確認先」だけを保持する。再レビューの条件の正本は Open Questions の表で、決定側には「暫定決定 (Qn)」と記載するだけにする (2 か所に記載すると片方だけ修正する) | `/spec-plan` Step 1 の入口判定 |
| 13 | 実装者が変わっても完成形がズレない | 人によって違うものを作る余地が小さい (判定に使う集合、主語と対象、決定の組み合わせが明記されている) | 用語節に集合の内外、各文に行為者と対象 |

一番重要なのは 11 〜 13 の 3 つ。良い状態は「何を作れば正解かは決まっている。どう作るかは SPEC で決められる」、弱い状態は「SPEC を書こうとすると要件や完成条件を考え直さないといけない」。

補助の判定 (上の表に含まれる細則):

- 「決定事項」に実装の書き方 (層 / 関数名 / 処理の置き場 / 共用の仕方) が混在していない (#11)
- 決定事項どうし、決定事項と受け入れ条件の組み合わせで結果が決まらない場面 (記録を消す × 再送、旧形式と新形式が両方来る) が無い (#13)
- 決定 n の本文に発生する名詞 (endpoint / flag / 一覧 / 別 table / master / 列) が Implementation Surface の表と Data Schema の table 一覧に記載されている。決定だけにあって表に無い endpoint や flag が無い。「master にする」と記載して表では固定値の列、のような食い違いが無い (#13。2026-09-06 実踏)
- 既存の制約 (UNIQUE / FK / NOT NULL / CHECK / 排他制御) を削除または緩める変更では、Data Schema に「不変条件の担い手」の 4 列表があり、Review Points に「同等のガードはあるか / なぜ付けていたか / どの操作で成り立たなくなるか」への答えが各 1 行である (#5 / #10。2026-09-10 に表が無く EM の 1 問の説明に 2 時間かかった)
- 「参考にした既存実装」が 1 つ以上ある (#12)
- 「初回でやらないこと」に「後から追加するとき」の入口がある (#4)
- 「未確定事項」に番号と「決める時点 / 確認先」がある (#12)
- PRD に書かれている本文を繰り返していない (#8)
- 同じ内容が 2 つの節にない。振る舞いの節が受け入れ条件の表の言い直し、設計判断の節が決定事項の却下案の再掲、用語表が PRD の複製、になっていれば片方を消す。判定は節単位でなく概念単位で行い、1 つの概念 (例: サイズカテゴリー) の説明が本文 3 か所以上にあれば Glossary か決定の 1 か所に集約し、他は参照だけにする
- 暫定決定に置くのは、書き手が code や出典を読んでも決められない問い (確認先が運営 / 他 team / PRD author) だけ。既存の仕組みで扱えるかのような code を読めば決まる問いは Step 3 で決めて本決定にする (2026-09-06 に運用フラグで扱えるかを「開発が確認」として先送りした)
- 決定表の cell が 2 行を超えていない (超えるなら bullet に戻す)
- 図は順序か分岐がある箇所だけにあり、label に `<br/>` が無い

## Options

| Option | Description |
|-----------|------|
| `--prd <path>` | PRD md から導出する (Q1-Q5 は転記) |
| `--update <path>` | 既存 md を更新する (受け入れ条件の文を保ち差分だけ Edit) |
| `--out <path>` | 出力先 dir |
| `--type <spec\|full>` | 既定は `spec`。`full` は 12 節 template (`references/design-doc-template.md`) |
| `--dry` | file を書かず chat に出す |

## Common guards

- Secret-free (`~/.claude/rules/enterprise-security.md`)。個人ローカル path を記載しない (`rules/no-local-path-in-shared-docs.md`)
- code 例は 5 行以内。1 file 1 H1。Mermaid は ``` mermaid code block
- 経過メモ (「当初 X で考えたが」) と時限マーカー (「この PR で」「先週」) を記載しない

## Bad Design Doc

受け入れ条件が無い / 「適切に処理する」で逃げる / 決定事項が実装の書き方になっている / 振る舞いが識別子の羅列で user に読めない → 実装の入力にならず、全て NG。

ARGUMENTS: $ARGUMENTS
