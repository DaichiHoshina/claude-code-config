# repo rule manifest (ai-tools を repo 構造に依存させない仕組み)

repo ごとの rule の置き場所と frontmatter の key は **repo によって違う**。これを command 本文に literal で記載すると、ai-tools が特定 repo の内部構造に依存し、公開したときにその構造が外部へ露出する。宣言を local manifest へ出し、ai-tools 側は解決 script を呼ぶだけにする。

trigger: `/review-full` / `/spec-plan` / `/spec-dev` が repo rule を参照するとき。manifest を新しい repo 向けに書き足すとき。

## 解決 script

```bash
~/.claude/scripts/resolve-repo-rules.sh <changed-file>...   # 当たる rule の絶対 path
~/.claude/scripts/resolve-repo-rules.sh --review-docs        # repo 固有の review 定義
~/.claude/scripts/resolve-repo-rules.sh --get <key>          # repo profile の 1 値 (dot 区切り)
```

いずれも exit 0 = 解決した (0 件でも 0)、**exit 3 = manifest 不在・対象 repo の節が無い・key 未宣言のいずれかで skip**。exit 3 のときは該当の手順を省略し「manifest 未設定のため skip」と 1 行報告する。dir 構造や command 名を推測した fallback は記載しない (推測を記載すると repo 依存が command 本文へ戻る)。

## manifest

置き場所は `$CLAUDE_REPO_RULES_MANIFEST`、既定は `~/.claude/references-private/repo-rules.json`。`references-private` は `sync.sh` の `SYNC_ITEMS` に無いので同期で消えない。social-hit term を記載してよい唯一の領域でもある (`rules/public-repo-private-data-block.md`)。AI は read のみで、追記は user が行う。

```json
{
  "repos": [
    {
      "path_prefix": "*/<repo を含む glob>*",
      "sources": [
        { "dir": "<正本の rule dir>", "glob_key": "globs" },
        { "dir": "<生成物の rule dir>", "glob_key": "paths" }
      ]
    }
  ]
}
```

- `path_prefix` は repo root の絶対 path に対する glob。worktree (`<ghq-root>/worktrees/<repo>-<slug>`) と本体を 1 節で当てるため、repo root の basename 完全一致にしない
- `sources` は宣言順に見て、**実在する最初の dir** を採る。正本を先、生成物を後に置く。生成物が `.gitignore` 済みで未同期 worktree では 0 本になる repo でも、正本が先にあれば当たる
- `glob_key` はその dir の rule が glob を記載する frontmatter の key 名。正本と生成物で key が違う repo があるため source ごとに保持する

### repo profile の任意 key (`--get` で取得する)

rule 以外の repo 固有値もここに宣言し、command 本文には key 名だけを記載する。宣言が無ければ `--get` は exit 3 を返すので、command 側は skip か汎用手順に切り替える。

| key | 用途 | 取得する command |
|---|---|---|
| `orm_registration_file` | 新しい entity の table 登録先 | `/spec-plan` |
| `branch_pattern` / `worktree_root` | branch と worktree の命名・置き場所 | `/spec-dev` / `scripts/spec-gate.sh` |
| `commands.api_docs_gen` | API doc の生成 command | `/spec-plan` |
| `commands.db_describe` | DB 定義の確認 command | `/spec-dev` |

## large-repo path list (別 file)

連続 inline 編集で delegation を促す対象 repo は `$CLAUDE_LARGE_REPO_PATHS_FILE` (既定 `~/.claude/references-private/large-repo-paths.txt`) に 1 行 1 glob で宣言する。`hooks/lib/agent-guard.sh` が読み、**file が無ければ判定ごと no-op** になる。hot path (`pre-tool-use.sh`) から Edit ごとに呼ばれるため、jq を使わない平文 list にしてある。

## 当たり判定

- 変更 file は repo root 相対に合わせてから照合する。`**/` は 0 段以上の dir、`*` は `/` を含まない
- `**/*` と `**` を含む rule、および **frontmatter を含まない rule** は対象領域を限定できないので常に当たる扱いにする
- glob が当たらないが file 名の慣習が違うだけの rule の扱いは `commands/spec-plan.md` の突き合わせ規約に従う

## 関連

- `references/local-files-setup.md` — 機体固有 local file の一覧と点検 (新 machine 移行時)

- `scripts/resolve-repo-rules.sh` — 実装
- `tests/unit/scripts/resolve-repo-rules.bats` — 当たり判定と exit 3 の回帰
- `hooks/lib/bash-checkers.sh` — env var 未設定なら機能ごと no-op にする先例
- `lib/redact.sh` — env var で上書きできる既定 path の先例
