# bats 使用時の注意点 (test の作成・実行・fail の切り分け)

## 書くとき

- lib が `BATS_TEST_FILENAME` 等で副作用 (log 書込み・外部送信) を skip する設計なら、test で同じ副作用を assert しない。構造上、常に fail する。新規 test の前に対象 lib を `grep BATS_` で確認し、検証は戻り値・stdout・引数に切り替える。手動 bash で pass し bats 経由で fail するなら、この skip を疑う。lib に skip を追加するときは header に 1 行明記する
- 共通 helper に `setup()` / `teardown()` を置いても part file から実行されない。helper は `_<name>_setup` 関数を提供し、各 part の `setup()` から呼ぶ。分割が正しく済んだかの確認は「元の @test 件数 = part 合計」と「ok 件数が分割前と同じ」の 2 つ

## 実行するとき

- `scripts/bats-run-locked.sh` は第 1 引数しか受け取らず、2 個目以降の file を通知なく無視して exit 0 を返す。複数 file の逆引き実行は `bats <file1> <file2>` を直接使う。GNU `parallel` が無いので `--jobs` は付けない。実行後は plan 行と ok 件数が、渡した file 数と合うか数える

## fail を切り分けるとき

- fail は `tail` で切らず全数を列挙する。bats を pipe に通すと exit code が末尾 command のものになるので、出力を file に保存して `grep -cE "^not ok"` で数える
- 既存 fail か変更起因かは、変更前 commit の一時 worktree (`git worktree add --detach`) で同じ test を実行して判定する。「以前 pass / 今 fail」が説明できなければ bats 自体の更新を疑う
- 仕様変更の commit 前に、変更した関数名・env 名・文言で `grep -r tests/` し、影響する test を全部更新する
- pin や config の変更前に、変える 1 変数以外を同じ条件にした対照実験を 1 回行う (2026-07-29 に bats 1.13 pin を誤診で push し、revert した)
