#!/usr/bin/env bash

set -euo pipefail

EXPECTED_REPO_ROOT=""
CURRENT_HEAD=""
CURRENT_SESSION=""
MODE=""
HANDOFF_PATH=""

usage() {
    cat <<'EOF'
Usage: validate-investigation-handoff.sh --mode source|implementation --expected-repo-root PATH --current-head SHA --current-session ID <absolute-handoff-path>

Validate a READY_FOR_IMPLEMENTATION investigation handoff without modifying it.

Options:
  --mode MODE                Require source or implementation session semantics
  --expected-repo-root PATH  Reject a different source_repo_root
  --current-head SHA         Reject a different git_head
  --current-session ID       Current SessionStart current_session_id
  -h, --help                 Show this help
EOF
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

require_option_value() {
    local option="$1"
    local value="${2:-}"

    [[ -n "$value" ]] || fail "$option requires a non-empty value"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            require_option_value "$1" "${2:-}"
            MODE="$2"
            shift 2
            ;;
        --expected-repo-root)
            require_option_value "$1" "${2:-}"
            EXPECTED_REPO_ROOT="$2"
            shift 2
            ;;
        --current-head)
            require_option_value "$1" "${2:-}"
            CURRENT_HEAD="$2"
            shift 2
            ;;
        --current-session)
            require_option_value "$1" "${2:-}"
            CURRENT_SESSION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            fail "unknown option: $1"
            ;;
        *)
            [[ -z "$HANDOFF_PATH" ]] || fail "only one handoff path is allowed"
            HANDOFF_PATH="$1"
            shift
            ;;
    esac
done

