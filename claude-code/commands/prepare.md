---
allowed-tools: Read, Glob, Grep, Bash, WebFetch, mcp__serena__*
description: Design Doc の前に issue / PRD / 関連 doc を読み込み、task の全体像 (目的 / 要求 / 現状 / 影響範囲 / 未確定点) を chat に整理する (read-only)
argument-hint: "<issue URL・番号 | PRD path | 要件 text> [--related <path|URL> ...] [--as-of <YYYY-MM-DD>] [--out <path>]"
---

# /prepare - task の全体像を整理する (read-only)

> **Goal**: 設計を作成する前に、依頼の出典 (issue / PRD / Slack 転記 / 関連 PR) を集めて読み、「誰が何を求めていて、今の code はどうなっていて、何が決まっていないか」を 1 画面で言える状態にする。設計も実装もしない。

**Position**: **`/prepare`** (全体像) → `/prd` (要件) または `/design-doc` (仕様) → `/spec-plan` → `/spec-dev`

## When to use (棲み分け)

| Command | Use |
|---|---|
| `/prepare` | 出典が複数 (issue + PRD + Slack 等) に散っていて、設計前に全体像をそろえたい |
| `/brainstorm` | 何を作るか自体が決まっておらず、対話で発散させたい |
| `/prd` | 要件を 11 persona で点検して PRD にまとめる (`/prepare` の出力を入力にできる) |
| `/design-doc` | 要件が揃っていて仕様を作成する |
| `/workflow understand` | code の subsystem 構造 (entry / 依存 / data flow) を map にする。要求の理解ではない |
| `/grill` | 設計案がある状態で前提の不足を指摘する |

「全体像把握して」「issue 読んで整理して」「タスク理解して」で発火する。出典が 1 つで数十行ならこの command を使わず、`/design-doc <path>` に直接渡す。

## Step 1: 出典を集める

| 入力 | 取り方 |
|---|---|
| issue URL / 番号 | `gh issue view <n> --json title,body,labels,comments,milestone` で本文と comment を全部読む。`--as-of <日付>` があれば `createdAt` がその日付より後の comment は読まない (実装前の断面で spec 系 command を再テストするとき、後日の実装 comment が答えを先に見せる。2026-09-06)。本文と comment に登場する他の issue / PR / URL は 1 段だけ開く (開いた先の link はさらに開かない) |
| issue の転記 (md / text) | issue 本文と comment を転記した file。`gh` で取れない (別 tracker / 権限なし) ときに使い、発言者と日付を保つ |
| PRD / md path | Read する。500 行超は見出し一覧を取り、目的 / scope / 要件 / 非機能 / 未決事項 の節だけ読む |
| 要件 text (Slack 転記等) | そのまま出典に置く。発言者と日付があれば保持する |
| `--related` | 追加の path / URL。URL は WebFetch で本文を取る |
| 関連 PR | `gh pr list --search "<issue 番号 or 機能名>" --state all --limit 10` で既存の着手を探す。`--as-of` があれば search に `created:<<日付>` を追加し、断面より後の PR は候補にしない。hit は title だけで関連と決めず、本文を開いて無関係なら「無関係 (理由)」と書く |

読めなかった出典 (権限 / 404 / MCP 未接続 / 番号が解決できない) は「未読」として Output の「読んだ資料」に理由付きで記録する。読めた前提で書かない。

## Step 2: code で裏取りする

出典に登場する名詞 (画面 / API / table / batch / 設定名) を Serena `find_symbol` / grep で引き、実在するか、今どう振る舞うかを確かめる。出典の記述と実物が食い違う点は「現状」に「出典では A、code では B」と並べて記載する。確かめられなかった点には【未確認】を付ける (`rules/thinking-principles.md` Section 1)。

- 「〜が無い」「〜は未対応」と書く前に、対象 file の該当 key を全文 grep して hit を開く。冒頭や見出しだけを読んで「無い」と書かない (2026-09-05 の試行で辞書の `置換候補` key を見落とした)
- 「大半」「多くの」「ほとんど」のような量の断定は、対象の要素を数えて (`grep -c` / `wc -l`) 「N 件中 M 件」の形で書く。数えられない量は書かない
- 出典が置く前提 (「辞書に候補がある」等) が実物で成り立たなかったときは、その前提に依存する `R-n` に「前提要確認」を付け、「未確定点」の先頭に置く。設計に進む前に依頼元へ戻す判断は Next の判定表に従う

## Step 3: 整理する

