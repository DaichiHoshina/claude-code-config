---
allowed-tools: Read, Glob, Grep, Edit, Bash, mcp__serena__*
description: 全 Phase 実装後に Design Doc と作業計画書が求めるものを現在の code と照合し、差を 4 分類して収束 Phase を作業計画書末尾へ追記する
argument-hint: "<作業計画書 path> [--dd <Design Doc path>] [--dry]"
---

# /sdd-converge - 設計と実装の差を収束させる

> **Goal**: 全 Phase を実装した後に 1 回だけ発火し、Design Doc と作業計画書が求めるものと現在の code の差を 4 分類で一覧にする。差が埋まる収束 Phase を作業計画書の末尾へ追記し、実装はしない。

**Position**: `/sdd-implement` で全 Phase を実装した後、最後の PR を作成する前。**既定の chain には入れない** (発火の実測が無いため)。差を確かめたいときに user が発火させる

## When to use (棲み分け)

| Command | Use |
|---|---|
| `/sdd-converge <path>` | 全 Phase 実装後に、設計が求めるものと code 全体の差を一覧にする (この command) |
| `/review` | diff 1 本の品質を判定する。設計との照合は範囲外 |
| `/verify-once` | 変更が動くことを 1 回確かめる |
| `/sdd-implement <path> --phase <n>` | Phase 1 つの実装。判定の相手はその Phase の完了条件だけ |

**git diff でなく現在の code を読む**。Phase ごとの diff は各 Phase の完了条件が既に判定しているので、この command が照合するのは「全部 merge した後の code が設計と一致しているか」になる。

## Step 1: 入力の特定

1. 引数の path を作業計画書として Read する。無ければ同 session で `/sdd-plan` か `/sdd-implement` が最後に扱った path を採用し、それも無ければ 1 問で聞く
2. Design Doc は `--dd` > 作業計画書の「Design Doc」欄に記載された path > 作業計画書と同じ dir の DD の順で特定する。DD の無い作業計画書 (1 文の要件から作成したもの) では作業計画書の完了条件だけを照合の相手にし、その旨を出力の冒頭に 1 行記載する
3. 全 Phase の実装が終わっているかを、作業計画書の PR 見出しと各 PR の branch の実在で確かめる。未実装の Phase があれば照合に入らず、その Phase 番号を 1 行報告して止める

## Step 2: 求めるものを一覧にする

照合の左辺を 3 つの source から作る。

| Source | 取る対象 |
|---|---|
| Design Doc | 受け入れ条件の表の全行、決定事項の各決定、Non-Goals |
| 作業計画書 | 各 Phase の 完了条件 と 対象外 |
| repo 規範 | `~/.claude/scripts/resolve-repo-rules.sh <対象 file>...` が返す rule |

- 条件は言い換えず原文のまま引用する (引用が変われば、読み手が期待値を取り違える)
- Non-Goals と 対象外 は `unrequested` の判定基準になるので、左辺から削除しない
- **repo 規範は非交渉の条件として扱う**。Design Doc の決定と食い違っても規範の側を採り、食い違い自体を `contradicts` に立てる。`resolve-repo-rules.sh` が exit 3 (manifest 未宣言) を返す repo では、この source を左辺に加えず「repo 規範なし」と 1 行記載する
- 左辺の件数を先に数えて宣言する。以降の照合は 1 件ずつ行い、件数と照合した数を一致させる

## Step 3: 現在の code を読む

- 左辺の 1 件ごとに、それを満たす code の位置を Serena `find_symbol` と grep で特定する。特定した位置が production の呼び出し経路から到達するかまで確かめる (到達しない code は、実在しても条件を満たさない)
- 読む範囲は作業計画書の `影響範囲` の Change Map の表にある層とする。表に無い層へ広げるときは、広げた理由を 1 行記載する
- test の実在だけで満たしたと判定しない。条件を確かめる test の無いものは `partial` とする

## Step 4: 4 分類で照合する

| 分類 | 判定 | 行き先 |
|---|---|---|
| `missing` | 左辺の条件に対応する code が無い | 収束 Phase の作業にする |
| `partial` | code はあるが条件を満たし切らない (分岐の片側だけ、test が無い 等) | 収束 Phase の作業にする |
| `contradicts` | code の挙動が条件と矛盾する。repo 規範に反する実装もこの分類とする | 収束 Phase の作業にし、どちらが正かを user に確認する |
| `unrequested` | 左辺に無いものが作られている (Non-Goals と 対象外 に当たるものを含む) | 撤去するか PR 本文に理由を記載するかの判断を作業にする |

- **`unrequested` で code を削除しない**。判断の材料 (追加された symbol、その参照件数、どの Phase で入ったか) を並べ、決めるのは user とする
- 分類の付かない差を `partial` へ寄せない。判定できない理由を 1 行添えて別に列挙する
- 0 件の分類も「0 件」と記載する。記載が無いと、照合しなかったのか差が無かったのかを後から区別できない

## Step 5: 収束 Phase を組み立てる

追記する Phase は作業計画書の既存 Phase と同じ形にする。`spec-gate.sh` が全 PR 見出しの本文に「想定変更行数」と `branch:` を要求するので、この 2 つを欠かさない。

- 見出しは `### PR #<最後の番号 + 1>: 設計との差を収束させる`
- 直下の箇条書きに `依存:` `branch:` `既存挙動:` `想定変更行数:` の 4 行を置く
- **file 名と symbol 名を含む finding は `**完了条件**` の配下に置く**。`spec-gate.sh` の impl-form 判定が対象外にするのは `完了条件` の配下だけで、他の節に `Foo()` 形式の識別子や `path.go:123` を記載すると FAIL になる
- 想定変更行数が 400 を超えたら、収束 Phase を分類ごとに 2 本へ分ける

## Step 6: 作業計画書へ追記する

- 追記するのは作業計画書末尾の収束 Phase だけとする。Design Doc と code と既存 Phase を編集しない
- **差が 0 件なら作業計画書を 1 byte も変えない**。「差 0 件」を chat へ 1 行記載して閉じる
- 追記した後に `~/.claude/scripts/spec-gate.sh <作業計画書 path>` を実行し、FAIL 0 を確かめる。FAIL が返ったら、指摘された行を追記した節の側で書き換えてから閉じる
- `--dry` は追記せず chat へ出力する

## Step 7: Next command

差の件数で分岐する。

| 状態 | Next |
|---|---|
| 差 0 件 | `/git-push --pr` (最後の PR へ) |
| `missing` / `partial` / `contradicts` がある | `/sdd-implement <作業計画書 path> --phase <収束 Phase の番号>` |
| `unrequested` だけ | user が撤去か記載かを決めてから上のいずれかへ |

## Guard

- code を編集しない。収束 Phase の実装は `/sdd-implement` が担う
- Design Doc と既存 Phase を編集しない。設計側の不足は `/sdd-design --update`、Phase の切り方は `/sdd-plan --update` へ戻す
- 差が 0 件のときに作業計画書を編集しない
- git diff を照合の材料にしない (Phase ごとの diff は各 Phase の完了条件が判定している)
- 全 Phase の実装が終わる前に発火しない
- `unrequested` を理由に code を削除しない

## Related

- `commands/sdd-plan.md` — 収束 Phase を追記する作業計画書を作成する
- `commands/sdd-implement.md` — 収束 Phase を実装する
- `commands/sdd-design.md` 「完了判定」 — 左辺になる受け入れ条件の書かれ方
- `references/design-phase-flow.md` — 遷移全体と 3 track の判定
