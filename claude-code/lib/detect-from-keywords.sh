#!/usr/bin/env bash
# =============================================================================
# Detect Technology Stack from Prompt Keywords
# user-prompt-submit.sh から分離（保守性向上）
# Performance optimization: キャッシング機構追加
# =============================================================================

set -euo pipefail

# キャッシュディレクトリ
CACHE_DIR="${HOME}/.claude/cache"
CACHE_FILE="${CACHE_DIR}/keyword-patterns.json"
CACHE_MAX_ENTRIES=100

# キャッシュの初期化
_init_cache() {
  if [ ! -d "$CACHE_DIR" ]; then
    mkdir -p "$CACHE_DIR"
  fi

  # -s は「存在し、かつ空でない」を builtin で見る。0 byte cache を欠損扱いにして
  # 書き直すのが要点で、-f だと 0 byte file が残り続けて cache が永久に miss する
  if [ ! -s "$CACHE_FILE" ]; then
    echo '{}' > "$CACHE_FILE"
  fi
}

# プロンプトのハッシュ値を計算
_hash_prompt() {
  local prompt=$1
  echo -n "$prompt" | md5sum 2>/dev/null || echo -n "$prompt" | md5
}

# キャッシュから検出結果を取得
# Returns: 0 if cache hit, 1 if cache miss
_get_cached_result() {
  local prompt_hash=$1
  local -n _cache_langs=$2
  local -n _cache_skills=$3

  if [ ! -f "$CACHE_FILE" ]; then
    return 1
  fi

  # 単一 jq invocation でキャッシュエントリ取得 + フィールド展開（fork 2→1）
  local jq_out
  jq_out=$(jq -r --arg h "$prompt_hash" '
    .[$h] // empty | if . == null or . == "" then empty else "\(.langs // "")\u001f\(.skills // "")" end
  ' "$CACHE_FILE" 2>/dev/null) || true
  if [ -z "$jq_out" ]; then
    return 1
  fi

  # tab は先頭の空 field を落とすため、非 whitespace 区切りで一括展開する
  local cached_langs_str cached_skills_str
  IFS=$'\x1f' read -r cached_langs_str cached_skills_str <<< "$jq_out"

  if [ -n "$cached_langs_str" ]; then
    IFS=',' read -ra lang_array <<< "$cached_langs_str"
    for lang in "${lang_array[@]}"; do
      _cache_langs["$lang"]=1
    done
  fi

  if [ -n "$cached_skills_str" ]; then
    IFS=',' read -ra skill_array <<< "$cached_skills_str"
    for skill in "${skill_array[@]}"; do
      _cache_skills["$skill"]=1
    done
  fi

  return 0
}

# 検出結果をキャッシュに保存
_save_to_cache() {
  local prompt_hash=$1
  local langs=$2
  local skills=$3

  _init_cache

  # 新しいエントリを作成
  local new_entry
  new_entry=$(jq -n \
    --arg l "$langs" \
    --arg s "$skills" \
    '{langs: $l, skills: $s, timestamp: now}')

  # tmp 名に PID を含める。固定名だと並列に走った hook 同士が同じ tmp を truncate し合い、
  # 中途半端な内容を mv した結果 cache が壊れる (2026-08-29 に 0 byte 化を実踏)
  local tmp_file="${CACHE_FILE}.$$.tmp"

  # 単一 jq invocation: エントリ追加 + LRU eviction を同時処理（fork 3→1）
  local max="$CACHE_MAX_ENTRIES"
  jq \
    --arg hash "$prompt_hash" \
    --argjson entry "$new_entry" \
    --argjson max "$max" \
    '
      .[$hash] = $entry |
      if length > $max then
        to_entries | sort_by(.value.timestamp) | reverse | .[0:$max] | from_entries
      else . end
    ' \
    "$CACHE_FILE" 2>/dev/null > "$tmp_file" && mv "$tmp_file" "$CACHE_FILE" || rm -f "$tmp_file"
}

# スキル名マッピング（旧名→新名+パラメータ）
# Phase2-5 スキル統合で追加
declare -g -A SKILL_ALIASES=(
)

# スキルエイリアス変換関数
_apply_skill_aliases() {
  local -n _skills_ref=$1
  local -A new_skills=()
  
  set +u
  for skill in "${!_skills_ref[@]}"; do
    if [[ -n "${SKILL_ALIASES[$skill]:-}" ]]; then
      # エイリアス検出: 新スキル名+環境変数設定に変換
      IFS=':' read -ra parts <<< "${SKILL_ALIASES[$skill]}"
      local new_skill="${parts[0]}"
      new_skills["$new_skill"]=1
      
      # 環境変数設定（パラメータ）
      for ((i=1; i<${#parts[@]}; i++)); do
        IFS='=' read -r var_name var_value <<< "${parts[$i]}"
        export "$var_name=$var_value"
      done
    else
      # エイリアスなし: そのまま保持
      new_skills["$skill"]=1
    fi
  done
  set -u

  # 元の配列を上書き
  set +u
  _skills_ref=()
  for skill in "${!new_skills[@]}"; do
    _skills_ref["$skill"]=1
  done
  set -u
}

# キーワードパターンから技術スタックを検出
# Args:
#   $1: prompt_lower (lowercase prompt)
#   $2: detected_langs (associative array name)
#   $3: detected_skills (associative array name)
#   $4: additional_context (string variable name)
detect_from_keywords() {
  local prompt_lower=$1
  local -n _langs=$2
  local -n _skills=$3
  local -n _context=$4

  # スラッシュコマンドはスキル側でルーティングするため検出スキップ
  if [[ "$prompt_lower" =~ ^/ ]]; then
    return 0
  fi

  # キャッシュチェック
  local prompt_hash
  prompt_hash=$(_hash_prompt "$prompt_lower")
  local prose_rewrite_request=0
  if echo "$prompt_lower" | grep -qE '読みやすさ|読みやす|文体|日本語.*(修正|推敲|チェック)|文章.*(修正|推敲|整え)|jp-fix'; then
    prose_rewrite_request=1
  fi
  local cache_hit=0
  if _get_cached_result "$prompt_hash" "$2" "$3"; then
    cache_hit=1
  fi

  if [ "$cache_hit" -eq 0 ]; then
    # キーワードパターンテーブル（pattern → language:skill）
    declare -A keyword_patterns=(
    ['go|golang|\.go|go\.mod']="golang:backend-dev"
    ['python|\.py|pip|poetry|pyproject\.toml|requirements\.txt|django|fastapi']="python:"
    ['rust|\.rs|cargo|cargo\.toml|tokio|axum']="rust:"
    ['typescript|\.ts|\.tsx|tsconfig']="typescript:backend-dev"
    ['react|next\\.js|nextjs|\\.jsx']="react:react-best-practices"
    ['tailwind']="tailwind:"
    ['review|レビュー|確認して|refactor|リファクタ']=":comprehensive-review"
    ['security|セキュリティ|脆弱性']=":comprehensive-review"
    ['test|テスト|doc|ドキュメント']=":comprehensive-review"
    ['api.*design|rest.*api|graphql']=":api-design"
    ['microservices|マイクロサービス|monorepo']=":microservices-monorepo"
    ['brainstorm|ブレスト|設計相談|アイデア出し']=":superpowers:brainstorm"
    ['tdd|test.*driven|red.*green.*refactor|テスト駆動']=":superpowers:test-driven-development"
    ['systematic.*debug|根本原因|デバッグ.*体系']=":superpowers:systematic-debugging"
    ['async.*job|queue|worker|job.*pattern|非同期|キュー|ワーカー|dlq|dead.*letter']=":backend-dev"
    )

    # set -u対応
    set +u
    for keywords in "${!keyword_patterns[@]}"; do
      if echo "$prompt_lower" | grep -qE "$keywords"; then
        IFS=':' read -r lang skill <<< "${keyword_patterns[$keywords]}"
        [ -n "$lang" ] && _langs["$lang"]=1
        [ -n "$skill" ] && _skills["$skill"]=1
      fi
    done
    set -u
  fi

  # 明示的な文章推敲要求は、汎用の review / doc 検出より優先する。
  # 「読みやすさチェックして修正」のような依頼に comprehensive-review を
  # 併発させると、code review の完了報告や工程説明が文章推敲へ混入する
  if [ "$prose_rewrite_request" -eq 1 ]; then
    unset '_skills[comprehensive-review]'
    unset '_skills[writing-knowledge]'
    _skills["jp-fix"]=1
  fi

  # Serena検出（特殊処理）
  if echo "$prompt_lower" | grep -qE '/serena|serena.*mcp|memory'; then
    _context="${_context}\\n- 🧠 Serena MCP detected: Use mcp__serena__* tools for project analysis"
  fi

  # 執筆意図検出（ヒト向け doc の窓口 skill を選択）
  # 対象: Notion/Design Doc/PRD/PR description/issue本文/RCA/記事/まとめ
  # 最適化: 先頭60文字 case で早期判定 → カテゴリ別サブ regex で確定（300+ OR 単一 eval を回避）
  local _writing_detected=0
  local _ph="${prompt_lower:0:60}"
  case "$_ph" in
    *書*|*まとめ*|*ドラフト*|*draft*|*notion*|*記事*|*レポート*|*議事録*|*報告*|*執筆*|*文章*|*pr*|*prd*|*rca*|*adr*|*spec*|*ears*|*プレス*|*お知らせ*|*案内*|*提案*|*振り返*|*retro*)
      # カテゴリ A: 執筆動詞
      if echo "$prompt_lower" | grep -qE '書いて|まとめて|ドラフト|draft|執筆|文章'; then
        _writing_detected=1
      # カテゴリ B: ドキュメント種別
      elif echo "$prompt_lower" | grep -qE 'design.?doc|デザインドック|prd|要件定義|要件定|notion|記事|レポート|議事録|報告書'; then
        _writing_detected=1
      # カテゴリ C: PR/Issue/RCA 系
      elif echo "$prompt_lower" | grep -qE 'pr.?description|pr本文|issue本文|rca|障害報告'; then
        _writing_detected=1
      # カテゴリ D: 振り返り/リリース/提案
      elif echo "$prompt_lower" | grep -qE '振り返り|retrospective|プレスリリース|お知らせ|案内文|提案書'; then
        _writing_detected=1
      # カテゴリ E: 技術仕様/ADR/基準
      elif echo "$prompt_lower" | grep -qE 'adr|技術選定|意思決定記録|ears|受け入れ基準|productspec|techspec|技術仕様書|プロダクト仕様'; then
        _writing_detected=1
      fi
      ;;
  esac
  if [ "$_writing_detected" -eq 1 ] && [ "$prose_rewrite_request" -eq 0 ]; then
    # skill 名は systemMessage 止まりで model に渡らないため、規範本文でなく窓口への誘導を context へ入れる
    _skills["writing-knowledge"]=1
    _context="${_context}\\n- 📝 外向き文章: skills/writing-knowledge/SKILL.md の判定表で種別を決め、該当 guideline を Read する"
  fi

  # 検出結果をキャッシュに保存（set -u対応）
  local langs_str=""
  set +u
  for lang in "${!_langs[@]}"; do
    langs_str="${langs_str}${lang},"
  done
  set -u
  langs_str="${langs_str%,}"

  local skills_str=""
  set +u
  for skill in "${!_skills[@]}"; do
    skills_str="${skills_str}${skill},"
  done
  set -u
  skills_str="${skills_str%,}"

  if [ "$cache_hit" -eq 0 ]; then
    _save_to_cache "$prompt_hash" "$langs_str" "$skills_str"
  fi
  
  # スキルエイリアス変換適用
  _apply_skill_aliases _skills
}

# Export functions
export -f detect_from_keywords
export -f _apply_skill_aliases
export -f _init_cache
export -f _hash_prompt
export -f _get_cached_result
export -f _save_to_cache