[[ -n "$HANDOFF_PATH" ]] || { usage >&2; fail "handoff path is required"; }
[[ "$HANDOFF_PATH" == /* ]] || fail "handoff path must be absolute: $HANDOFF_PATH"
[[ -n "$MODE" ]] || fail "--mode is required"
[[ "$MODE" == "source" || "$MODE" == "implementation" ]] \
    || fail "--mode must be source or implementation: $MODE"
[[ -n "$EXPECTED_REPO_ROOT" ]] || fail "--expected-repo-root is required"
[[ -n "$CURRENT_HEAD" ]] || fail "--current-head is required"
[[ -n "$CURRENT_SESSION" ]] || fail "--current-session is required"
[[ -f "$HANDOFF_PATH" ]] || fail "handoff file not found: $HANDOFF_PATH"
[[ -r "$HANDOFF_PATH" ]] || fail "handoff file is not readable: $HANDOFF_PATH"

metadata_value() {
    local key="$1"

    awk -v key="$key" '
        index($0, key ":") == 1 {
            value = substr($0, length(key) + 2)
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            print value
        }
    ' "$HANDOFF_PATH"
}

require_metadata() {
    local key="$1"
    local count
    local value

    count="$(awk -v key="$key" 'index($0, key ":") == 1 { count++ } END { print count + 0 }' "$HANDOFF_PATH")"
    [[ "$count" -eq 1 ]] || fail "metadata '$key' must appear exactly once"

    value="$(metadata_value "$key")"
    [[ -n "$value" ]] || fail "metadata '$key' must not be empty"
}

section_has_content() {
    local section="$1"

    awk -v heading="## $section" '
        $0 == heading {
            in_section = 1
            next
        }
        in_section && /^##[[:space:]]/ {
            exit found ? 0 : 1
        }
        in_section {
            line = $0
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (line ~ /<!--/) {
                in_comment = 1
            }
            if (in_comment) {
                if (line ~ /-->/) {
                    in_comment = 0
                }
                next
            }
            if (line == "" || line ~ /^```[[:alnum:]_-]*$/) {
                next
            }
            found = 1
        }
        END {
            if (!in_section || !found) {
                exit 1
            }
        }
    ' "$HANDOFF_PATH"
}

require_section() {
    local section="$1"
    local count

    count="$(awk -v heading="## $section" '$0 == heading { count++ } END { print count + 0 }' "$HANDOFF_PATH")"
    [[ "$count" -eq 1 ]] || fail "section '$section' must appear exactly once"
    section_has_content "$section" || fail "section '$section' must contain content"
}

has_ready_template_marker() {
    awk '
        BEGIN {
            metadata["state"] = 1
            metadata["source_session"] = 1
            metadata["source_repo_root"] = 1
            metadata["source_branch"] = 1
            metadata["git_head"] = 1
            metadata["next_command"] = 1

            sections["scope"] = 1
            sections["out_of_scope"] = 1
            sections["requirements"] = 1
            sections["decisions"] = 1
            sections["evidence"] = 1
            sections["files_and_symbols"] = 1
            sections["implementation_steps"] = 1
            sections["verification_commands"] = 1
            sections["open_questions"] = 1
            sections["residual_risks"] = 1
        }
        /^##[[:space:]]/ {
            section = substr($0, 4)
            in_required_section = section in sections
        }
        {
            inspect = in_required_section
            for (key in metadata) {
                if (index($0, key ":") == 1) {
                    inspect = 1
                    break
                }
            }
            if (inspect && ($0 ~ /<!--|-->/ || $0 ~ /<[^<>]+>/)) {
                found = 1
            }
        }
        END {
            exit found ? 0 : 1
        }
    ' "$HANDOFF_PATH"
}

metadata_fields=(
    state
    source_session
    source_repo_root
    source_branch
    git_head
    next_command
)

section_fields=(
    scope
    out_of_scope
    requirements
    decisions
    evidence
    files_and_symbols
    implementation_steps
    verification_commands
    open_questions
    residual_risks
)

for field in "${metadata_fields[@]}"; do
    require_metadata "$field"
done

for field in "${section_fields[@]}"; do
    require_section "$field"
done

state="$(metadata_value state)"
source_session="$(metadata_value source_session)"
source_repo_root="$(metadata_value source_repo_root)"
git_head="$(metadata_value git_head)"
next_command="$(metadata_value next_command)"

[[ "$state" == "READY_FOR_IMPLEMENTATION" ]] \
    || fail "state must be READY_FOR_IMPLEMENTATION, got: $state"
if has_ready_template_marker; then
    fail "READY_FOR_IMPLEMENTATION handoff contains an unresolved angle-bracket placeholder or template marker"
fi
[[ "$source_repo_root" == /* ]] \
    || fail "source_repo_root must be an absolute path: $source_repo_root"
[[ "$git_head" =~ ^[[:xdigit:]]{40}$ ]] \
    || fail "git_head must be a 40-character git SHA: $git_head"
expected_next_command="/dev --handoff $HANDOFF_PATH"
[[ "$next_command" == "$expected_next_command" ]] \
    || fail "next_command must equal exactly: $expected_next_command"

if awk '
    /<!--/ { in_comment = 1 }
    !in_comment { print }
    in_comment && /-->/ { in_comment = 0 }
' "$HANDOFF_PATH" | grep -Eiq '(^|[^[:alnum:]_])UNRESOLVED_BLOCKER[[:space:]]*:'; then
    fail "handoff contains an UNRESOLVED_BLOCKER marker"
fi

normalize_root() {
    local path="$1"

    while [[ "$path" != "/" && "$path" == */ ]]; do
        path="${path%/}"
    done
    printf '%s\n' "$path"
}

expected_root="$(normalize_root "$EXPECTED_REPO_ROOT")"
artifact_root="$(normalize_root "$source_repo_root")"
[[ "$artifact_root" == "$expected_root" ]] \
    || fail "source_repo_root mismatch: artifact='$source_repo_root' expected='$EXPECTED_REPO_ROOT'"

[[ "$CURRENT_HEAD" =~ ^[[:xdigit:]]{40}$ ]] \
    || fail "--current-head must be a 40-character git SHA: $CURRENT_HEAD"
artifact_head_lower="$(printf '%s' "$git_head" | tr '[:upper:]' '[:lower:]')"
current_head_lower="$(printf '%s' "$CURRENT_HEAD" | tr '[:upper:]' '[:lower:]')"
[[ "$artifact_head_lower" == "$current_head_lower" ]] \
    || fail "git_head mismatch: artifact='$git_head' current='$CURRENT_HEAD'"

case "$MODE" in
    source)
        [[ "$CURRENT_SESSION" == "$source_session" ]] \
            || fail "source validation requires current session to equal source_session"
        ;;
    implementation)
        [[ "$CURRENT_SESSION" != "$source_session" ]] \
            || fail "implementation must run in a fresh session; current session equals source_session"
        ;;
esac

echo "OK: READY_FOR_IMPLEMENTATION handoff is valid: $HANDOFF_PATH"
