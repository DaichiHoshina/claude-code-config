#!/bin/bash
# =============================================================================
# publish-export.sh — claude-code/ の設定を公開 repo へ選別 export する
#
# 設計: docs/design/2026-09-12_claude-code-config-publish-export.md
# 入力: publish/allowlist.txt (include / exclude)、publish/replace-rules.txt (置換 rule)、
#       機体の term list 2 file (SOCIAL_HIT_TERM_FILE / PRIVATE_TERM_FILE)
#
# 使い方:
#   publish-export.sh --dry-run          staging を作り、全判定の結果を表示する (何も書き込まない)
#   publish-export.sh --status           公開 repo の manifest と SoT の差を表示する   (Phase 3)
#   publish-export.sh --init             公開 repo を private で作成し初回 export する (Phase 3)
#   publish-export.sh [--accept-new]     export (検査を通過したら公開 repo を更新する)   (Phase 3)
#
# 判定の順序 (DD 6.1): term list、staging 作成と置換、root file (README / LICENSE) の staging、
#              秘匿検査、初出 file、置換と commit の順。root file は置換の対象外で、秘匿検査だけを当てる。
# 秘匿検査は fail-closed で、term list が不在か placeholder (term 0 件) なら停止する (DD 決定 2)。
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/print-functions.sh
source "${SCRIPT_DIR}/../lib/print-functions.sh"

SOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
STAGING_DIR=""
# 公開 repo の root に置く file (README / LICENSE) の staging。秘匿検査の対象にする
ROOT_STAGING=""
KEEP_STAGING=0
MODE="export"
ACCEPT_NEW=0
# 公開 repo の名前と local clone の置き場。--remote は test 用で、指定すると repo の作成を skip する
PUBLISH_NAME="${PUBLISH_NAME:-claude-code-config}"
REMOTE_PATH=""
GITHUB_OWNER="${GITHUB_OWNER:-<owner>}"
SOCIAL_HIT_TERM_FILE="${SOCIAL_HIT_TERM_FILE:-$HOME/.claude/references-private/social-hit-terms.txt}"
PRIVATE_TERM_FILE="${PRIVATE_TERM_FILE:-$HOME/.claude/references-private/private-name-list.txt}"

# 停止条件に該当した判定の件数。--dry-run は停止せず全判定を進めて最後に exit code へ反映する
STOP_COUNT=0

usage() {
    sed -n '/^# 使い方:/,/^# 判定の順序/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) MODE="dry-run" ;;
        --status) MODE="status" ;;
        --init) MODE="init" ;;
        --accept-new) ACCEPT_NEW=1 ;;
        --name) PUBLISH_NAME="$2"; shift ;;
        --remote) REMOTE_PATH="$2"; shift ;;
        --sot) SOT_DIR="$(cd "$2" && pwd -P)"; shift ;;
        --staging) STAGING_DIR="$2"; KEEP_STAGING=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) print_error "不明な option: $1"; usage; exit 2 ;;
    esac
    shift
done

ALLOWLIST="${SOT_DIR}/publish/allowlist.txt"
REPLACE_RULES="${SOT_DIR}/publish/replace-rules.txt"
README_SRC="${SOT_DIR}/publish/README.public.md"
LICENSE_SRC="${SOT_DIR}/../LICENSE"
# local clone は sync.sh の同期対象の外に置く
CLONE_DIR="${PUBLISH_CLONE_DIR:-$HOME/.claude/publish/$PUBLISH_NAME}"
MANIFEST_NAME=".publish-manifest.json"
# 公開 repo では設定本体を claude-code/ の下に置く (sync.sh と install.sh が
# claude-code/ を含む dir を repo root として解決する)
PUBLISH_SUBDIR="claude-code"

# -----------------------------------------------------------------------------
# 判定結果の記録。label は判定名、status は PASS / STOP / INFO
# -----------------------------------------------------------------------------
report() {
    local status="$1" label="$2" detail="$3"
    printf '%-4s  %-14s  %s\n' "$status" "$label" "$detail"
    [[ "$status" == "STOP" ]] && STOP_COUNT=$((STOP_COUNT + 1))
    return 0
}

# 停止条件に該当したとき、dry-run 以外は即終了する
stop_unless_dry_run() {
    [[ "$MODE" == "dry-run" ]] && return 0
    exit 1
}

