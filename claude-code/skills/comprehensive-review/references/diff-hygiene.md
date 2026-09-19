# diff-hygiene

Perspective on the character of the diff as a whole. Instead of judging individual lines, inspect "why does this diff look like this?" This class of finding cannot be detected by per-file Edit / Write hooks; it becomes visible only at commit / PR granularity.

## Critical

| Item | Description |
|---|---|
| Purpose-drift edit | An "incidental cleanup" unrelated to the PR's purpose is mixed into the feature diff |
| Comment removal without justification | An existing comment whose intent is legible has been removed without a Why-not explanation |

## Warning

| Item | Description |
|---|---|
| Meaningless rename | A meaning-preserving synonym rename is mixed into hunks (e.g. only a 1:1 substitution such as `batch↔バッチ` / `インシデント↔障害` with no behavioral change) |
| Minimal-diff violation | Lines around the touched function that did not need to change have been rewritten (formatter re-run / blank-line cleanup mixed into a feature diff) |
| Cosmetic-only commit in feature PR | A commit with zero semantic change appears as a standalone cosmetic commit inside a feature PR |

## Inspection procedure

1. Run `git diff --stat` and note total hunk count and line count
2. For each hunk, judge three points:
   - (a) Is this change necessary for the PR's purpose (issue / title)?
   - (b) Did the removed comment carry information value (Why / Why not / a non-obvious constraint)?
   - (c) Does the rename have a semantic reason (clarifying meaning / unifying terminology)?
3. If more than three hunks fail to be justified by the above, raise Warning; if purpose-drift is obvious (a fix from an unrelated issue has slipped in), raise Critical

## Hard-to-judge cases

- Deciding "the substitution preserves meaning" is a semantic judgment. Regex cannot catch it; LLM comparison suits the job
- Deciding "useful comment" also requires a human to weigh information value. A "comment that restates the what already obvious from the function name" may be removed, but "Why not / non-obvious constraint" must not be deleted
- At single-file Edit time the whole diff is not visible, so a hook cannot detect this. **This perspective works only inside the review skill**

## Rationale (why this perspective was added)

Five real incidents in past code reviews:
- 「意味のない機械 rename (`batch → バッチ` / `インシデント → 障害`) を一緒に使うな」
- 「有用な comment を消しちゃっている」
- 「AI をもうちょい適切に扱えるようになってもらえると助かります」

Existing quality / readability perspectives have no slot for judging the character of the whole diff, and cannot separate the merit of a rename in isolation (whether it is a correct Japanese translation) from its meaning as a diff (whether this rename is needed in this PR right now).

## Related

- Existing hook `_check_edit_churn` (write-checkers.sh): warns when the same file is written more than three times. Churn watches "frequency"; diff-hygiene watches "content"
- Existing feedback memory `feedback_ai-diff-churn.md`: the abstract norm for churn
- Upstream skill: `comprehensive-review` Step 4.5 sorts this perspective into Critical / Warning output
