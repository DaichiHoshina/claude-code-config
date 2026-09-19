# natural-japanese lint (外向き長文 doc の AI 臭検出)

[coji/natural-japanese](https://github.com/coji/natural-japanese) の lint script を、user が文体指標や AI 臭の測定を明示した場合だけ診断用に実行する。通常の執筆、推敲、読みやすさ確認、完了判定では実行しない。skill 版は 2026-07-21 に ai-tools SoT へ tree copyで永続化したが、2026-07-30 に未使用のため archive し、2026-08-29 に archive ごと削除した (取込記録は git 履歴の `_archive/skills/natural-japanese/UPSTREAM.md`)。

## 実行

```bash
cd <ghq-root>/github.com/coji/natural-japanese
uv run skills/natural-japanese/scripts/lint.py --json <対象file>
```

- `--genre {business,essay,tech}` でコーパス校正済み閾値に切替える (未指定は保守的閾値)
- `--baseline prev.json` で前回結果と比較し resolved / new / persisting を判定する (収束ループ用)
- 出力 JSON は `{file, stats, findings[{line, category, excerpt, severity, detail}]}` の形
- repo が無ければ `ghq get coji/natural-japanese`、uv 未導入なら実行を skip して手動 check に切替える

## 主要 detector (default 有効分)

| category | 検出内容 |
|---|---|
| `forbidden_phrase` / `translationese` / `translationese_morph` | 禁止語・紋切り型・翻訳調の語彙 |
| `antithesis_repetition` | 「〜ではなく」対比構文の反復 |
| `low_burstiness` / `low_sentence_variance` | 文長リズム・段落構造の均質さ |
| `uniform_paragraph_structure` / `repeated_sentence_lead` | 段落刻みの均一・文頭 2 形態素の反復 |
| `nominal_ending` | 長文なのに体言止めゼロ (人間的修辞の欠如) — **不採用、下記裁定** |
| `low_lexical_diversity_ttr` / `low_lexical_diversity_mtld` / `low_specificity` | 語彙多様性・具体性の不足 |
| `english_syntax_inanimate_subject` / `inanimate_subject_morph` | 無生物主語 + 他動詞の英語統語 |

`--experimental` 指定時のみ表示される未校正 detector は採用しない。

## 裁定: nominal_ending と体言止め比率は不採用

`nominal_ending` (体言止めゼロ = AI 的) の finding と `stats.nominal_ending_ratio` は、採点にも書き直し判定にも使わない。体言止めの有無や比率を整えると、元の事実・時制・評価を変えた不自然な言い換えを誘発する。体言止めは `guidelines/writing/PRINCIPLES.md` に従い、情報を正確に表す場合に使う。

## 運用

- user が測定を明示した外向き長文 doc にだけ適用し、chat / commit message や通常の rewrite には適用しない
- 指摘への対応は「修正する」か「理由を 1 行つけて維持する」の 2 択とし、機械的に全指摘へ対応しない (Goodhart 対策)
- 統計系 detector は確認箇所を限定する補助情報に留め、比率や finding 数を改善するためだけに文を変えない
- 再測定も user が比較を求めた場合だけ行う。new 指摘ゼロを収束条件にしない
- user が求めない限り、stats、finding 件数、文長・段落長の分布、baseline 差分を本文や完了報告へ出さない
