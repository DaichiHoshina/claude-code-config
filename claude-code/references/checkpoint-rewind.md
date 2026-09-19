# Checkpoint / Rewind

Claude Code auto-creates a checkpoint per user prompt (file snapshots for the 100 most recent, kept 30 days with the session). Restore conversation, code, or both to a prior state.

## Operations

| Action | Effect |
|--------|--------|
| `Esc` | Stop Claude mid-execution. Keep context, change direction |
| `Esc + Esc` (empty input) or `/rewind` | Show rewind menu (input に text があると double Esc は clear 動作) |
| `"Undo that"` | Ask Claude to revert the last change |
| `/clear` | Full context reset between unrelated tasks |

## Rewind menu (6 択)

Select a prompt in the list, then choose:

| Option | Effect |
|--------|--------|
| Restore code and conversation | Revert both to that point |
| Restore conversation | Rewind conversation, keep current code |
| Restore code | Revert file changes, keep conversation |
| Summarize from here | その地点以降を要約に圧縮 (targeted `/compact` 相当) |
| Summarize up to here | その地点より前を要約に圧縮、以降の message は保持 |
| Never mind | Return without changes |

- Restore 系 code option は tracked file change がある checkpoint のみ表示される
- Summarize option を arrow key で highlight し「add context (optional)」欄に指示を入力すると要約の焦点を誘導できる。番号 key 選択は即時要約
- Summarize は file を変えず、原文 message は transcript に保持される (Claude は詳細参照可)。圧縮位置に **Summarized conversation** marker が入る
- `/clear` 実行済みの process では menu 先頭に `/resume <session-id> (previous session)` entry が表示される (v2.1.191+)。clear 前の会話へ復帰できる
- 別 approach への分岐は Summarize でなく `/branch` か `claude --continue --fork-session` を使う

## When to Use

- **Risky trials**: Run bold changes assuming "rewind if it fails"
- **Contaminated conversation**: After 2+ failed corrections, clean up with Summarize from here
- **Experiment branching**: Try multiple approaches in sequence, keep the best
- **Cross-session**: Checkpoints persist after session end. Rewind works after closing the terminal

## Constraints

- Checkpoints track **only Claude's file-editing tools**. Bash 経由の変更 (rm / mv / cp)・manual edits・他 session の編集は対象外
- **Subagent edits は通常 restore されない** (foreground forked skill のみ例外)。git で戻す
- **Symlink / hard link path は restore を skip** し `Restored the code, but skipped N files` warning が表示される (v2.1.216+。dotfile manager の symlink / pnpm hard link が該当)
- **Not a git replacement**. Use git commit for important state preservation
- No new tool calls during rewind

## Official Recommended Pattern

> "tell Claude to try something risky. If it doesn't work, rewind and try a different approach." — over "carefully planning every move"

Compare planning cost vs trial cost. If trial is cheap, run with rewind assumed.

## Related Commands

- `claude --continue` — resume previous session
- `claude --resume` — select from recent sessions
- `/rename` — assign session name (e.g., `oauth-migration`, `debugging-memory-leak`)
- `/btw` — side question without contaminating context. Answer shown in overlay, not saved to history
