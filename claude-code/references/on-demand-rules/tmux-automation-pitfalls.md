# tmux 自動化の注意点

Bash tool / GUI app (Raycast 等) から tmux window を script で量産・操作する時に読む。3 件とも 2026-07-31 の remote-control 受け口一括作成で実踏した。

## 1. Bash tool の for ループ内 tmux new-window 連続実行は一部が消える

Bash tool 内で `for name in a b c; do tmux new-window ...; done` のように長時間コマンド付き window を for ループで複数作ると、一部の window が即時または数秒後に消える。同じ内容を for ループを使わず 1 行ずつ flat に並べると全部安定して保持される。

**Why**: 仕事 repo の worktree 13 個に受け口を一括で作ろうとして発生した。for ループ 12 個同時実行で 0 個生存、flat 6 個ずつで 5〜6 個生存、単独再実行で生存という結果だった。tmux 側でなく、Bash tool の sandbox が for ループ由来の子プロセス group をまとめて reap している可能性が高い (未確定)。

**How to apply**: 複数の長時間 background プロセスの一括起動は、bash の `for`/`while` を避けてコマンドを flat に並べて 1 つの Bash tool 呼び出しで実行する。実行後は `tmux list-windows` で期待数と一致するか確認し、欠けた分だけ個別に再実行する。

## 2. 永続 tmux session の新規 window は session 生成時点の古い環境変数を引き継ぐ

tmux の永続 session に新しい window を作ると、session が最初に作られた時点の環境が `tmux show-environment -g` に固定され、以後の新規 window はそこから引き継ぐ。settings 側を修正しても既存 session の global environment には反映されない。実例: 削除済みのはずの `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` を新規 window だけが引き継ぎ、`claude remote-control` が起動失敗した。

**How to apply**: tmux 新規 window でだけ環境依存 feature が失敗したら、まず `tmux show-environment -g | grep -i claude` で汚染変数を確認する。汚染されていたら `tmux set-environment -g -u <VAR>` で削除すれば、以後の新規 window は正しい環境を引き継ぐ (session 作り直しは不要)。

## 3. GUI app の execFile は絶対 path 必須、tmux window 名のドットは target 指定を壊す

- **execFile の path 解決**: Raycast 等 LaunchServices 経由の GUI app は Homebrew の `/opt/homebrew/bin` を含む shell PATH を継承しない。`execFile("tmux", [...])` は `spawn tmux ENOENT` で失敗し、toast にエラーが表示されないと気づきにくい。
- **window 名のドット**: tmux の target 構文は `session:window.pane` で `.` を pane 区切りに使う。repo 名由来の `.com` 等を含む window 名だと `send-keys -t <session>:<repo>.com-...` が `.` 以降を pane 番号と誤認して `can't find pane` で失敗する。window 自体は正常に作れてしまうため、「window はあるが中でコマンドが動いていない」半端な状態になる。

**How to apply**: (1) GUI app から CLI を呼ぶときは `which <cmd>` の絶対 path を定数化して使う。(2) ドットを含みうる window 名は `send-keys -t session:name` の文字列組み立てで再アドレッシングせず、`new-window -t <session> -n <name> -c <path> "<command>"` のように生成コマンドへ実行内容を直接渡して target 指定自体をなくす。

## 関連

- `references/on-demand-rules/bash-tool-environment.md` — Bash tool の環境制約
- `references/on-demand-rules/macos-shell-testing-pitfalls.md` — launchd / macOS shell の注意点
