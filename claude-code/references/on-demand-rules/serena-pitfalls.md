# Serena MCP の注意点

`mcp__serena__*` tool を使う前に読む。

## 1. ai-tools repo で claude-code/ 配下は ignore される

ai-tools repo で `mcp__serena__*` symbol / insert / replace 系 tool を `claude-code/` 配下 file に発火すると `ValueError: Explicitly requested symbols in '<path>' while the path is ignored` で失敗する。`.gitignore` か `.serena/project.yml` の ignore 設定に由来する (未追跡 config)。

**Why**: 2026-07-20 の reviewer-agent.md 編集で `insert_after_symbol` が上記 error で fail し、Edit tool に fallback した。CLAUDE.md 「Serena 必須化」は「code 関連 tool の前に initial_instructions を呼ぶ」だが、ignore された path では Serena instruction 通りに動かせず built-in tool 使用が正当。

**How to apply**:
1. `claude-code/` 配下 (`agents/` `hooks/` `commands/` `skills/` `scripts/` 等) を編集するときは Serena symbol tool を試さず、最初から Read + Edit / Write / Bash で操作する
2. `docs/` `memory/` 配下は Serena OK (ignore 対象外)
3. error が発生した時は path が claude-code/ 配下かを確認して即 Edit fallback、Serena の再試行を繰り返さない
4. 恒久解: `.serena/project.yml` を見て ignore rule を明示する (未着手)

## 2. replace_content の regex 置換で helper 定義本体まで置換する

同一 file 内に helper 定義と call site の両方があるとき、`funcName\(([^)]+)\)` のような regex で call site を一括置換すると、`func funcName(param type)` の定義側も match して壊れる。

Go の例。`strPtr(s string) *string` を Go 1.26 `new(string(...))` に swap したい。`strPtr\(([^)]+)\)` → `new(string($!1))` の全置換で `func new(string(s string)) *string` の壊れた定義ができる (`s string` が引数リストと解釈される)。build tool は解釈せずに渡し、tail や grep で目視発見するしかない。

**Why**: call site と定義が同 file にある時、`func name(param list)` の内部 param list も needle pattern に一致する。「call site だけ書き換える」意図は regex に反映されず、Serena は plain regex なので単純 match で全て置換する。build が通ることがあるため気付きにくい。

**How to apply**:

- **推奨: 定義を消してから call site 置換に入る**。定義行が保持されていなければ collision の余地は生まれない
- **代替: negative look-behind で `func` を除外する**。`(?<!func\s)funcName\(([^)]+)\)` のようにする (Python re の DOTALL/MULTILINE 前提で動く)
- **併用: 置換後に必ず build + tail -20 で file 末尾を目視する**。`go build ./...` は param list が構造的に正しければ成功してしまう
- **cast 二重回避**: `intPtr(int(x))` → `new(int(x))` のように内側 cast を保つ場合、専用 regex `intPtr\(int\(([^)]+)\)\)` → `new(int($!1))` を先に実行してから `intPtr\(([^)]+)\)` → `new(int($!1))` の順で置換する。逆順だと `new(int(int(x)))` になる

## 3. replace_content regex mode の DOTALL 事故

`mcp__serena__replace_content` の regex mode は Python `re` の DOTALL + MULTILINE flag が常時 ON になる。`.` が改行も食う。「1 行を消すつもり」の regex が greedy に全行を飲む。2026-05-18 に 5 file で同時大量削除する事故が起きた。`git restore` で復旧し、literal mode 再実行で 1 行のみ削除に成功した。

**Why**:

- DOTALL の `.` は newline を含む全文字にヒットする
- greedy `.*` は longest match を取る
- 末尾の `\n` は file 末尾 newline まで届く
- `bash -n` の syntax check は通過する
- `git diff --stat` で `-48 lines` のような異常規模を見るまで気付けない

**How to apply**:

- 1 行削除は literal mode + 行末 `\n` 込み needle が最も安全になる
- 複数行 block 削除は regex mode で非貪欲 `.*?` と明示終端 anchor を使う
- shell 内に `\n` literal (backslash + n) が混入すると `n: command not found` で死ぬ
- 行全体が `\n` だけの混入は `grep -nE '^\\n$' <file>` で即検出する
- 実行検証を必ず実行する (`bash -n` だけでは不十分になる)
- regex 適用後は `git diff --stat` で削除行数が想定内 (1-5 行) か即確認する
- 大規模ヒットは即 `git restore` で復旧する

**v1.5.0 update (2026-05-19)**:

- `ContentReplacer.replace()` が改善された
- match 範囲内で同 pattern が再出現する case は `ValueError("Match is ambiguous: ...")` を返す
- `.*\n` greedy で同 pattern が再ヒットする case は構造的に検出される
- ただし 1 file 内で同 pattern が非再出現の greedy 食いは依然発生する
- `ReplaceContentTool` 自体は DOTALL/MULTILINE を hardcode する
- `multiline` opt-out は `search_for_pattern` のみで開放されている
- 実務手順は変更なし (literal mode / 非貪欲 + 終端 anchor / `git diff --stat` 確認)
- error 文言 `Match is ambiguous` を見たら即 literal mode 切替か終端 anchor 明示で再実行する

## 4. 別 worktree での相対 path は project root (main 側) に解決される

Serena の project root は起動時の worktree に固定される。別の worktree (`<ghq-root>/worktrees/<repo>-<slug>`) で `replace_content` 等を相対 path で呼ぶと、root 側の同名 file を書き換える (2026-09-03 に発生、`git checkout -- <file>` で復元)。別 worktree の編集は Bash (python / sed) で行い、Serena の編集 tool は cwd が root と一致するときだけ使う。

**絶対 path でも防げない (2026-09-08 に再発)**。developer-agent 4 体を worktree へ fan-out したところ、4 体とも `replace_content` が main checkout を書き換えた。agent には `activate_project` が渡らないので、prompt で worktree の絶対 path を指定しても project root を差し替える手段がない。1 体は 40 件近く、別の 1 体は 27 件を main 側へ書き込み、各自が `git checkout --` で復元した。**worktree を割り当てる委譲では、prompt に「Serena の編集 tool を使わず built-in Edit に worktree の絶対 path を渡す」と明記する**。親は fan-out 後に `git -C <main repo> status --short` を見て、担当 file が M で出ていないか確かめる。禁止条項は `agents/developer-agent.md` 「Absolute prohibitions」 にある。

## 関連

- `references/serena-tool-map.md` — Serena tool 一覧
