#!/usr/bin/env bash
# spec 型 Design Doc の機械判定 gate。/sdd-design Step 6 から呼ぶ。
# 判定 6 項目: (1) Implementation Surface の合計 1 行と表の行数の一致
#             (2) 未確定 marker と「決める時点 = 作業計画書作成前 / DD レビュー」の残存
#             (3) 「受け入れ条件」 / 振る舞い / 決定事項 の識別子・HTTP status (warn)
#             (4) 決定事項の表 cell 長 (160 字超は読めない)
#             (5) 分岐のある受け入れ条件が 2 行以上あるのに振る舞いの図も番号付き手順も無い (warn)
#             (6) 受け入れ条件と振る舞いに曖昧な形容 (適切に / 堅牢 等) が残っている (warn)
# 出力: 1 行 1 判定 (PASS / FAIL / WARN)。FAIL が 1 つでもあれば exit 1
set -u

usage() { echo "usage: dd-gate.sh <design-doc.md>" >&2; exit 2; }
[ $# -eq 1 ] && [ -f "$1" ] || usage
DD="$1"
fail=0

report() { # $1=PASS|FAIL|WARN $2=item $3=detail
  printf '%s  %s  %s\n' "$1" "$2" "$3"
  [ "$1" = FAIL ] && fail=1
  return 0
}

# 節の本文を取り出す。$1 = 見出しの正規表現 (## か ### の後)。次の同レベル以上の見出しまで
section() {
  awk -v pat="$1" '
    /^#+ / {
      l = match($0, /[^#]/) - 1
      if (on && l <= lvl) { exit }
      if (!on && $0 ~ pat) { on = 1; lvl = l; next }
    }
    on { print }
  ' "$DD"
}

# 表の data 行 (header と区切り行を除く) を数える。stdin = 節本文。$1 = 表の 1 列目 header 名 (その表だけ数える)
table_rows() {
  awk -v hdr="$1" '
    /^\|/ {
      if (!in_tbl) { if (index($0, "| " hdr) == 1 || $0 ~ "^\\| *" hdr " *\\|") { in_tbl = 1; next } else { next } }
      if ($0 ~ /^\| *-+/) next
      n++; next
    }
    in_tbl && !/^\|/ { exit }
    END { print n + 0 }
  '
}

# 振る舞いの節の見出し。template は節名を英語にする指定で (design-doc-spec-template.md 「外見」)、
# Section 6 の英語名は Proposed Design › Data Flow になる。日本語の節名だけで探すと、
# 規範どおりに書いた DD で節が 0 行になり、図があっても無いと判定する (2026-09-20 実踏)
BEHAVIOR_PAT='Behavior|振る舞い|Proposed Design'

# (1) 合計 1 行と表の行数
total_line=$(section '4\. Implementation Surface|Implementation Surface' | grep -m1 '^合計')
if [ -z "$total_line" ]; then
  report FAIL surface-total '合計 1 行が無い'
else
  api_total=$(printf '%s' "$total_line" | grep -oE 'API[^0-9]*[0-9]+ 本' | grep -oE '[0-9]+' | head -1)
  read_total=$(printf '%s' "$total_line" | grep -oE 'Read [0-9]+' | head -1 | grep -oE '[0-9]+')
  write_total=$(printf '%s' "$total_line" | grep -oE 'Write [0-9]+' | head -1 | grep -oE '[0-9]+')
  screen_total=$(printf '%s' "$total_line" | grep -oE '画面 [0-9]+' | grep -oE '[0-9]+')
  api_body=$(section 'Backend API')
  api_rows=$(printf '%s\n' "$api_body" | table_rows endpoint)
  api_read=$(printf '%s\n' "$api_body" | grep -c '^| `[^|]*| *Read ')
  api_write=$(printf '%s\n' "$api_body" | grep -c '^| `[^|]*| *Write ')
  fe_rows=$(section 'Frontend' | table_rows 画面)
  if [ "${api_total:-x}" = "$api_rows" ]; then report PASS surface-api "合計 ${api_total} 本 = 表 ${api_rows} 行"; else report FAIL surface-api "合計 ${api_total:-?} 本 / 表 ${api_rows} 行"; fi
  if [ "${read_total:-x}" = "$api_read" ] && [ "${write_total:-x}" = "$api_write" ]; then report PASS surface-rw "Read ${api_read} / Write ${api_write}"; else report FAIL surface-rw "合計 Read ${read_total:-?} / Write ${write_total:-?}、表 Read ${api_read} / Write ${api_write}"; fi
  if [ -z "$screen_total" ]; then report WARN surface-screen '合計に画面の数が無い'; elif [ "$screen_total" = "$fe_rows" ]; then report PASS surface-screen "画面 ${fe_rows}"; else report FAIL surface-screen "合計 画面 ${screen_total} / 表 ${fe_rows} 行"; fi
fi

# (2) 未確定の残存
pending=$(grep -c '【未確定' "$DD" || true)
if [ "$pending" -eq 0 ]; then report PASS open-marker '【未確定】marker 0'; else report FAIL open-marker "【未確定】marker ${pending} 件"; fi
oq_rows=$(section 'Open Questions|未確定事項' | grep '^| Q' | grep -v '| 確定' || true)
# 旧称「SPEC 作成前」で書かれた既存の DD も同じく判定する
oq_block=$(printf '%s\n' "$oq_rows" | grep -E '作業計画書作成前|SPEC 作成前|DD レビュー' | grep -vE '暫定決定|決定 [0-9]+|案 [A-Z]' | grep -c . || true)
if [ "$oq_block" -eq 0 ]; then report PASS open-deadline '決める時点 = 作業計画書作成前 / DD レビュー の未決 0'; else report FAIL open-deadline "作業計画書を止める未決 ${oq_block} 件"; fi

# (3) 識別子と HTTP status (warn)
spec_body=$( { section 'Acceptance Criteria|受け入れ条件'; section "$BEHAVIOR_PAT"; section 'Design Decisions|決定事項'; } )
ident=$(printf '%s\n' "$spec_body" | grep -cE '`[^`]*(/|\.go|\.vue|\.sql|\.ts)[^`]*`|\b(SELECT|INSERT|UPDATE|DELETE) \b' || true)
status=$(printf '%s\n' "$spec_body" | grep -cE '(^|[^0-9])(200|201|204|400|401|403|404|409|422|500)([^0-9]|$)' || true)
if [ "$ident" -eq 0 ]; then report PASS ident 'file path / SQL 0'; else report WARN ident "file path / SQL らしき行 ${ident}"; fi
if [ "$status" -eq 0 ]; then report PASS http-status 'HTTP status 0'; else report WARN http-status "HTTP status を含む行 ${status} (既存挙動の変更で明示した分は許容)"; fi

# (4) 決定事項の表 cell 長
long_cells=$(section 'Design Decisions|決定事項' | grep '^|' | grep -v '^| *-' | awk -F'|' '{ for (i = 2; i < NF; i++) if (length($i) > 160) c++ } END { print c + 0 }')
if [ "$long_cells" -eq 0 ]; then report PASS decision-cell '160 字超の cell 0'; else report FAIL decision-cell "160 字超の cell ${long_cells} (bullet に戻す)"; fi

# (5) 振る舞いの図 (warn)
# 分岐語の検出は語彙に依存して取りこぼしと誤検出の両方が発生するので FAIL にしない。
# 閾値 2 は「1 つの分岐なら条件の表 1 行で追える」という template の線引きに合わせた
# (`references/design-doc-spec-template.md` Section 6「条件の表 1 行では追えない場面に限る」)。
branch_rows=$(section 'Acceptance Criteria|受け入れ条件' \
  | grep '^|' | grep -v '^| *-' \
  | grep -cE '失敗|エラー|重複|同時|期限|キャンセル|取り消|再送|拒否|競合|上限|超え|できない' || true)
behavior_form=$(section "$BEHAVIOR_PAT" | grep -cE '^```mermaid|^[0-9]+\. ' || true)
if [ "$branch_rows" -lt 2 ]; then
  report PASS behavior-diagram "分岐のある条件 ${branch_rows} 行 (2 行未満は図の要否を判定しない)"
elif [ "$behavior_form" -gt 0 ]; then
  report PASS behavior-diagram "分岐のある条件 ${branch_rows} 行、振る舞いに図か番号付き手順あり"
else
  report WARN behavior-diagram "分岐のある条件 ${branch_rows} 行に対して振る舞いの図も番号付き手順も無い (sequence / state 図か番号付き手順を置く)"
fi

# (6) 曖昧な形容 (warn)
# 語彙に依存して取りこぼしと誤検出の両方が発生するので、behavior-diagram と同じく FAIL にしない。
# 「適切に処理する」の類は何を満たせば良いかの判断を実装者へ預けることになり、
# 受け入れ条件として機能しない (`commands/sdd-design.md` 「Bad Design Doc」)。
VAGUE_PAT='適切に|正しく|高速|堅牢|直感的|柔軟|十分|スムーズ'
vague=$( { section 'Acceptance Criteria|受け入れ条件'; section "$BEHAVIOR_PAT"; } | grep -cE "$VAGUE_PAT" || true)
if [ "$vague" -eq 0 ]; then report PASS vague-adjective '曖昧な形容 0'; else report WARN vague-adjective "曖昧な形容を含む行 ${vague} (測れる条件に書き換える)"; fi

exit $fail
