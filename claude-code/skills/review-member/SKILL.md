---
allowed-tools: Read, Grep, Glob, Bash
name: review-member
description: team メンバーの過去 PR review 傾向を lens として当てる pre-PR self-review。「レビュアー観点で見て」「member レビューで」「/review-member」で起動。read-only。
---

# review-member

自分の PR に付いた過去の human review コメントから抽出した「team 固有の指摘傾向」を lens として当て、PR 提出前に同じ指摘が付きそうな箇所を先に炙り出す。読み取り専用で修正はしない。

## When to use

| skill / command | 用途 |
|---|---|
| `/review-member` (この skill) | team 固有の指摘傾向を lens として当てる pre-PR self-check |
| `/review` | 汎用的な自作コード review (内部で `comprehensive-review` skill の多観点 review 本体を実行、直接呼ばない) |

review 系を重ねる場合は `/review-member` → 修正済みの差分に対して `/review` の順で実行すると重複が減る。

## Input

以下の優先順で対象を決める。1. 引数の file path / glob 2. 引数の `PR #<number>` / PR URL → `gh pr diff <n>` で diff 取得 3. staged diff (`git diff --cached`、空でなければ) 4. 上記全て非該当なら「対象を指定して」と縮退して終わる (推測で全 file を走査しない)。対象が 50 file 超のときも「対象が大きすぎる。file か directory を限定して」と縮退する。

## Lens (33 観点)

lens 定義本体と照合手順の詳細は **lens data dir** の `detail.md` (canonical) にある。dir は `$CLAUDE_REVIEW_MEMBER_DATA_DIR` (既定 `~/.claude/references-private/review-member/`) で、team の実 review から抽出した内容を格納するため repo には置かない。Flow Step 2 の前に同 file を Read する。base data 更新履歴は同 dir の `lens-history.md` に分離してあり、照合実行では Read しない (lens の追加 / 削除を検討するときだけ読む)。**dir が無ければ lens 照合は行わず、「lens data 未設定のため team 傾向の照合を skip した」と 1 行報告して汎用の self-review だけで閉じる**。lens は「team のレビュー傾向」で絶対 rule ではなく、ケースごとに例外を許容する。

## Flow

Step 1. Input 判定 (上記 `## Input`) で対象 file list を確定する。

Step 2. lens data dir の `detail.md` を Read し、対象 file に 33 lens を順に heuristic 照合する。静的 pattern は Grep / Bash で 1 pass 取得し、意味 review が必要なものは Read で本文を見て判断する。file 種別ごとに当てる lens を限定する rule は `## Noise discard` の「対象が 〜 のみのとき」の bullet にある (test / migration / Vue)。

Step 2.5. **差分外 routine** を必ず当てる。ベテランの review 187 件を分類した調査では 69% が差分外の file を 1 枚開いた結果で、33% は「今は壊れていない」劣化防止の指摘だった (出典は lens data dir の `lens-history.md` 2026-08-30)。差分だけで出せるものから順に、次の 7 件を lens とは別に 1 pass 実行する。

| routine | 動作 | 対応 lens |
|---|---|---|
| 根拠の保存 | diff 内のリテラル値 (閾値 / timeout / retry 回数 / page 上限) に「どこに記載してあるか」を問う。Go 以外 (`*.mjs` / `*.ts`) の定数も対象。`git log -S <値>` で履歴側の根拠を先に出す | 2 |
| 対の非対称 | 対の相手 (一覧/詳細、合計/明細、追加/削除) を名前で挙げ、相手側 file を開く | 31 |
| 二重定義 | 新定数 / 新 helper を値と名前で grep する | 22 |
| dead code | 参照数と guard 条件の出所を確認する | 16 |
| silent failure | catch 到達条件と HTTP client の error 設定を実物で見る | 12 |
| 配置の慣習 | 手順詳細: `references/on-demand-rules/review-member-routines.md` | 1 / 9 / 17 / 20 |
| 変更波及 | 手順詳細: 同上 file | 4 / 17 / 22 / 25 / 31 |

Step 3. `## Evidence gate` で各候補に実測根拠を付ける。付けられない候補はここで落とす。

Step 4. `## Noise discard` で候補を濾す (canonical の共通基準にこの skill の追加 rule を重ねる)。判断に迷った候補は保持して confidence を `low` と付記する。

Step 5. Output format で出力し、同じ turn で `~/.claude/scripts/review-member-log.sh append` に run を 1 行記録する (stdin に JSON: `target` = PR 番号か path / `kind` = 事前 (PR 提出前) ・事後 (reviewer 指摘後) ・backtest / `files` = 対象 file 数 / `findings` = 出力した指摘の `{lens, file, line, confidence}` 配列 / `verdict` = 判定行)。落とした候補は記録しない。user が「記録しないで」と言ったときだけ skip する。

出力文は `guidelines/writing/PRINCIPLES.md` の「文章生成の不変条件」に従う。lens の修正 template は候補であり、実際の差分にない理由・影響・repo 慣習を補わない。

