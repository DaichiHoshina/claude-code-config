# NG 語の登録手順 (user が chat で語を禁止と言ったとき)

user が「X も禁止にして」「X はダメ」「X 使うな」のように語を指定したら、その turn のうちに `guidelines/writing/NG-DICTIONARY.md` へ登録して hook で block できる状態にする。`hooks/lib/prompt-trigger-detectors.sh` の `_inject_ng_word_capture_if_trigger` が発話から候補語を取り出して `~/.claude/logs/ng-candidates.log` に書き、この file を指す additionalContext を注入する。検出が外れた発話 (80 字超、trigger 語なし) でも user の意図が同じならこの手順で登録する。

## 手順

1. **語と活用形を決める**: 動詞は終止形と て / た 形を literal で並べる (`流す / 流した / 流して`)。stem (`引き` `詰め`) は「逆引き」「詰め込み」のような複合語に当たるので登録しない。1 文字で全活用形を拾える語 (`畳`) は 1 文字で登録する。hook は fixed-string の部分一致なので、`〜` などの prefix を付けない (`hook-implementation-pitfalls.md` 注意点 1-A)。活用形が別語の一部になる語 (文末の「だ」が「読んだ」「含んだ」に一致する等) は辞書へ登録せず、構造判定 (`lib/jp-quality/structural-checks.sh` の python 判定) で扱い、`block-checks.sh` の `_struct_block` で block する
2. **辞書内の既存判断と衝突しないか読む**: 追加する語で `NG-DICTIONARY.md` を grep し、(a) 「block 対象外」と名指しされていないか (中間漢語の注記が `担保` 等を対象外にしている) (b) 別の禁止語の言い換えとして推奨されていないか (`安全側` は `倒す` の言い換えとして 2 箇所で勧めている) を確かめる。どちらかに当たったら登録せず、衝突を示して user の判断を仰ぐ。2026-09-08 にこの 2 語が実際に当たり、どちらも見送った。user が登録を選んだときは、衝突する用法だけを除いた形を提示する。2026-09-17 の「書く」がこれで、辞書と PRINCIPLES.md が言い換えを示す定型の「〜と書く」を対象外にし、log や file への出力を指す助詞付きの形 (を書く / に書く / へ書く) だけを登録した
3. **category を採用する**: 比喩 / 擬人化 / 口語の圧縮動詞は `**比喩・擬人化 (block)**` へ追加する。難読漢語や AI 定型語なら既存の該当 category へ追加する。新 category を作るときは `lib/jp-quality/block-checks.sh` の `_inject_keys` / `_block_categories` / `_cq_block_keys` と `scripts/jp-quality-lint.sh` の `_BLOCK_KEYS` にも同じ key を追加する (`term-extraction.sh` の `required_keys` には追加しない。fixture を含まない test が fail-loud になる)
4. **辞書の注記に言い換えを記載する**: 禁止する語ごとに、代わりに使う動作や状態の書き方を 1 つずつ添える (`畳む` → 削除する、`寄せる` → まとめる / 置く / 合わせる)。辞書自身が禁止語を定訳として勧めている行 (`死蔵コード` の例) があれば同時に修正する
5. **fixture と test**: `tests/helpers/jp-quality-check.bash` の fixture へ同じ行を追加し、`tests/unit/lib/jp-quality-check-block.bats` に「語が block される」test と、誤検出を避けたい隣接語 (`逆引き` 等) が hit しない test を追加する。fixture から語を消して test が fail することを確かめてから戻す (mutation check)
6. **既存の使用箇所も全件へ適用する** (user 決定 2026-09-09。それ以前は遡及しない方針だった): 規範 doc (`claude-code/` 配下) と memory (`<repo-root>/memory/`、org memory、`~/.claude/references-private/`) の既存箇所を数え、同じ語を実際の動作や状態を記載した表現へ書き換える。件数が 100 を超えるときは対象 dir で 4 分割して developer-agent へ並列に委ねる。1 か所ずつ文脈を読んでから修正する (同じ語が削除・下げる・書き下す・取りこぼすの 4 意で使われていた実例がある)。触らないのは、他者の発言と投稿済み文章の引用、code block と識別子、定義 file の YAML frontmatter、履歴 doc の過去記録、日本語として成立している複合語 (`窓口` `本番` `使い回す` `補足` `遷移` 等) の 5 つで、見送りは件数と理由を報告する。hook の `_run_ai_jargon_check` は `_is_aitools_path` で早期 return するため ai-tools 配下の書き込みは block されない。既存箇所を修正する目的は、次 session が読む文体の模範を辞書とそろえることにある。developer-agent へ委ねるときは、完了判定に使う grep を親が登録形のまま渡し、「対象は 0 件になった」と報告する前にその出力を添えさせる (2026-09-18 に 1 体が対象範囲を 0 hit と報告したが、親が改めて数えると 31 箇所が残っていた。agent 側の検索条件に一部の活用形しか入っていなかった)、見送りを行単位で判定させる (file 単位の見送りを許すと地の文まで対象から外れる)、変更 file 名で `tests/` を逆引きする bats は親が再実行する (agent の「該当なし」報告で 8 file が hit した)、規範 doc の見出しを書き換えたら旧見出し名で memory 全体を grep して参照を更新する、の 3 つを prompt に記載する (2026-09-09 実踏)
7. **語が全 repo へ波及する処理に含まれる場合だけ修正する**: 実装が出力する文字列を test が assert しているような、語を変えないと契約が食い違う箇所は対象にする。`codex/install.sh` の出力文言と `codex-memory-sync.bats` の assertion がこれに当たる。置換表を loop で perl に渡すとき、`- ` で始まる語句を引数にすると perl が stdin 指定と解釈して以降の行を読み捨てる。語句は env 変数で渡し (`FROM=... TO=... perl -pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/g'`)、perl の stdin は `</dev/null` にする
8. **検証と反映**: 変更 file 名で `tests/` を逆引きして bats を実行する (`xargs bats` で渡す)。worktree で commit → main へ ff-merge (別 session の commit が先に含まれていたら cherry-pick) → push → `./claude-code/sync.sh to-local --yes` (全体 sync。hook は `~/.claude/` 側の辞書を読む) → `~/.claude/scripts/jp-quality-lint.sh` に禁止語を含む 1 行 file を渡して block になることと、言い換え後の文が hit しないことを確かめる。**lib の関数と lint script だけで終えず、`jq -n '{tool_name:"Write", tool_input:{file_path:"/tmp/x.md", content:"<禁止語を含む文>"}}' | bash ~/.claude/hooks/pre-tool-use.sh` の形で実物の hook にも JSON を渡し、block の message が出力されることを確かめる**。hook は `set -euo pipefail` で動き fail-close で exit 0 になるため、lib 側の変更が途中で止めていても lint script の結果だけでは気づけない (2026-09-14 に `shopt -p` の戻り値で hook が無出力のまま停止した。canonical: `rules/shell.md` 失敗パターンカタログ)
9. **commit message**: NG 語の literal を本文に記載すると自分の commit が hook に block される。「口語の圧縮動詞 5 語 (PRINCIPLES.md 「口語の圧縮動詞」)」のように語の一覧は辞書の section を指す

## 回収

`~/.claude/logs/ng-candidates.log` の `new` 行のうち辞書に無い語は `/sleep-review` Step 0 が候補として出す。検出器が拾えなかった発話 (長文の中の指摘等) は、その turn の AI がこの手順を実行して同じ log に手で 1 行追加する。

## Why

2026-09-05 に user が 1 session で 9 語 (畳む系 / 死蔵 / 孤児 / 流す / 倒す / 詰める / 引く / 寄せる / 折り畳み) を順に禁止と指摘し、そのたびに登録と言い換えを手で行った。指摘のたびに同じ手順を再発明せず、発話から登録までを 1 本の流れにする。

## 参照

- `guidelines/writing/NG-DICTIONARY.md` (辞書の canonical)
- `guidelines/writing/PRINCIPLES.md` 「口語の圧縮動詞」 / 「自然な話し言葉の日本語」
- `references/on-demand-rules/hook-implementation-pitfalls.md` 注意点 1 (NG list 追加時の 3 つの注意点)
- `references/on-demand-rules/measure-before-hook-change.md` (hook の block list を変更する前の baseline)
- `<repo-root>/memory/feedback-norm-retrofit-scope.md` (2026-09-07 の決定。Step 6 の遡及禁止はこれが canonical)
