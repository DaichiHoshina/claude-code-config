# lib/ - 共有ライブラリ

Claude Code フック・スクリプト間で共有される関数群。

## 前提条件

| 要件 | 最低バージョン |
|------|-------------|
| bash | 5.0+ |
| jq | 1.6+ |
| git | 2.0+ |

`common.sh` は読み込み時に bash 5.0 未満を検出すると exit する（`lib/common.sh` のバージョンガード）。macOS 標準の bash 3.2 では動かないため `brew install bash` が必須。

インストール: `brew install bash jq git`（macOS）、`sudo apt-get install bash jq git`（Ubuntu）

## 読み込み方法

```bash
# common.sh 経由（推奨）
source "${SCRIPT_DIR}/../lib/common.sh"

# detect ライブラリ（個別）
load_lib "detect-from-keywords.sh"

```

## ライブラリ一覧

### Level 0: 依存なし

| ファイル | 提供内容 |
|--------|---------|
| `colors.sh` | ANSIカラー変数（`BLUE`, `GREEN`, `YELLOW`, `RED`, `BOLD`, `RESET`） |
| `security-functions.sh` | OWASP対策・入力検証（`escape_sed_pattern`, `safe_read_token`, `validate_json`, `prevent_path_traversal`） |

### Level 1: colors.sh に依存

| ファイル | 提供内容 |
|--------|---------|
| `print-functions.sh` | 出力ヘルパー（`print_header`, `print_success`, `print_warning`, `print_error`, `print_info`, `confirm`） |

### Level 2: 独立または Level 1 に依存

| ファイル | 提供内容 |
|--------|---------|
| `hook-utils.sh` | フック入力解析（`read_hook_input`, `get_field`, `get_nested_field`）、jq に依存 |

### Level 3: 検出ライブラリ（user-prompt-submit.sh で使用）

| ファイル | 提供内容 |
|--------|---------|
| `detect-from-keywords.sh` | プロンプトキーワードから検出、LRUキャッシュ内蔵（100エントリ） |
| `detect-technique.sh` | テクニック自動推奨（TDD、リファクタリング等） |

### 個別読み込み（`common.sh` 経由ではなく各フック・スクリプトが直接 source）

| ファイル | 提供内容 |
|--------|---------|
| `stop-common.sh` | stop 系フック（`stop.sh` / `stop-failure.sh` / `stop-verify.sh`）の共通処理 |
| `output-sanitizer.sh` | 出力の secret / PII マスク（`pre-tool-use.sh` 等が使用） |
| `redact.sh` | 個人情報・内部識別子の redact ヘルパー |
| `validator.sh` | 入力・設定値のバリデーション |
| `comment-style-checker.sh` | code comment の Why not / 最小限ルール検査 |
| `writing-self-check.sh` | 外向きテキストの文体セルフチェック |
| `jp-quality-check.sh` | 日本語品質チェックの入口（`jp-quality/` 配下を束ねる） |
| `analytics-writer.sh` | usage ログの記録 |
| `bats-self-check.sh` | bats テスト環境のセルフチェック |
| `env-configurator.sh` | `install.sh` の環境変数・設定ファイル展開 |
| `mcp-installer.sh` | MCP サーバー設定の生成・インストール |

### サブディレクトリ

| ディレクトリ | 内容 |
|--------|---------|
| `hook-utils/` | `command-classifier.sh` / `json-io.sh` / `notification.sh` / `path-helpers.sh` |
| `jp-quality/` | `block-checks.sh` / `structural-checks.sh` / `term-extraction.sh`（`jp-quality-check.sh` から使用） |

## 読み込み順序

common.sh は以下を自動読み込み（重複防止あり）：

```
1. colors.sh
2. print-functions.sh
3. security-functions.sh
4. hook-utils.sh
```

detect（Level 3）・自律実行ライブラリ（Level 4）は `load_lib()` で個別に読み込む。

## 新しいライブラリを追加する場合

1. `lib/new-library.sh` を作成する。shebang は `#!/usr/bin/env bash` にする
2. 依存関係に応じて Level を決定し、`common.sh` に追加する
3. この README に 1 行説明を追記する
4. `tests/unit/lib/new-library.bats` に単体テストを作成する