## Evidence gate (指摘前の実物照合、必須)

heuristic 一致だけで指摘を出さない。過去運用 (2026-07-24 fact-check) で 7 件中 5 件が実物と照合していない誤指摘だった (godoc 誤読 / test 網羅の見落とし / 既受入済 pattern の蒸し返し / PR body 既記載 / repo 内 0 件の慣行を前提化)。各候補は出力前に以下の照合を通し、通過しないものは落とす。

| 誤指摘 pattern | 照合手順 (指摘前に必須) |
|---|---|
| 「〜が無い」系 (lens 2 godoc 欠落 / lens 13 test 欠落 / lens 16 未使用 / lens 26 test 未網羅) | 対象 file と対応 `_test.go` を Grep して不在を実測する。「無い」は grep 0 件を根拠にし、hit したら候補ごと落とす |
| 「不要」系 (lens 11 private 化 / lens 30 処理削除) | 呼び出し元 / package 外参照を Grep して件数を根拠にする。下流 PR で参照予定のものは落とす (lens 11)。到達しない fallback は呼び出し元の入力値を引用して到達不能を示す。結果に影響しない加工処理は、その出力を読んでいる箇所の grep 0 件を示す。引用も 0 件も出せないなら落とす (lens 30)。grep 件数を根拠にする前に、対象が interface 実装 / framework hook / generated code でないか確認する。該当するなら呼び出しは framework 側にあり grep では数えられないので候補ごと落とす (lens 11 / 16 / 30 共通) |
| 「〜と書いてある」系 (godoc / comment / PR body の内容への指摘。lens 2 の抽象語 / 初出 jargon 未展開 / 語感が実装と食い違う も含む) | 該当行を Read して原文を指摘に引用する。引用できない (= 読み違いの可能性) なら落とす。**この系に「repo 慣習では〜」の慣習チェックを当てない**。慣習チェックが答えるのは「書くのが慣習か」であって「書いてある内容が読めるか」ではない。周囲が無 comment でも、書いた comment の語が読めないことは指摘してよい |
| 「repo 慣習では〜」系 (lens 1 / 7 / 9 / 19 / 20 の慣行前提) | 慣行の実在を Grep で数え、件数を根拠に添える。repo 内 0 件の「慣習」を前提にしない。逆に、Go style guide (initialism) と標準 library の新 API (`sql.Null[T]`) への指摘は、既存 code が旧形式で揃っていても落とさない (2026-08-30 実測: 既存準拠を理由に見送った 5 件が全部 reviewer の指摘だった)。修正案が構造の変更 (別関数化 / helper 抽出 / 分割) を求めるときも同じ照合を修正案側に当て、同 file の既存 case が同じ構造 (loop 内で case ごとに assertion を変える等) を取っていれば、その構造に合わせた修正案へ差し替える (2026-09-05 実踏: 早期 return の case に別関数化を提案し、同 file の既存分岐と逆行した) |
| 既決の蒸し返し | PR 対象なら `gh pr view --comments` で既存 thread を確認する。同 pattern が議論済み / 受け入れ済みなら落とす |

Output の各指摘には根拠 (grep 件数 / 引用行 / thread 参照 / 開いた差分外 file の path のいずれか 1 つ) を必ず付ける。grep 件数は file 数 (`-l`) と行数 (`-n`) を分けて数え、どちらを記載したかを明記する (2026-09-05 実踏: NOT NULL の行 2 件を「2 本」と file 数のように記載した)。

## Output format

```
## review-member 結果

- [lens 名] file:line — 症状。根拠: grep 件数 / 引用行 / thread 参照 / 開いた差分外 file。修正案: 実際の差分に合う対応。
- [lens 名] file:line — 症状。根拠: 同上のいずれか。修正案: 実際の差分に合う対応。
...

## 判定
pass  (該当 0)
```
または
```
needs-fix N 件
```

- lens 名は table の「観点」列 (「命名整合」「godoc / 意図明示」等) を使う
- 症状・根拠・修正案を区別して書く。文数は揃えず、条件や因果を読み違える場合だけ分ける。根拠は `## Evidence gate` で取った実測を示す
- 指摘の合計が 33 件を超えたら「重要度の上位 33 件のみ表示 (全 N 件)」と 1 行添えて truncate する (lens 33 本に合わせた上限)

## Noise discard

canonical: `references/on-demand-rules/review-noise-discard.md`。この skill は finding を数値採点しないため、canonical の confidence 閾値 (80) は使わず、`## Evidence gate` の根拠を示せるかで保持する / 落とすを決める。追加:

