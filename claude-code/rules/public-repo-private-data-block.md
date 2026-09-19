---
description: Hard-block internal product names / identifiers from being written to the ai-tools repo (may be partially published)
paths: ["**/*"]
---

# Public-repo private-data block

`<repo-root>/` repo は現在 private だが、**一部を分離して公開する可能性がある**。公開時に秘匿情報が外部へ出ないよう、社内 product 名 / 社内識別子 / 個人名 / 会社名 / project 固有名詞を `<repo-root>/` 配下 file と commit message に書き込むことを最初から禁止する。hook (`hooks/pre-tool-use.sh` + `hooks/lib/public-repo-guard.sh`) が Write / Edit / commit / PR / issue 系で hard block する。

## social-hit term の置き場

term の実体は repo に置かない (ai-tools は一部を公開する可能性があるため)。2 系統を **別 file** で保持する。

| 系統 | file | env var | 発火条件 |
|---|---|---|---|
| social-hit (社内 product / doc 名) | `~/.claude/references-private/social-hit-terms.txt` | `SOCIAL_HIT_TERM_FILE` | cwd が ai-tools 配下のときだけ |
| private-name (個人名 / 会社名) | `~/.claude/references-private/private-name-list.txt` | `PRIVATE_TERM_FILE` | cwd 無条件 |

どちらも 1 行 1 term、`#` 始まりは注記、user が記入し AI は read のみとする。**2 つを 1 file に統合しない**。統合すると social-hit が cwd 無条件で当たり、product repo での `gh pr create` が自 project 名で block される。

file が不在なら term 0 件となり block は適用されない (fail-open)。機体固有 file の全体像と点検手順は `references/local-files-setup.md` にある。新しい機体では上記 2 file を置くまで hook 側の保護が無いので、後述の AI 側 default rule で補う。

## AI 側 default rule

list に literal match しない場合でも、個人名 / 会社名 / 社内 codename・service 名・doc 名を出力しない。匿名化形式は `<person-name>` / `<company-name>` / `<project-name>` / `<service-name>` を使う。allowlist (block しない): 本人 (`daichi` / `<owner>` / `Daichi Hoshina`) / `Anthropic` / `Claude` / OSS・public product 名。

## commit / PR draft 時の人名 self-check

commit message / PR body / issue comment の draft 前に固有名詞を点検する (`@<handle>` / 「<姓名>さん」/ Slack display name / 社内 alias)。レビュー指摘を引用するときは handle を伏せて「レビュー指摘」と総称する。Co-Authored-By trailer の AI marker は人物ではないため対象外とする。

## hit 時の対応

`~/.claude/references-private/` へ保存先を切替えるか、term を削除 / 匿名化して再実行する。自己除外 file list と詳細判定 logic は `hooks/lib/public-repo-guard.sh` を参照する。block log: `~/.claude/logs/social-hit-block.log`。incident 経緯: `references/on-demand-rules/public-repo-incident-history.md`。