# -----------------------------------------------------------------------------
# term list。hooks/lib/public-repo-guard.sh と同じ書式 (1 行 1 term、# は注記) を読む。
# hook 側の loader は private-name の path を env で上書きできないため、ここで同書式の loader を定義する
# -----------------------------------------------------------------------------
load_terms() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    grep -v '^[[:space:]]*#' "$file" | grep -v '^[[:space:]]*$' || true
}

check_term_lists() {
    local f n total=0
    # 判定は 2 file の term 合計で行う。社内 product 名を登録していない機体でも、
    # 個人名の list に term があれば検査は機能する。合計 0 件のときだけ停止する
    for f in "$SOCIAL_HIT_TERM_FILE" "$PRIVATE_TERM_FILE"; do
        if [[ ! -f "$f" ]]; then
            report INFO term-list "不在: $f"
            continue
        fi
        n=$(load_terms "$f" | wc -l | tr -d ' ')
        total=$((total + n))
        if [[ "$n" -eq 0 ]]; then
            report INFO term-list "term 0 件 (注記だけの雛形): $f"
        else
            report PASS term-list "${n} 件: $f"
        fi
    done
    if [[ "$total" -eq 0 ]]; then
        report STOP term-list "term list 未整備 (2 file の term 合計が 0 件)"
        stop_unless_dry_run
    else
        report PASS term-list "term 合計 ${total} 件"
    fi
}

# -----------------------------------------------------------------------------
# allowlist。"+ path" が include、"- path" が exclude
# -----------------------------------------------------------------------------
read_allowlist() {
    local kind="$1"
    [[ -f "$ALLOWLIST" ]] || return 0
    grep -E "^\\${kind} " "$ALLOWLIST" | sed -E "s/^\\${kind} //" | sed -E 's:/+$::'
}

build_staging() {
    local inc ex n_inc
    n_inc=$(read_allowlist + | grep -c . || true)
    if [[ "$n_inc" -eq 0 ]]; then
        report STOP allowlist "allowlist が空 ($ALLOWLIST)"
        stop_unless_dry_run
        return 0
    fi
    while IFS= read -r inc; do
        [[ -z "$inc" ]] && continue
        if [[ ! -e "${SOT_DIR}/${inc}" ]]; then
            report STOP allowlist "include が実在しない: $inc"
            stop_unless_dry_run
            continue
        fi
        mkdir -p "${STAGING_DIR}/$(dirname "$inc")"
        # node_modules と .git は常に対象外にする
        rsync -a --exclude node_modules --exclude .git "${SOT_DIR}/${inc}" "${STAGING_DIR}/$(dirname "$inc")/"
    done < <(read_allowlist +)
    while IFS= read -r ex; do
        [[ -z "$ex" ]] && continue
        rm -rf "${STAGING_DIR:?}/${ex}"
    done < <(read_allowlist -)
    report PASS allowlist "include ${n_inc} 件、staging の file $(staging_files | wc -l | tr -d ' ') 件"
}

# -----------------------------------------------------------------------------
# git が追跡していない file を staging から削除する。生成物 (bytecode cache、build 成果物)
# が allowlist の dir に紛れても公開しない。SoT が git repo でないときは判定を skip する
# -----------------------------------------------------------------------------
prune_untracked() {
    local tracked f n=0
    tracked="$(git -C "$SOT_DIR" ls-files 2>/dev/null || true)"
    if [[ -z "$tracked" ]]; then
        report INFO tracked "SoT が git repo でないため追跡の判定を skip する"
        return 0
    fi
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        if ! grep -qxF "$f" <<<"$tracked"; then
            rm -f "${STAGING_DIR:?}/${f}"
            n=$((n + 1))
        fi
    done < <(staging_files)
    # 空になった dir も削除する (bytecode cache の dir 等が残存しないようにする)
    find "$STAGING_DIR" -type d -empty -delete 2>/dev/null || true
    report PASS tracked "git 管理外の ${n} file を staging から削除した"
}

# staging 内の file 一覧 (相対 path)
staging_files() {
    (cd "$STAGING_DIR" && find . -type f | sed 's:^\./::' | sort)
}

# staging 内の text file 一覧 (置換と検査の対象。binary は除く)
staging_text_files() {
    (cd "$STAGING_DIR" && find . -type f -exec grep -Il '' {} + 2>/dev/null | sed 's:^\./::' | sort)
}