- lens 該当 0 の観点行は書かない
- 推測止まりで根拠を示せない指摘や、保険で付ける指摘は落とす
- 既に godoc / comment / PR body で意図が説明されているなら落とす。comment が what (「gender=none → other で代替」のような読み替えの事実) しか書いていないものは「説明済み」に当てず、値の読み替えや条件の非対称の妥当性を問う候補は保持する。test が期待値として固定していることは意図の証拠にはなるが妥当性の根拠にはならないので、それだけを理由に落とさない (2026-08-30 実測: この 2 つを理由に見送った 2 件が両方とも reviewer の指摘だった)。ただし失敗時の既定値 (取得失敗を false / 0 にする等) がビジネス判断に関わる候補は、説明があっても「その判断でよいか」を問う形で保持する (2026-08-30 実測: 明記済みの fallback に reviewer が指摘した)
- 対象が test file のみのとき、lens 2 / 4 / 5 / 8 / 10 / 17 / 19 / 20 / 23 / 29 は原則落とす (production code 向け lens)
- 対象が test file のみのとき、lens 26 は case の pattern 網羅判定のみ当てる。新規 method の test 有無判定は production diff が無いと成立しない
- 対象が test file のみのとき、lens 27 (fixture 配置) は当てる
- 対象が migration file のみのとき、lens 8 / 9 / 17 / 18 / 33 を優先的に当て、他は落とす
- 対象が Vue / frontend のみのとき、lens 1 / 3 / 5 / 6 / 15 / 16 / 22 / 24 / 25 / 28 / 30 / 31 / 32 を優先、他 (Go 向け) は落とす
- lens 30 は「消せる」でなく「消しても壊れない」を根拠にする。この skill は read-only で code を消して test を回せないため、根拠は静的に取れるものに限る (呼び出し元 grep 件数 / 呼び出し元の入力値の引用 / 出力を消費している箇所の grep 0 件)。どれも示せない候補は落とす
- 対象が md doc (DesignDoc 等) のみのとき、code 向け lens を対象外にして pass で終わらせない。以下 7 つを lens 2 / 14 / 22 / 31 の doc 版として当てる (2026-08-30 の blind backtest で human 4 件に対し pass):
  - (a) doc 内の数値 / 一覧を同 doc の表と突き合わせる
  - (b) doc が主張する現状挙動 (「PC は 404」「dialog が発生する」等) を実 code (template / handler) で確かめる
  - (c) 同 dir の同種 doc (同列の integration の DesignDoc 等) と節構成を比べ、片方だけにある節 (csv download / test mode / 共通化の可否) を挙げる
  - (d) 「A か B か」「検討」「TBD」で未決のまま残存する文を挙げる
  - (e) doc が参照する上位 doc / rule (`SKILL.md` の section n、`rules/*.md`) を開き、定義や推奨形式 (build tag / error check の書き方) が食い違う箇所を挙げる
  - (f) 行番号での参照 (`file.go:99`) は path + 関数名に修正する
  - (g) 同じ label (Style A/B 等) を別 doc で別概念に使っていれば注記を求める
- 「実運用では起きない」と説明された防御経路 (retry / fallback / error の握り) は、説明の有無で落とさない。lens 12 で「起きたとき人が気づける口 (log / metric / error 返却) があるか」を 1 度当て、口が無ければ `low` で残し、あれば落とす (2026-09-05 実踏: 1062 を握って 1 秒ずらす経路を、この判定を経ずに確信度だけで low にした)
- lens 26 の「分岐網羅が足りない」は confidence `low` 固定にする (2026-08-30 の blind backtest で 3 PR に 4 件出して human の指摘と一致 0。team は review で分岐網羅を求めない傾向がある)

## Failure Handling

| 状況 | 挙動 |
|---|---|
| 対象未指定 (Input 4 に該当) | 「file / PR / staged diff のいずれかを指定して」と 1 行返して終わる |
| 対象 file 50 超 | 「対象が大きすぎる。file か directory を限定して」と縮退する |
| `gh pr diff` 失敗 | 「PR diff 取得失敗。auth or number を確認」と 1 行返して終わる |
| Read 対象が binary | skip して残りを続ける |

## Notes

- この skill は read-only。修正は user が別途 `/dev` 等で実行する
- 起動時は前提 config file の読込は不要 (`pr-review-digest` と異なり、この skill は lens 定義を lens data dir の `detail.md` に格納する)
- **性能の根拠は `~/.claude/logs/review-member-runs.jsonl` (Step 5 で追記) と、それを複製した lens data dir の `lens-history.md` 「前向き計測台帳」だけ**とする。reviewer の指摘が付いたら 3 分類 (事前に拾えた / lens あり・拾えず / lens 無し) で数え、`review-member-log.sh reconcile <target> --caught N --missed-lens N --no-lens N` で記録する。突き合わせ待ちは `review-member-log.sh pending`、一覧は `list` で出す。reconcile の合計が 10 件たまったら heuristic を修正する
- lens 追加 / 削除は、以下のいずれかの source から頻出 pattern を抽出して、四半期に 1 回程度 review する (更新履歴は lens data dir の `lens-history.md` 参照):
  - 自分の PR に付いた新規 review コメントの傾向 (`pr-review-digest` skill の集約 HTML から取得する)
  - 特定 reviewer が他者 PR に記載した review コメントの傾向 (reviewer 別 + scope 別に集めた review コメントを explore-agent で lens に分類する)
