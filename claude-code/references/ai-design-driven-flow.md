# AI を使った設計駆動開発フロー (Why)

この file は spec 系 command が**なぜその境界で分かれているか**を説明する。**対象は 3 track のうち大きい開発だけ**で、極小と小さい開発 (`/dev` だけ、または `/prd` → `/plan` → `/dev` or `/flow`) にはこの段階分けを適用しない。各 command の手順は `commands/spec-design.md` / `commands/spec-plan.md` / `commands/spec-detail.md` / `commands/spec-dev.md` が canonical で、ここでは重複させない。遷移条件の一覧は `design-phase-flow.md` にある。

## 中心にある前提

> **AI が動くコードを書けることと、設計として正しいことは別**

AI は与えた範囲を動く形にする能力が高い。一方で「そもそも何を作るべきか」「どこで分けるべきか」の判断は、実装を始める前に人間が決めておかないと、レビュー段階で初めて設計を議論することになる。

このフローの狙いは、AI が生成した設計上の問題を後から直すことではなく、**AI が独自に設計判断しなければならない範囲そのものを小さくする**ことにある。

### 以前の進め方と何が違うか

```
以前: Issue → AI 実装 → コードを読んで PR 分割 → レビューで設計問題が判明
今回: Issue → Design Doc → SPEC → Code Investigation → 詳細設計 → AI 実装 → Review
```

設計・分割・調査が、すべてコード生成より前にある。

## 5 段階と、それぞれが答える問い

| 段階 | 答える問い | 一言で |
|---|---|---|
| Design Doc | 何を作るか、どの設計を採るか | What |
| SPEC | その設計を、どの責務単位・順序で実装するか | How の方針 |
| Code Investigation | 既存コードで、その責務は現在どう実現されているか | 現状把握 |
| 詳細設計 | 調査結果を踏まえ、具体的にどうコードで実現するか | How の具体化 |
| Implementation | 詳細設計に沿って実装する | 実行 |

この 3 段が運用の核心になる。

```
SPEC               「この責務を変える」
  ↓
Code Investigation 「現在、この責務はどこでどう実装されているか」
  ↓
詳細設計           「だから今回は、この method / interface / SQL をこう変える」
```

役割を分けると、SPEC は既存実装に引っ張られずに責務を考え、Code Investigation は現実のコード構造を確かめ、詳細設計が理想と現実を接続する。

## 段階と command の対応

| 段階 | command | 成果物 |
|---|---|---|
| Design Doc | `/spec-design` | `docs/design/<slug>.md` |
| SPEC | `/spec-plan` | 作業計画書 `plans/<issue 番号>/*.md` |
| Code Investigation | `/spec-detail` Step 2 | 調査は内部。独立節は成果物に置かない |
| 詳細設計 | `/spec-detail` Step 3 | `<SPEC 名>-phase<n>.md` |
| Implementation | `/spec-dev` | code |

Code Investigation と詳細設計は 1 つの command に入っているが、Step として分かれている。調査の段階で実装方法を決めないためで、同じ Step にすると調査が不十分なまま方針が確定する。

## 境界がそこにある理由

### Design Doc に関数名・SQL・file 名を記載しない

実装のなかで自然に決まる詳細を書き込むと、レビュー対象が大きくなり、本当に議論すべき設計判断に集中できなくなる。Design Doc の目的は実装前にチームが方向性で合意することにある。

