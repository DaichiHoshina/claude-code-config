# Monitor で外部完了を待つときは DONE-only 出力にする

`Monitor` tool で CI / 外部 job / cron / background bash の完了を待つとき、poll ごとの状態 line (`running:2 fails:0` 等) をそのまま出力すると、60s 間隔でも 30 分の待機で 30 line 積み、user の terminal と context を占有する。

## 原則

- 出力条件は **状態が変わったとき** か **完了 (`in_progress == 0`) に到達したとき**の 2 つに限定する
- 途中の poll は Monitor 内で silent に処理し、chat には出さない
- 完了通知の 1 line は「何が何件通過 / 失敗したか」を最終値で書く。途中経過の再掲はしない

## 書き方 (bash + gh の例)

```bash
# NG (毎 poll で状態を出す)
until [ "$(gh pr checks 12345 --json state -q '[.[]|select(.state=="IN_PROGRESS")]|length')" = "0" ]; do
  gh pr checks 12345
  sleep 60
done

# OK (DONE のときだけ出力)
until state=$(gh pr checks 12345 --json state -q '[.[]|select(.state=="IN_PROGRESS")]|length'); [ "$state" = "0" ]; do
  sleep 60
done
gh pr checks 12345 --json name,conclusion -q '.[]|select(.conclusion!="SUCCESS")|.name' \
  | { fails=$(wc -l | tr -d ' '); echo "DONE fails:$fails"; }
```

`Monitor` tool の filter を書くときは、正規表現で `^DONE` 等の line 頭を明示的に絞る。`running:` を含まないだけの negative filter は、poll ごとに出す別の line が混ざったときに気付けない。

## Why

Monitor の設計は「stdout の 1 line = 通知 1 件」で、chat には全 line が届く。60s ごとの `running:N` は「状態が同じ」報告なので通知価値はゼロで、待機の間ずっと context を消費する。完了時の 1 line だけあれば「今は待つ / 完了した」の 2 状態を区別できる。

CI 完了を inline で待たない (`rules/ci-no-inline-wait.md`) は background 化の指針、この rule は background 化した後の**出力量**の指針。両者は独立している。

## 適用範囲

- Monitor tool の全用例 (CI / job queue / deploy / batch / bats loop 等)
- `Bash run_in_background: true` の完了検知 script も同じ考え方 (poll 内では出さない、完了時に 1 line)

## 参照

- `rules/ci-no-inline-wait.md`
- CLAUDE.md `## Rewind / Context Management`
