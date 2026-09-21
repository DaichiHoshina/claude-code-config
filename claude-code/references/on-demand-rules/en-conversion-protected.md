# EN 化保護対象 file (英語化禁止)

`/claude-update-fix` / EN 化系 refactor / developer-agent 委譲 で **絶対に英語化してはいけない** file・section リスト。違反すると規約破壊・bats test 破壊・JP user input trigger 不一致が発生する。

## File 単位 (body 全文 JP 維持)

- `guidelines/writing/PRINCIPLES.md` — 規約 file 自体が JP、EN 化で規約と矛盾
- `commands/jp-fix.md` — JP writing 例示が規範 (frontmatter は EN OK、body のみ保護)
- `commands/post-comment.md` — 同上
- `commands/spec-design.md` — 同上
- `commands/prd.md` — 同上
- `guidelines/writing/*.md` (全 file、canonical: `ls guidelines/writing/*.md` で導出) — 執筆規約・NG 辞書・JP 文体規範
- `rules/thinking-principles.md` — JP 文言が `tests/integration/thinking-principles-sync.bats` の anchor
- `../codex/AGENTS.md.example` の managed:codex-thinking block — 同上 (3 tool 同期 anchor)
- `../cursor/rules/ai-tools-thinking.mdc` — 同上 (3 tool 同期 anchor)
- `references/developer-agent-delegation-prompt.md` — Section 0 checklist の JP 文言 4 件 (「target file:line 特定済」「verify cmd 確定済」「DoD 1 行化済」「単 domain」) が `tests/integration/orchestrate-mode.bats` の exact-match anchor。4 件だけ保持して他を EN 化すると表記が割れるので file ごと JP に据える (2026-08-29 に EN 化を試みて撤回)。見出し `## 0. Parent pre-delegation checklist` も同 bats の anchor なので rename しない

## Section 単位 (file 内一部のみ JP 維持)

- `CLAUDE.md` "## Natural Language Triggers (major only)" section (現在 L86-100 付近) — table 内 JP trigger ("pushして" / "全自動で" / "レビュー" 等) は user 入力 pattern なので literal 維持必須
- `CLAUDE.md` 冒頭注 (現在 L3) — 文体 default 説明
- `references/PARALLEL-PATTERNS.md` `forbidden_phrases` section (現在 L162-166 付近) — bats test が exact-match で検証する JP literal

> 前述の line 番号は参考値。CLAUDE.md は頻繁更新されるため section heading 名で grep して位置確認すること。

## Literal 維持 (技術的理由)

- 全 Go code block — technical idiom、コメントは JP のまま
- bats test の expected output / fixture 内 JP literal — test assertion 破壊回避
- `commands/dev.md` の `skip 4 conditions` — `tests/integration/parallel-consistency.bats` の anchor。EN の言い回しとしては `the four --auto skip conditions` の方が自然だが、言い換えると test が失敗する

## EN 化の着手前に必ず打つ確認

保護 list は網羅ではなく、**test の anchor は増える**。EN 化する file を決めたら、着手前にその file の JP 文言と、見出しに含まれる英語 literal の両方を `tests/` へ逆引きする。

```bash
grep -rn "<その file の JP 見出し / 特徴的な JP 文>" tests/
grep -rn "<見出しに含まれる英語 literal>" tests/
```

JP 文言だけを見ても足りない。JP の地の文に埋め込まれた英語 literal が anchor になっている例があり、2026-08-29 に `commands/dev.md` の `skip 4 conditions` を EN 化のついでに言い換えて `tests/integration/parallel-consistency.bats` を削除した。hit した file は EN 化の対象から外すか、anchor になっている literal だけ元の綴りで保持する。

## 違反時の影響

| 対象 | 違反時症状 |
|------|----------|
| `guidelines/writing/PRINCIPLES.md` | 規約 file が EN だと文体規約自体が矛盾 |
| `commands/{text,post-comment,...}.md` body | JP writing 例示が EN になり command の本来用途破壊 |
| `guidelines/writing/*` | NG 辞書の JP literal 消失で執筆検証不能 |
| CLAUDE.md Natural Language Triggers | "pushして" 等の trigger 不一致で `/git-push --pr` 自動発火失敗 |
| `PARALLEL-PATTERNS.md` forbidden_phrases | `tests/integration/parallel-consistency.bats` が exact-match 失敗 |
| `developer-agent-delegation-prompt.md` Section 0 | `tests/integration/orchestrate-mode.bats` が checklist 4 件の grep -F で失敗 |
| `commands/dev.md` の `skip 4 conditions` | `tests/integration/parallel-consistency.bats` が canonical 参照を見つけられず失敗 |

## 参照元

- `CLAUDE.md` "## Definition File Token Saving" section の末尾
- developer-agent / `/claude-update-fix` 委譲 prompt template (将来追加)