規模は Implementation Surface の表に endpoint 名・画面名・table 名を列挙し、その**行数として結果的に現れる**。本文で規模そのものを論じない。この使い分けが「一覧は具体名、判断は抽象」という team の慣習にあたる (`commands/spec-design.md` 完了判定 #11)。

### SPEC に method 名・SQL・シグネチャを記載しない

SPEC は着手前に全 Phase 分が 1 file へ集まる。実装形まで書くと、着手しない Phase の method 名と SQL まで読むことになる。SPEC は「どの責務を、どの単位・順序で」の地図に保つ。

ただし**行数を減らす効果は小さい**と実測した。540 行の SPEC のうち実装形にあたる「タスク」節は 44 行 (8%) だった (2026-09-17)。行数の大半は同じ Phase を「実装計画」と「PR分割計画」の 2 節に分けて書いた分だが、これも削減できる量ではない。7 Phase の SPEC で重複を解消したところ 616 行 → 624 行になり、本体が別の節へ移動しただけだった (2026-09-17 実測)。分離の本来の効果は、次の 2 つになる。

1. 着手する Phase 以外の実装形を読まずに済む
2. 上流で実装構造を決め打ちしない。SPEC が既存の method 名に紐付くと、Code Investigation の前に構造が確定し、調査結果と食い違ったときに上流の文書ごと書き直すことになる

だから SPEC は責務までで止める。

### 実装形を詳細設計まで遅らせる

interface や SQL 方針は、既存コードとその依存関係を確かめないと妥当な判断ができない。上流で決め打ちすると「既存の別 method と衝突する」「TX 境界を越えてしまう」が実装時に判明する。

着手する Phase の分だけ、着手する直前に決めるのが最も手戻りが少ない。

### Code Investigation を独立した Step にする

暗黙の作業のままだと 2 つの問題が発生する。1 つは調査が不十分なまま詳細設計が確定し、実装時に食い違いが判明すること。もう 1 つは AI に調査と設計を同時にやらせて、AI が判断を先取りすることになる。

Step として分けると、**AI に調査だけを任せ、設計判断は人間が引き受ける**役割分担がはっきりする。

## AI と人間の役割分担

| 段階 | 主導 |
|---|---|
| Design Doc | 人間が決める |
| SPEC | 人間 + AI |
| Code Investigation | AI を積極的に利用する。ただし**調査結果の責任は実装担当者が担う** |
| 詳細設計 | 人間 + AI |
| Implementation | AI |
| Review | 人間 |

Code Investigation で AI が返した method 一覧や件数を、そのまま事実として採用しない。人間が確認してから成果物として確定させる。「AI が調べたから正しい」ではなく「実装担当者が調査結果を保証する」という形にする。

## 実装単位と PR の関係

**1 Phase = 1 PR** とするが、Phase 自体を「単独でレビューできる変更単位」として切る。分割の優先順位と 400 行の上限は `commands/spec-plan.md` Step 3 が canonical で、PR を細かく分けすぎてレビューが滞ることを避ける判断もそこに含まれる。

## コード生成後のレビューだけに頼らない理由

AI 生成コードを設計観点から評価する考え方は、このフローでも重要になる。評価の観点は次の 4 つになる。

- 責務が適切に分離されているか
- 変更容易性が保たれているか
- 依存関係が不自然になっていないか
- コードの意図を説明できるか

Implementation の後も、責務・凝集度・結合度・依存方向・可読性・テスト容易性は Code Review で確認する。

このフローが追加するのは、その考え方を**コード生成前の工程まで広げる**点にある。

```
コード生成後だけを確認する場合:
  AI 生成コード → 設計観点でレビュー → 問題を発見 → 再設計

このフロー:
  人間が設計判断 → AI が既存コードを調査 → 人間が実装方法を決める
    → AI が実装 → 人間が設計観点でレビュー
```

違いは設計判断をいつ行うかにある。Code Review を「初めて設計を考える場所」にしない、という一点に集約される。コードレベルの設計判断が Code Review へ集中しないよう、設計工程をコード生成より前へ広げたものと位置づける。

## 大きい開発の内側で、どこまで省略できるか

3 track のどれに入るかは `design-phase-flow.md` 「Route selection (3 track)」が決める。この節が決めるのは、大きい開発に入った後で 4 つの成果物のうちどれを作成するかになる。

判定は責務ベースで行う。PR 本数を基準にすると「SPEC を作成する → PR を分ける」ではなく「PR を分けることが先に決まっている → SPEC を作成する」という逆転が起きる。

| 条件 | 書くもの |
|---|---|
| 影響が既存 API / DB / 外部連携に及ぶ | Design Doc |
| 実装単位が複数ある、または実装順序・依存関係の整理が必要 | SPEC |
| 既存コードの実装場所や依存関係が不明 | Code Investigation |
| interface / SQL / TX 境界 / 排他制御で実装時に迷う | 詳細設計 |
| どれにも当たらない | 大きい開発ではない。`design-phase-flow.md` で track を選び直す |

省略したときは、PR 本文に省略の理由を 1 行記載する。各 command 側の省略条件は `commands/spec-detail.md` Step 0 と `design-phase-flow.md` 「Route selection (3 track)」が canonical。

## 実例: 物理削除を論理削除へ変更する

同じ変更が段階ごとにどの粒度になるかを比べる。

| 段階 | 記述 |
|---|---|
| Design Doc | 記事削除を物理削除から論理削除へ変更する。通常 Read では論理削除済みを除外する。削除日時を保持する |
| SPEC (Phase) | 記事の Read 責務を「有効なレコードのみ」に切り替える。完了条件: 論理削除済みが一覧 / 詳細 API から取得されない |
| Code Investigation | 現在地は finder.go / list.go と article_query 配下の JOIN クエリ。呼び出し元は Usecase 12 箇所。COUNT クエリと Search 側にも参照がある |
| 詳細設計 | 既存 interface は変更せず内部実装に条件を追加する。全 SELECT に `deleted_at IS NULL` を AND で加え、JOIN 経由は articles alias 側に付ける。COUNT も同条件。TX 変更なし |
| Implementation | 上記に沿って実装し、完了条件の test を実行する |

Design Doc に `deleted_at` の型や `IS NULL` 判定を記載しない理由は、設計判断としては「論理削除を採用する / 削除日時を保持する」で足りるところにある。カラムの型は詳細設計の議題になる。ただし**データモデル自体が設計判断になる場合** (履歴テーブルを分離する、イベントソーシングを採用する等) は Design Doc で決める。

SPEC に「finder.go の FindByID を変更する」と記載しない理由は、対象 method の一覧が Code Investigation で初めて確定するところにある。SPEC 段階で記載すると、調査で対象が変わるたびに SPEC を修正することになる。

## 関連

- `design-phase-flow.md` — 遷移条件と 3 track の選択 (track 判定の canonical)
- `commands/spec-plan.md` Step 3 — 分割の優先順位 (canonical)
- `commands/spec-detail.md` — Code Investigation と詳細設計の手順 (canonical)
- `guidelines/common/spec-driven-development.md` — 外部 SDD ツール (Spec Kit / Kiro / cc-sdd) の調査と失敗パターン
- `on-demand-rules/spec-flow-episodes.md` — spec 系の実踏エピソード