- 要求は出典ごとに拾い、`R-n` の ID を振る。1 要求 = 1 文で「〜のとき、〜が〜になる」に寄せ、出典 (issue 番号 / PRD 節 / 発言者) を括弧で添える。`R-n` は `/prd` の `AC-n` と `/design-doc` の受け入れ条件の「由来」列から参照できる
- 複数の出典で同じ要求が違う言い方をされていたら 1 つにまとめ、食い違っていたら両方を保持して「未確定点」に上げる。同じ人の発言どうしなら新しい方を推奨にし、別の人どうしなら依頼元 (起票者 / PRD author) の発言を推奨にする。日付の無い出典は新旧比較の根拠にせず、「日付不明」と記載したうえで日付のある発言を推奨にする。推奨は断定でなく「推奨」欄に記載する
- 未確定点には推奨を 1 つずつ添える (`rules/minimize-questions.md`)。AskUserQuestion は使わず、chat の表で user が差分だけ返せる形にする
- 制約 (期限 / 非機能 / やらないと決まっていること) は要求と分けて書く
- 出典が Design Doc を書ける状態かを 3 条件で判定し、「設計可否」に条件ごとの合否を記載する。(1) 必須 (Must) の `R-n` に実現可否が未確認のものが無い (2) 出典の未決事項が空か、設計に影響しない項目だけである (3) 受け入れ条件が試験項目に落とせる粒度で記述されている。1 つでも不合格なら Next は「戻す」になる (PRD が Must にした要件を DD が Non-Goal にして review で決着させた例が 2026-06 にあり、決着を PRD へ書き戻さなかったため次に読む人が同じ食い違いに当たった)

## Output format (見出しを固定する)

```markdown
# Prepare: [task 名]

## 一言でいうと
[誰の何のための変更かを 1-2 文]

## 依頼元と背景
[issue 起票者 / PRD author / 発端の出来事。無ければ「不明」]

## 要求一覧
- R-1: [〜のとき、〜が〜になる] (出典)
- R-2: ...

## 現状 (code から)
- [関係する module / API / table の今の振る舞い。出典との食い違いはここに並べる]

## 影響範囲
- file / service / 他 team / 外部 API / migration の有無

## 制約
- 期限 / 非機能 / やらないこと

## 未確定点
| 点 | 影響 | 推奨 |
|---|---|---|

## 読んだ資料 / 未読の資料
- 読んだ: ...
- 未読: ... (理由)

## 設計可否
| 条件 | 合否 | 根拠 |
|---|---|---|
| 必須要件の実現可否が全て確認済み | | |
| 未決事項が空か設計に影響しない | | |
| 受け入れ条件が試験項目に落とせる | | |

## Next
[下の判定表から 1 行]
```

### Next の判定

| 状態 | Next |
|---|---|
| 要求が散っていて優先度や対象外が決まっていない | `/prd <task 名>` (本出力を入力にする) |
| 要求はそろい、仕様を作成する段 | `/design-doc <task 名>` (`R-n` を受け入れ条件の由来にする) |
| 1 file / 数十行で設計が不要 | `/dev <task>` |
| 要求そのものが揺れている | `/brainstorm` |
| 「前提要確認」の `R-n` がある、または設計可否に不合格がある | 設計に進まず、未確定点を依頼元に戻す (下記「前提要確認ケースの扱い」参照) |

### 前提要確認ケースの扱い

- issue comment の文案を chat に出す (投稿は user が行う)
- 戻すコメントを投稿した後に限り、該当 `R-n` を Non-Goal に仮置きした `/design-doc` の draft と並走してよい
- 仮置きは DD の Non-Goals に「依頼元の確認待ち」と明記する
- 決着したら PRD 側にも書き戻す

## Step 4: 自己点検 (出力前)

次を 1 つでも満たさなければ Step 1-3 に戻る。

- 全 `R-n` に出典が付いている
- 「現状」の各 bullet が実物 (file:line / command 出力) に裏付けられているか【未確認】が付いている
- 未確定点の各行に推奨がある
- 読めなかった出典が「未読」に理由付きで並んでいる
- 設計可否の 3 行全てに合否と根拠がある
- Next が判定表の 1 行に対応している

## Step 5: 出力

chat に出す。`--out <path>` のときだけ同じ内容を md に Write する (repo 配下 `.claude/**` へは記載しない)。保存先の既定は無く、`/design-doc --prd` に渡すときは `--out` で PRD 相当の md を保持する。

## Guard

- 設計判断 (採用案 / 却下案) を記載しない。書きたくなったら「未確定点」に問いとして置く
- 出典に無い要求を補わない。補うべきと感じた点は「未確定点」に推奨として書く
- 出典が 20 件を超えたら、全部読む前に一覧を出して範囲を 1 問で限定する
- file 編集 / 投稿 / memory 保存をしない (`--out` の md 1 file だけが例外)

## Related

- `references/design-phase-flow.md` — 設計フェーズ全体の遷移
- `commands/prd.md` / `commands/design-doc.md` — この command の出口
- `commands/explain.md` — 同じ read-only 説明系 (対象が実装のとき)
