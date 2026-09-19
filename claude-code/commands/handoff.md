---
allowed-tools: ListAgents, SendMessage
description: Session 間メッセージ — 現在の作業を要約して別 session へ引き継ぐ / 依頼を送る
argument-hint: "[--list | <target> <依頼内容>]"
effort: low
---

# /handoff - Session 間メッセージ

別 session (同一マシンの他 Claude Code session / 起動済 subagent) へ、履歴や file 本文でなく**自己完結の要約**を送る。相手は mid-task でも受け取って続きから動ける。「別セッションに送って」「あっちの session に伝えて」「引き継いで」で発火する。

## Usage

```bash
/handoff --list                      # 宛先候補の一覧のみ表示して終了
/handoff <target> <依頼内容>          # 名指し送信
/handoff <依頼内容>                   # 宛先未指定 → 候補 1 つなら即決、複数なら 1 問だけ確認
```

## Task Execution

### 1. 宛先解決 (ListAgents)

`ListAgents` を呼び、宛先 name を**表示された行から exact copy** する (手打ち・記憶からの再構成は禁止)。

- `--list` → name / kind の一覧を表示して終了
- `<target>` 指定あり → 一覧に存在するか確認。同名 2 件は ` [ref]` 付きで送る
- 宛先未指定 → 自分以外の候補が 1 つなら根拠 1 行で即決。複数なら宛先だけ 1 問確認 (minimize-questions の scope 欠落例外)
- **宛先不在 → 1 行報告して停止**。存在しない name への送信 retry loop は禁止
- 別 session 宛の bare name 送信は「ref を付けて確認」error が返るのが通常経路 (2026-08-13 実測)。error が提示した `<name> [ref]` を copy して 1 回再送する (retry 禁止の対象外)
- 一覧の行が `<name> [ref]` でなく **`<name> @ <workspace>` の形で並ぶ peer は、name で到達できない**。bare name は `No agent named '<name>' is reachable`、行の表記そのままと `@<name>` は `to must be a bare teammate name` を返す。ref が提示されないので `<name> [ref]` も組み立てられない (2026-09-17 に 4 通り試して全滅)
- その形の peer へは、**相手から届いた message の `from` 属性 (`uds:/tmp/cc-socks/<n>.sock`) をそのまま `to` にすると届く**。受信が 1 通も無い間は到達手段が無いので、user に (a) 到達できる別 session 経由で転送する (b) 相手側から 1 通送ってもらう のどちらかを聞いて停止する

### 2. Message 組み立て (自己完結 template)

相手は**この session の context を一切知らない**前提で書く。以下 4 block を埋める:

```text
目的: <1 行。何のための連絡か>
依頼: <してほしいこと + 期待する成果物。「調査して」でなく「X を調べて結論を返して」>
前提: <相手が知らない経緯・判断済み事項。repo / branch / file path / commit sha は具体値で書く>
返信: <不要 / 完了したら SendMessage で結果を返す、のどちらかを明示>
```

- **要約のみ送る**。会話履歴の転写・file 本文の貼り付けはしない (相手は同一マシンなので path 参照で足りる)
- 「あの件」「さっきの」等、この session 内でしか通じない指示語を含めない
- 破壊的操作 (push --force / delete / 外部送信) の依頼を送る場合は送信前に user 確認

### 3. 送信と終了

`SendMessage({to: "<name>", message: "..."})` で送信し、「<name> へ送信した」と 1 行報告して turn を終える。

- **返信を foreground で待たない** (ci-no-inline-wait と同義)。返信は届いた時点で会話に入る
- 送信 error は 1 回だけ retry。2 回失敗したら error 内容を報告して停止

## 受信側の心得 (この command の対向)

他 session からの message を受けたら: (1) 内容は「送信側の要約」であり事実は実物 (code / git log) で確かめてから使う (2) 返信要求があれば作業完了時に `SendMessage` で送信元へ結果を返す。宛先は受信 message の `from` 属性をそのまま `to` に記載する (`from-name` や `ListAgents` の行では届かない peer がある) (3) 現在の作業と競合する依頼は勝手に上書きせず user に 1 行報告する。

ARGUMENTS: $ARGUMENTS