# -----------------------------------------------------------------------------
# 置換 rule。"<from>\t<to>" を上から順に適用する。$HOME は literal を実際の home に展開する
# -----------------------------------------------------------------------------
apply_replace_rules() {
    local from to n=0
    local -a files
    [[ -f "$REPLACE_RULES" ]] || { report INFO replace "置換 rule なし"; return 0; }
    # file 名の空白で分割されないよう、一覧を array に読んで perl の引数に展開する。
    # rule ごとに 1 回だけ perl を起動する (file ごとに起動すると rule 数 x file 数の process になる)。
    # macOS 既定の bash 3.2 に mapfile が無いので while read で array を作る
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        files+=("$line")
    done < <(staging_text_files)
    [[ "${#files[@]:-0}" -eq 0 ]] && return 0
    while IFS=$'\t' read -r from to; do
        [[ -z "$from" || "$from" == \#* ]] && continue
        from="${from//\$HOME/$HOME}"
        # from / to は path の "/" や正規表現の記号を含むので、perl の式に埋め込まず env で渡す
        # shellcheck disable=SC2016  # $ENV{...} は perl 側で展開する
        (cd "$STAGING_DIR" && PE_FROM="$from" PE_TO="$to" perl -pi -e 's/\Q$ENV{PE_FROM}\E/$ENV{PE_TO}/g' "${files[@]}")
        n=$((n + 1))
    done < "$REPLACE_RULES"
    report PASS replace "置換 rule ${n} 件を適用"
}

# -----------------------------------------------------------------------------
# staging (claude-code/ 配下) と root staging (README / LICENSE) の両方に同じ grep を当てる。
# hit の file 名は公開 repo での path と同じ形にする
scan_secret_dirs() {
    local dir
    for dir in "$STAGING_DIR" "$ROOT_STAGING"; do
        [[ -d "$dir" ]] || continue
        if [[ "$dir" == "$STAGING_DIR" ]]; then
            (cd "$dir" && "$@" 2>/dev/null | sed "s:^\./:${PUBLISH_SUBDIR}/:") || true
        else
            (cd "$dir" && "$@" 2>/dev/null | sed 's:^\./::') || true
        fi
    done
}

# 秘匿検査。term list 2 file の語と固定 pattern (個人 home の絶対 path / ghq 配下 / mail address) を
# staging 全体に当てる。hit 1 件でも停止する
# -----------------------------------------------------------------------------
check_secrets() {
    local terms hits fixed_hits
    terms=$( { load_terms "$SOCIAL_HIT_TERM_FILE"; load_terms "$PRIVATE_TERM_FILE"; } | sort -u)
    hits=""
    if [[ -n "$terms" ]]; then
        # term は file へ書き出す。process substitution は pipe なので、
        # 2 つ目の dir を検査する grep が空の入力を読む
        local term_file
        term_file="$(mktemp "${TMPDIR:-/tmp}/publish-terms.XXXXXX")"
        printf '%s\n' "$terms" > "$term_file"
        hits=$(scan_secret_dirs grep -rnoF -f "$term_file" .)
        rm -f "$term_file"
    fi
    fixed_hits=$(scan_secret_dirs grep -rnoE -e "$HOME" -e '<ghq-root>/' -e '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z0-9.-]*[A-Za-z]{2,}' .)
    if [[ -z "$hits" && -z "$fixed_hits" ]]; then
        report PASS secrets "term と固定 pattern の hit 0 件"
        return 0
    fi
    report STOP secrets "hit あり (file:line:語)"
    { [[ -n "$hits" ]] && printf '%s\n' "$hits"; [[ -n "$fixed_hits" ]] && printf '%s\n' "$fixed_hits"; } | sed 's/^/      /'
    stop_unless_dry_run
}

# -----------------------------------------------------------------------------
# manifest。公開 repo 内の .publish-manifest.json に、前回 export した file の一覧と
# SoT の commit SHA と export 日時を記録する
# -----------------------------------------------------------------------------
manifest_path() {
    printf '%s\n' "${CLONE_DIR}/${MANIFEST_NAME}"
}

# manifest が壊れていれば停止する。manifest が無い状態と区別して報告する
check_manifest_valid() {
    local m
    m="$(manifest_path)"
    [[ -f "$m" ]] || return 0
    if ! jq -e . "$m" >/dev/null 2>&1; then
        report STOP manifest "manifest が壊れている (JSON として読めない): $m"
        stop_unless_dry_run
        return 1
    fi
    return 0
}

manifest_files() {
    local m
    m="$(manifest_path)"
    [[ -f "$m" ]] || return 0
    jq -r '.files[]? // empty' "$m" 2>/dev/null || true
}

manifest_sot_sha() {
    local m
    m="$(manifest_path)"
    [[ -f "$m" ]] || return 0
    jq -r '.sot_sha? // empty' "$m" 2>/dev/null || true
}

write_manifest() {
    local sha
    sha="$(sot_sha)"
    staging_files | jq -R -s --arg sha "$sha" --arg at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        '{sot_sha: $sha, exported_at: $at, files: (split("\n") | map(select(length > 0)))}' \
        > "$(manifest_path)"
}

sot_sha() {
    git -C "$SOT_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown\n'
}

sot_short_sha() {
    git -C "$SOT_DIR" rev-parse --short HEAD 2>/dev/null || printf 'unknown\n'
}

sot_version() {
    [[ -f "${SOT_DIR}/VERSION" ]] && cat "${SOT_DIR}/VERSION" || printf 'unknown\n'
}

# -----------------------------------------------------------------------------
# 初出 file。manifest に無い file を初出として扱う。export は初出があれば停止し、
# --accept-new を付けた実行だけが続行する (DD)。--init と --dry-run は停止しない
# -----------------------------------------------------------------------------
check_new_files() {
    local prev new_list n
    if ! check_manifest_valid; then
        report INFO new-files "manifest が壊れているため初出 file を判定できない"
        return 0
    fi
    prev="$(manifest_files)"
    if [[ -z "$prev" ]]; then
        n=$(staging_files | wc -l | tr -d ' ')
        if [[ "$MODE" == "export" && "$ACCEPT_NEW" -eq 0 ]]; then
            report STOP new-files "manifest が無く、全 ${n} file が初出 (--accept-new が必要)"
            stop_unless_dry_run
        else
            report INFO new-files "manifest なし。全 ${n} file を初出として export する"
        fi
        return 0
    fi
    new_list=$(comm -23 <(staging_files) <(printf '%s\n' "$prev" | sort) || true)
    n=$(printf '%s\n' "$new_list" | grep -c . || true)
    if [[ "$n" -eq 0 ]]; then
        report PASS new-files "初出 file 0 件"
        return 0
    fi
    if [[ "$MODE" == "export" && "$ACCEPT_NEW" -eq 0 ]]; then
        report STOP new-files "初出 file ${n} 件 (--accept-new が必要)"
        printf '%s\n' "$new_list" | sed 's/^/      /'
        stop_unless_dry_run
    else
        report INFO new-files "初出 file ${n} 件"
        printf '%s\n' "$new_list" | sed 's/^/      /'
    fi
}

# -----------------------------------------------------------------------------
# 公開 repo の local clone。無ければ clone する。--init 以外では clone できないときに停止する
# -----------------------------------------------------------------------------
remote_url() {
    if [[ -n "$REMOTE_PATH" ]]; then
        printf '%s\n' "$REMOTE_PATH"
    else
        printf 'https://github.com/%s/%s.git\n' "$GITHUB_OWNER" "$PUBLISH_NAME"
    fi
}

ensure_clone() {
    if [[ -d "${CLONE_DIR}/.git" ]]; then
        report PASS clone "既存の clone を使う: $CLONE_DIR"
        return 0
    fi
    if [[ "$MODE" != "init" ]]; then
        report STOP clone "公開 repo の clone が無い ($CLONE_DIR)。--init が必要"
        stop_unless_dry_run
        return 1
    fi
    mkdir -p "$(dirname "$CLONE_DIR")"
    git clone "$(remote_url)" "$CLONE_DIR" 2>&1 | sed 's/^/      /'
    # 空 repo を clone した直後は commit が無いので、branch 名を main に定める。
    # 既に main がある repo では HEAD を動かさない (checkout 済みの内容と食い違う)
    if ! git -C "$CLONE_DIR" rev-parse --verify --quiet main >/dev/null; then
        git -C "$CLONE_DIR" symbolic-ref HEAD refs/heads/main
    fi
    report PASS clone "clone した: $CLONE_DIR"
}

create_remote_repo() {
    if [[ -n "$REMOTE_PATH" ]]; then
        report INFO github "--remote 指定のため repo の作成を skip する"
        return 0
    fi
    if gh repo view "${GITHUB_OWNER}/${PUBLISH_NAME}" >/dev/null 2>&1; then
        report INFO github "repo は既にある: ${GITHUB_OWNER}/${PUBLISH_NAME}"
        return 0
    fi
    gh repo create "${GITHUB_OWNER}/${PUBLISH_NAME}" --private \
        --description "Claude Code の設定一式 (ai-tools から選別 export)" 2>&1 | sed 's/^/      /'
    report PASS github "private repo を作成した: ${GITHUB_OWNER}/${PUBLISH_NAME}"
}

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# 公開 repo の root に置く README と LICENSE を staging へ copy する。置換 rule は
# 当てない。README は公開するために手で書く file なので、個人 path が入っていたら
# 書き換えるのでなく秘匿検査で止めて書き手に直させる (置換すると owner 名を含む
# clone URL まで書き換わる)
# -----------------------------------------------------------------------------
stage_root_files() {
    local n=0
    mkdir -p "$ROOT_STAGING"
    if [[ -f "$README_SRC" ]]; then
        cp "$README_SRC" "${ROOT_STAGING}/README.md"
        n=$((n + 1))
    fi
    if [[ -f "$LICENSE_SRC" ]]; then
        cp "$LICENSE_SRC" "${ROOT_STAGING}/LICENSE"
        n=$((n + 1))
    fi
    report PASS root-files "root に置く ${n} file を検査の対象にした"
}

# clone の内容を staging で置き換える。.git と manifest 以外を削除してから copy するので、
# allowlist から除いた file は公開 repo からも削除される (DD 決定 3)
# -----------------------------------------------------------------------------
sync_to_clone() {
    local entry
    while IFS= read -r entry; do
        [[ -z "$entry" || "$entry" == ".git" || "$entry" == "$MANIFEST_NAME" ]] && continue
        rm -rf "${CLONE_DIR:?}/${entry}"
    done < <(cd "$CLONE_DIR" && ls -A)
    mkdir -p "${CLONE_DIR}/${PUBLISH_SUBDIR}"
    (cd "$STAGING_DIR" && rsync -a ./ "${CLONE_DIR}/${PUBLISH_SUBDIR}/")
    [[ -f "${ROOT_STAGING}/README.md" ]] && cp "${ROOT_STAGING}/README.md" "${CLONE_DIR}/README.md"
    [[ -f "${ROOT_STAGING}/LICENSE" ]] && cp "${ROOT_STAGING}/LICENSE" "${CLONE_DIR}/LICENSE"
    report PASS sync "clone を staging で置き換えた ($(staging_files | wc -l | tr -d ' ') file)"
}

# -----------------------------------------------------------------------------
# commit と push。差分が無ければ commit を作らない。前回の push が失敗して local に
# commit が保持されているときは、差分が無くても push だけを試す
# -----------------------------------------------------------------------------
commit_and_push() {
    local msg
    # manifest は公開する内容に差分があるときだけ更新する。export 日時を毎回書き換えると、
    # 同じ SoT の commit を 2 回 export したときに日時だけの commit ができる
    git -C "$CLONE_DIR" add -A
    if git -C "$CLONE_DIR" diff --cached --quiet; then
        report INFO commit "差分なし"
    else
        write_manifest
        git -C "$CLONE_DIR" add -A
        msg="$(printf 'ai-tools %s (%s) の設定を反映する' "$(sot_version)" "$(sot_short_sha)")"
        git -C "$CLONE_DIR" commit -q -m "$msg"
        report PASS commit "$msg"
    fi
    # 差分が無いときも push を試す。前回の push が失敗して local に commit が保持されていれば、
    # この実行で push だけが済む。push 済みなら何も送らずに成功する
    if git -C "$CLONE_DIR" push -q origin HEAD:refs/heads/main 2>&1 | sed 's/^/      /'; then
        report PASS push "push した"
    else
        report STOP push "push に失敗した (commit は local clone に保持される。次回は push だけで済む)"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# --status。manifest が記録した SoT の SHA と現在の HEAD の差を表示する。
# term list が未整備でも実行できる
# -----------------------------------------------------------------------------
cmd_status() {
    local prev now n days
    print_header "publish-export (status) 公開 repo=${PUBLISH_NAME}"
    if [[ ! -d "${CLONE_DIR}/.git" ]]; then
        print_error "公開 repo の clone が無い ($CLONE_DIR)。--init が必要"
        return 1
    fi
    check_manifest_valid || return 1
    prev="$(manifest_sot_sha)"
    now="$(sot_sha)"
    if [[ -z "$prev" ]]; then
        report INFO status "manifest が無い (未 export)"
        return 0
    fi
    if [[ "$prev" == "$now" ]]; then
        report PASS status "SoT と同じ commit を export 済み ($(sot_short_sha))"
        return 0
    fi
    if ! git -C "$SOT_DIR" rev-parse --verify --quiet "$prev" >/dev/null; then
        report INFO status "manifest の SHA (${prev:0:8}) が SoT に無い (rebase で消えた履歴の可能性)"
        return 0
    fi
    n=$(git -C "$SOT_DIR" rev-list --count "${prev}..HEAD" 2>/dev/null || printf '?')
    days=$(git -C "$SOT_DIR" log -1 --format=%cr "$prev" 2>/dev/null || printf '不明')
    report INFO status "未 export の commit ${n} 件 (前回の export は ${days})"
}

# -----------------------------------------------------------------------------
main() {
    if [[ "$MODE" == "status" ]]; then
        cmd_status
        exit 0
    fi

    if [[ -z "$STAGING_DIR" ]]; then
        STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/publish-export.XXXXXX")"
        trap 'rm -rf "$STAGING_DIR" ${ROOT_STAGING:+"$ROOT_STAGING"}' EXIT
    else
        # --staging は毎回空から作る。既存 dir を削除するので、
        # 絶対 path に解決してから root と home と SoT 配下を拒否する。
        # 比較する両辺を pwd -P で正規化する (/var と /private/var のような symlink の差で
        # 同じ dir が別の文字列になる)
        local home_real
        mkdir -p "$STAGING_DIR"
        STAGING_DIR="$(cd "$STAGING_DIR" && pwd -P)"
        home_real="$(cd "$HOME" && pwd -P)"
        case "$STAGING_DIR" in
            / | "$home_real" | "$SOT_DIR" | "$SOT_DIR"/*)
                print_error "--staging に指定できない path: $STAGING_DIR"
                exit 2
                ;;
        esac
        rm -rf "${STAGING_DIR:?}"
        mkdir -p "$STAGING_DIR"
    fi
    STAGING_DIR="$(cd "$STAGING_DIR" && pwd -P)"
    # root staging は staging と同じ寿命にする (--staging 指定時は検査後も残す)
    ROOT_STAGING="${STAGING_DIR}.root"
    rm -rf "${ROOT_STAGING:?}"

    print_header "publish-export (${MODE}) SoT=${SOT_DIR}"
    if [[ -n "$(git -C "$SOT_DIR" status --porcelain 2>/dev/null)" ]]; then
        report INFO sot-dirty "SoT に未 commit の変更がある (commit message の SHA は HEAD を指す)"
    fi
    check_term_lists
    build_staging
    prune_untracked
    apply_replace_rules
    stage_root_files
    check_secrets

    # 秘匿検査を通過してから公開 repo に接続する。init は repo の作成も行う
    if [[ "$MODE" == "init" ]]; then
        [[ "$STOP_COUNT" -eq 0 ]] || { print_error "停止条件に該当した判定: ${STOP_COUNT} 件"; exit 1; }
        create_remote_repo
    fi
    if [[ "$MODE" == "init" || "$MODE" == "export" ]]; then
        ensure_clone || true
    fi
    check_new_files

    if [[ "$STOP_COUNT" -gt 0 ]]; then
        print_error "停止条件に該当した判定: ${STOP_COUNT} 件"
        exit 1
    fi

    if [[ "$MODE" == "dry-run" ]]; then
        print_success "全判定を通過 (staging: ${STAGING_DIR}$([[ $KEEP_STAGING -eq 1 ]] || printf ' は終了時に削除'))"
        exit 0
    fi

    sync_to_clone
    commit_and_push || exit 1
    print_success "公開 repo を更新した ($CLONE_DIR)"
}

main
