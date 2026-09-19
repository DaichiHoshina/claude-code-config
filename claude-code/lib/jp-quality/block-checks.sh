#!/usr/bin/env bash
# NG 語 block / chat 文体検査関数群 (jp-quality-check.sh から抽出)
# source してから使用する。GUARD_CLASS / MESSAGE / ADDITIONAL_CONTEXT / TOOL_NAME を参照・変更する。
# term-extraction.sh / structural-checks.sh に依存する

# 多重 source 防止
if [[ "${_JP_QUALITY_BLOCK_CHECKS_LOADED:-}" == "1" ]]; then
    return 0
fi
_JP_QUALITY_BLOCK_CHECKS_LOADED=1

# shellcheck source=structural-checks.sh
source "${BASH_SOURCE[0]%/*}/structural-checks.sh"

# 外向き text を AI語 + カタカナ造語チェックし、hit 時に Forbidden block をセットする
# 全 block category を一括収集して exit 2 + まとめて提示する (逐次 block 廃止)
# 呼び出し元: tool ごとの case 節
_block_if_ai_jargon() {
  local text="$1"
  local context_label="$2"  # "commit message" / "PR body" 等
  # 語彙・文長・句読点は意味の正否を判定できないため、既定では外向き操作を遮断しない。
  # 既定でも検出と log 記録までは行い、block と warn 通知だけを flag の内側に置く。
  # log を flag の内側に閉じると、遮断を有効にするか判断するための頻度データが永久に貯まらない
  local _jpq_enforce=0
  [[ "${JP_QUALITY_STYLE_ENFORCEMENT:-0}" == "1" ]] && _jpq_enforce=1
  # 辞書全 key を 1 pass で cache 化する (以降の _extract_term_list は fork 0)
  _preload_term_lists
  # 必須 key sanity check は exit 2 で落とすため、遮断が有効なときだけ走らせる
  if [[ "$_jpq_enforce" -eq 1 ]]; then
    _assert_required_keys

    # inject byte size 計測: 全 block list の合計抽出 byte 数を計算してログ出力
    local _inject_keys=("AI定型語" "カタカナ造語禁止" "難読漢語 (block)" "非日常英語 (block)" "弱い表現 (block)" "冗長表現 (block)" "AI段取り定型 (block)" "ヘッジ濫用 (block)" "過剰丁寧 (block)" "比喩・擬人化 (block)" "曖昧な汎用動詞 (block)" "くだけた話し言葉 (block)" "記号 (block)" "非公式専門用語 (block)")
    local _inject_total=0
    local _inject_key
    for _inject_key in "${_inject_keys[@]}"; do
      local _inject_terms
      _inject_terms=$(_extract_term_list "$_principles_file" "$_inject_key" 2>/dev/null || true)
      _inject_total=$(( _inject_total + ${#_inject_terms} ))
    done
    local _inject_status="ok"
    [[ "$_inject_total" -gt 1500 ]] && _inject_status="over"
    _append_jp_quality_inject_log "$context_label" "$_inject_total" "$_inject_status"
  fi

  # --- block category 定義 ---
  # 各要素: "key|label|guidance"
  # label: bats テスト互換の表示名 (例: "難読漢語 block")
  local _block_categories=(
    "AI定型語|AI定型語 block|AI定型語を削除または具体表現に置換してください"
    "カタカナ造語禁止|カタカナ造語 block|カタカナ造語を削除または説明的表現に置換してください"
    "難読漢語 (block)|難読漢語 block|難読漢語を平易な語に置換してください"
    "非日常英語 (block)|非日常英語 block|日常で使う英語または日本語に置換してください"
    "弱い表現 (block)|弱い表現 block|弱い表現を断定または「検証が必要」に置換してください"
    "冗長表現 (block)|冗長表現 block|冗長表現を短縮形に置換してください (例: することができる → できる、を行う → する)"
    "AI段取り定型 (block)|AI段取り定型 block|段取り定型を削除して内容を直接書いてください (まず/次に/最後に は番号 list で代替)"
    "ヘッジ濫用 (block)|ヘッジ濫用 block|ヘッジ語を削除して断定で書いてください (念のため/一応 は不要)"
    "過剰丁寧 (block)|過剰丁寧 block|過剰丁寧を削除して直接的に書いてください (chat では「確認してください」、外向き text では「確認してほしい」)"
    "比喩・擬人化 (block)|比喩・擬人化 block|動作や状態をそのまま書いてください (削除する / 使われていない / link されていない)"
    "曖昧な汎用動詞 (block)|曖昧な汎用動詞 block|意味の広い動詞を実際の処理を表す動詞に置き換えてください (出す→返す・表示する / 外す→削除する・無効化する / 持つ→保持する / 見る→確認する / 入れる→追加する / 切る→作成する)"
    "くだけた話し言葉 (block)|くだけた話し言葉 block|話し言葉の短縮形を削除し、敬体または動詞終止に開いてください (やっぱ→やはり / だよ→です・する)"
    "非公式専門用語 (block)|非公式専門用語 block|公式 doc に無い業界の口頭語です。語をやめて役割を日本語で書いてください (backing index → 外部キーの検査に利用される index / sad path → 失敗したときの経路 / race window → 競合が起きうる時間範囲)"
    "記号 (block)|記号 block|セクション記号 § を置き換えてください (見出し → ## 3. API設計 / 第○節 → Section 1・第1節 / 他 file の参照 → 見出し「口語の圧縮動詞」)"
  )

  # block hit: key → hit_words の連想配列
  declare -A _hit_by_key=()
  local _hit_words
  local _cat_entry _cat_key _cat_label _cat_guidance
  local _has_block=0

  # fast path: 全 category の語 union を 1 回の grep で検査し、hit ゼロ (大多数) なら per-key loop を省く。
  # 検査を既定でも走らせる以上、hit なしの経路を 9 fork から 1 fork に落とさないと書き込みのたびに待たされる
  local _fp_clean _fp_words=() _fp_any="" _fp_key _fp_word
  _fp_clean=$(_strip_code_blocks "$text")
  _fp_clean=$(printf '%s' "$_fp_clean" | sed -E 's/[A-Za-z0-9_.]+(-[A-Za-z0-9_.]+)+/ /g')
  for _cat_entry in "${_block_categories[@]}"; do
    _fp_key="${_cat_entry%%|*}"
    while IFS= read -r _fp_word; do
      [[ -n "$_fp_word" ]] && _fp_words+=("$_fp_word")
    done < <(_extract_term_list "$_principles_file" "$_fp_key")
  done
  if [[ ${#_fp_words[@]} -gt 0 ]]; then
    _fp_any=$(printf '%s' "$_fp_clean" | grep -ioFf <(printf '%s\n' "${_fp_words[@]}") | sort -u || true)
  fi

  # 遮断が無効なとき: union の hit 語を log に記録するだけで、GUARD_CLASS / MESSAGE / ADDITIONAL_CONTEXT を変更しない。
  # category 別の内訳は辞書を引けば後から復元できるので、per-key loop と構造検査 (python fork) は走らせない。
  # verdict は block と別値にする。jp-quality-override-detect が block 行だけを override 判定に使うため
  if [[ "$_jpq_enforce" -ne 1 ]]; then
    if [[ -n "$_fp_any" ]]; then
      _append_jp_quality_log "$context_label" "$(printf '%s' "$_fp_any" | tr '\n' ',' | sed 's/,$//')" "record-only"
    fi
    return 0
  fi

  if [[ -n "$_fp_any" ]]; then
    for _cat_entry in "${_block_categories[@]}"; do
      _cat_key="${_cat_entry%%|*}"
      if ! _hit_words=$(_check_term_list "$text" "$_cat_key"); then
        _hit_by_key["${_cat_key}"]="${_hit_words}"
        _has_block=1
      fi
    done
  fi

  # warn-only チェック (block 有無に関係なく実行)
  local _warn_words=""
  if ! _warn_words=$(_check_term_list "$text" "断定語 (warn-only)"); then
    local _warn_list
    _warn_list=$(printf '%s' "$_warn_words" | tr '\n' ',' | sed 's/,$//')
    _append_jp_quality_log "$context_label" "$_warn_list" "warn"
  fi

  # 英語jargon warn-only: log に加えて additionalContext で書き直しを促す (block はしない)
  local _jargon_words=""
  local _jargon_msg=""
  if ! _jargon_words=$(_check_term_list "$text" "英語jargon (warn-only)"); then
    local _jargon_list
    _jargon_list=$(printf '%s' "$_jargon_words" | tr '\n' ',' | sed 's/,$//')
    _append_jp_quality_log "$context_label" "jargon: ${_jargon_list}" "warn"
    _jargon_msg="${ICON_WARNING:-▲} 英語jargon warn (${context_label}): ${_jargon_list} — 日本語で言える一般語は日本語化、識別子として使うなら backtick で囲む (NG-DICTIONARY.md 「英語jargon」)"
  fi

  # 構造的可読性 warn (連続漢字 / 読点)。block しない、additionalContext に追記
  local _struct_warn
  _struct_warn=$(_check_structural_quality "$text")
  # counts 版を直接呼ぶ ($() subshell だと _SS_* が親に伝播しないため wrapper は使えない)
  _check_sentence_structure_counts "$text" 0 0
  local _sent_warn=""
  (( _SS_ARROW > 0 )) && _sent_warn="${_sent_warn}矢印チェーン: ${_SS_ARROW}行 → 文章に展開; "
  (( _SS_FLAT > 0 )) && _sent_warn="${_sent_warn}平坦 bullet ≥11 + 理由語含み: ${_SS_FLAT}group → 上位と下位の階層に組み替え (PRINCIPLES.md ## 箇条書き階層化); "
  (( _SS_TIME > 0 )) && _sent_warn="${_sent_warn}時限マーカー: ${_SS_TIME}件 (${_SS_TIME_SAMPLE}) → 時制中立表現に (pr-description.md ### 時限マーカー禁止); "
  (( _SS_STUFF > 0 )) && _sent_warn="${_sent_warn}括弧詰め込み: ${_SS_STUFF}件 (${_SS_STUFF_SAMPLE}) → 括弧の名詞羅列を本文の文に開く (PRINCIPLES.md ### 圧縮文を開く); "
  (( _SS_ENDING > 0 )) && _sent_warn="${_sent_warn}同一文末3連続: ${_SS_ENDING}箇所 (${_SS_ENDING_SAMPLE}) → 文をまとめるか 2 文目以降を下位 bullet に下げる; "
  _sent_warn="${_sent_warn%; }"
  # 100字超文の block は廃止 (2026-08-28)。字数を理由に語を削った不自然な文を誘発したため、文長は hook で判定しない
  local _struct_block=""
  # 文末の断定「〜だ」は block する (PRINCIPLES.md 「plain JP の文体」、user 指示 2026-09-12)。
  # 辞書は fixed-string 一致で「読んだ」のような撥音便の過去形まで拾うため、構造判定で扱う
  if (( _SS_PLAIN_DA > 0 )); then
    _struct_block="文末の断定「〜だ」${_SS_PLAIN_DA}件 (${_SS_PLAIN_DA_SAMPLE}) → 動詞終止 (〜する / 〜した / 〜ある) か「〜になる」に開く"
  fi
  if [[ -n "$_sent_warn" ]]; then
    _struct_warn="${_struct_warn:+${_struct_warn}; }${_sent_warn}"
  fi
  local _struct_msg=""
  if [[ -n "$_struct_warn" ]]; then
    _append_jp_quality_log "$context_label" "structural: ${_struct_warn}" "warn"
    _struct_msg="${ICON_WARNING:-▲} 可読性 warn (${context_label}): ${_struct_warn}"
  fi
  if [[ -n "$_jargon_msg" ]]; then
    if [[ -n "$_struct_msg" ]]; then
      _struct_msg="${_struct_msg}"$'\n'"${_jargon_msg}"
    else
      _struct_msg="${_jargon_msg}"
    fi
  fi

  # block なし → return (構造 warn があれば additionalContext に含める)
  if [[ "$_has_block" -eq 0 && -z "$_struct_block" ]]; then
    if [[ -n "$_struct_msg" ]]; then
      if [[ -n "$ADDITIONAL_CONTEXT" ]]; then
        ADDITIONAL_CONTEXT="${ADDITIONAL_CONTEXT}"$'\n'"${_struct_msg}"
      else
        ADDITIONAL_CONTEXT="${_struct_msg}"
      fi
    fi
    return
  fi

  # --- 全 hit を一括集計してメッセージ構築 ---
  GUARD_CLASS="Forbidden"

  # 全 hit 用語をカンマ区切りで結合 (log 用)
  local _all_terms_list=""
  local _detail_lines=""
  for _cat_entry in "${_block_categories[@]}"; do
    _cat_key="${_cat_entry%%|*}"
    # label: 2番目フィールド (key|label|guidance から抽出)
    local _rest="${_cat_entry#*|}"
    _cat_label="${_rest%%|*}"
    _cat_guidance="${_rest#*|}"
    if [[ -v "_hit_by_key[${_cat_key}]" ]]; then
      local _wl
      _wl=$(printf '%s' "${_hit_by_key[${_cat_key}]}" | tr '\n' ',' | sed 's/,$//')
      if [[ -n "$_all_terms_list" ]]; then
        _all_terms_list="${_all_terms_list},${_wl}"
      else
        _all_terms_list="${_wl}"
      fi
      # _detail_lines に label を使う (bats テスト "難読漢語 block" 等と互換)
      # hit 語ごとに置換候補を調べて候補があれば "語 → 候補" を列挙する
      local _suggestion_lines=""
      local _sw
      while IFS= read -r _sw; do
        [[ -z "$_sw" ]] && continue
        local _sugg
        _sugg=$(_lookup_suggestion "$_sw")
        if [[ -n "$_sugg" ]]; then
          _suggestion_lines="${_suggestion_lines}    ${_sw} → ${_sugg}"$'\n'
        fi
      done < <(printf '%s\n' "${_hit_by_key[${_cat_key}]}")
      if [[ -n "$_suggestion_lines" ]]; then
        _detail_lines="${_detail_lines}  ${_cat_label}: [${_wl}] → ${_cat_guidance}"$'\n'"${_suggestion_lines}"
      else
        _detail_lines="${_detail_lines}  ${_cat_label}: [${_wl}] → ${_cat_guidance}"$'\n'
      fi
    fi
  done

  # log は全 hit 用語をカンマ区切りで1行
  [[ -n "$_all_terms_list" ]] && _append_jp_quality_log "$context_label" "$_all_terms_list" "block"
  if [[ -n "$_struct_block" ]]; then
    _append_jp_quality_log "$context_label" "structural: ${_struct_block}" "block"
    _detail_lines="${_detail_lines}  構造 block: ${_struct_block}"$'\n'
  fi

  # systemMessage: 検出用語一覧 (構造 block 単独時は構造理由を表示)
  if [[ -n "$_all_terms_list" ]]; then
    MESSAGE="${ICON_CRITICAL} NG用語 block (${context_label}): [${_all_terms_list}]${_struct_block:+ + ${_struct_block}}"
  else
    MESSAGE="${ICON_CRITICAL} NG構造 block (${context_label}): ${_struct_block}"
  fi

  # additionalContext: category 別詳細 + source
  ADDITIONAL_CONTEXT="以下のNG用語を修正して再実行してください。語だけを差し替えず、検出語を含む文を単位に書き直してください (置換候補は書き直しの方向を示すもので、貼り替える対象ではありません)。source: guidelines/writing/NG-DICTIONARY.md
${_detail_lines}"

  # 各 block category の語 list も併記する (回避参考)。全語を並べると 435 語の category で
  # hit 語が埋没するため、hit 語を先頭に置いて _TH_JP_REF_LIST_MAX 語で打ち切り、残数を添える
  local _ref_lines=""
  for _cat_entry in "${_block_categories[@]}"; do
    _cat_key="${_cat_entry%%|*}"
    if [[ -v "_hit_by_key[${_cat_key}]" ]]; then
      local _ref_words=() _ref_word _ref_seen _ref_skipped=0 _ref_list _ref_nocase
      while IFS= read -r _ref_word; do
        [[ -n "$_ref_word" ]] && _ref_words+=("$_ref_word")
      done <<< "${_hit_by_key[${_cat_key}]}"
      # 末尾改行を保つため command substitution ではなく loop で組み立てる
      _ref_seen=$'\n'
      if [[ ${#_ref_words[@]} -gt 0 ]]; then
        for _ref_word in "${_ref_words[@]}"; do
          _ref_seen="${_ref_seen}${_ref_word}"$'\n'
        done
      fi
      # hit 語は grep -ioF の出力で、入力側の綴りがそのまま保持される。辞書の語と綴りが違うと
      # 同じ語が 2 回並ぶため、重複判定のあいだだけ大小の区別を無くす
      # shopt -p は option が off のとき exit 1 を返すので、set -e で止まらないよう || true を付ける
      _ref_nocase=$(shopt -p nocasematch || true)
      shopt -s nocasematch
      while IFS= read -r _ref_word; do
        [[ -z "$_ref_word" ]] && continue
        [[ "$_ref_seen" == *$'\n'"${_ref_word}"$'\n'* ]] && continue
        if [[ ${#_ref_words[@]} -ge $_TH_JP_REF_LIST_MAX ]]; then
          _ref_skipped=$(( _ref_skipped + 1 ))
          continue
        fi
        _ref_words+=("$_ref_word")
        _ref_seen="${_ref_seen}${_ref_word}"$'\n'
      done < <(_extract_term_list "$_principles_file" "$_cat_key")
      eval "$_ref_nocase"
      _ref_list=$(printf '%s, ' "${_ref_words[@]}")
      _ref_list="${_ref_list%, }"
      if [[ "$_ref_skipped" -gt 0 ]]; then
        _ref_list="${_ref_list} (他 ${_ref_skipped} 語は NG-DICTIONARY.md 「${_cat_key}」参照)"
      fi
      _ref_lines="${_ref_lines}  ${_cat_key} block list: ${_ref_list}"$'\n'
    fi
  done
  if [[ -n "$_ref_lines" ]]; then
    ADDITIONAL_CONTEXT="${ADDITIONAL_CONTEXT}
block list (この session で全て回避):
${_ref_lines}"
  fi

  # block 時も構造 warn を併記 (修正ついでに可読性も改善する)
  if [[ -n "$_struct_msg" ]]; then
    ADDITIONAL_CONTEXT="${ADDITIONAL_CONTEXT}"$'\n'"${_struct_msg}"
  fi
}

# chat 応答 (stop hook 経路) の文体検査。誤爆の低い語彙 8 key + 構造 1 種 (矢印) を block し、
# 誤爆リスクのある key + 残りの構造検査は warn に降格する。
# 出力契約: _CHAT_BLOCK_REASON (block hit 時のみ非空) / _CHAT_WARN_MSG (warn hit 時のみ非空) の 2 変数。
# _assert_required_keys は呼ばない (exit 2 が stop hook では block になるため)。dict 不在は graceful return。
# turn 締め語 (完了/次に/済/済み) は行末に単独で現れる場合だけ block 対象にする。文中利用は対象外にする
_check_turn_closing_tail() {
  local text="$1"
  local clean
  clean=$(_strip_code_blocks "$text")
  local words=("完了" "次に" "済み" "済")
  local hits="" w
  for w in "${words[@]}"; do
    if printf '%s\n' "$clean" | grep -qE "${w}。?[[:space:]]*\$"; then
      hits="${hits:+${hits},}${w}"
    fi
  done
  printf '%s' "$hits"
}

# 許可一覧に含まれない小文字英単語 (3 字以上) を返す。denylist 追補でなく反転方式にしたのは語追いが終わらないためだ。
# 大文字含みの語と backtick 内と複合識別子は対象外にする。escape hatch: JP_EN_ALLOWLIST_CHECK=0
_allowed_en_terms_file="$HOME/.claude/guidelines/writing/allowed-en-terms.txt"
_check_unknown_en_terms() {
  local text="$1"
  [[ "${JP_EN_ALLOWLIST_CHECK:-1}" == "1" ]] || return 0
  [[ -f "$_allowed_en_terms_file" ]] || return 0
  local clean
  clean=$(_strip_code_blocks "$text")
  clean=$(printf '%s' "$clean" | sed -E 's#[A-Za-z0-9~]+([/._~-]+[A-Za-z0-9~]+)+# #g')
  printf '%s\n' "$clean" | tr -c 'A-Za-z0-9\n' '\n' | grep -E '^[a-z]{3,}$' | sort -u \
    | grep -Fxv -f "$_allowed_en_terms_file" || true
}

_chat_quality_check() {
  local text="$1"
  _CHAT_BLOCK_REASON=""
  _CHAT_WARN_MSG=""
  # 文体の機械判定で応答を書き直すと、事実・時制・評価まで変わりうる。
  # 既定では書き直しを求めず、検出結果を log に記録するだけにする。
  # log の verdict を block と別値にするのは、jp-quality-override-detect が block 行だけを override 判定に使うため
  local _jpq_enforce=0
  [[ "${JP_QUALITY_STYLE_ENFORCEMENT:-0}" == "1" ]] && _jpq_enforce=1
  [[ -z "$text" ]] && return 0
  [[ -f "$_principles_file" ]] || return 0
  _preload_term_lists

  # 弱い表現 / AI段取り / ヘッジは外向き経路で block 実績があり誤爆が低いため chat でも block (2026-07-16 昇格)。
  # 断定語 (「完了」がタスク名引用で誤爆) / 英語jargon / 過剰丁寧 (UI コピー draft の正当用法) は warn 据え置き。
  # 非公式専門用語 は chat でのみ warn とする。辞書へ登録した語そのものを話題にする会話 (登録の可否検討 / 言い換えの相談) が
  # 成立しなくなるため。file / commit / PR 経路は block のまま (_block_categories、user 指示 2026-09-14)
  local _cq_block_keys=("AI定型語" "カタカナ造語禁止" "難読漢語 (block)" "非日常英語 (block)" "冗長表現 (block)" "弱い表現 (block)" "AI段取り定型 (block)" "ヘッジ濫用 (block)" "比喩・擬人化 (block)" "曖昧な汎用動詞 (block)" "くだけた話し言葉 (block)" "記号 (block)")
  local _cq_warn_keys=("過剰丁寧 (block)" "断定語 (warn-only)" "英語jargon (warn-only)" "主体不明断定 (warn-only)" "非公式専門用語 (block)")

  # fast path: 全 key の語 union を 1 回の grep で検査し、hit ゼロ (大多数) なら per-key loop を省く
  local _cq_clean
  _cq_clean=$(_strip_code_blocks "$text")
  _cq_clean=$(printf '%s' "$_cq_clean" | sed -E 's/[A-Za-z0-9_.]+(-[A-Za-z0-9_.]+)+/ /g')
  local _cq_key _cq_word
  local _cq_all_words=()
  for _cq_key in "${_cq_block_keys[@]}" "${_cq_warn_keys[@]}"; do
    while IFS= read -r _cq_word; do
      [[ -n "$_cq_word" ]] && _cq_all_words+=("$_cq_word")
    done < <(_extract_term_list "$_principles_file" "$_cq_key")
  done
  local _cq_any=""
  if [[ ${#_cq_all_words[@]} -gt 0 ]]; then
    _cq_any=$(printf '%s' "$_cq_clean" | grep -ioFf <(printf '%s\n' "${_cq_all_words[@]}") | sort -u || true)
  fi

  # turn 締め語 (完了/次に/済/済み) は文末 anchor 一致のみ block 対象。「次に」は AI段取り定型 の lead 判定より優先する
  local _cq_tail_hits
  _cq_tail_hits=$(_check_turn_closing_tail "$text")

  # 遮断が無効なとき: union の hit 語を log に記録して抜ける。
  # 以降の per-key loop と構造検査と許可一覧外英単語の抽出は turn ごとに 300ms 級かかるうえ、
  # 遮断を有効にするかは語の頻度で判断でき、category 別の内訳は辞書を引けば後から復元できる
  if [[ "$_jpq_enforce" -ne 1 ]]; then
    [[ -n "$_cq_any" ]] && _append_jp_quality_log "chat" "$(printf '%s' "$_cq_any" | tr '\n' ',' | sed 's/,$//')" "record-only"
    [[ -n "$_cq_tail_hits" ]] && _append_jp_quality_log "chat" "turn締め語文末: ${_cq_tail_hits}" "record-only"
    return 0
  fi

  local _cq_block_terms="" _cq_detail="" _cq_warn_terms=""
  if [[ -n "$_cq_any" ]]; then
    local _cq_hits _cq_list
    for _cq_key in "${_cq_block_keys[@]}"; do
      if ! _cq_hits=$(_check_term_list "$text" "$_cq_key"); then
        if [[ "$_cq_key" == "AI段取り定型 (block)" && "$_cq_tail_hits" != *"次に"* ]]; then
          _cq_hits=$(printf '%s\n' "$_cq_hits" | grep -v '^次に$' || true)
          [[ -z "$_cq_hits" ]] && continue
        fi
        _cq_list=$(printf '%s' "$_cq_hits" | tr '\n' ',' | sed 's/,$//')
        _cq_block_terms="${_cq_block_terms:+${_cq_block_terms},}${_cq_list}"
        # 置換候補を併記して自己修正の 1 発成功率を上げる
        local _cq_sugg _cq_sline=""
        while IFS= read -r _cq_word; do
          [[ -z "$_cq_word" ]] && continue
          _cq_sugg=$(_lookup_suggestion "$_cq_word")
          [[ -n "$_cq_sugg" ]] && _cq_sline="${_cq_sline} ${_cq_word}→${_cq_sugg}"
        done <<< "$_cq_hits"
        _cq_detail="${_cq_detail}${_cq_key}: [${_cq_list}]${_cq_sline:+ (置換候補:${_cq_sline})}; "
      fi
    done
    for _cq_key in "${_cq_warn_keys[@]}"; do
      if ! _cq_hits=$(_check_term_list "$text" "$_cq_key"); then
        _cq_list=$(printf '%s' "$_cq_hits" | tr '\n' ',' | sed 's/,$//')
        _cq_warn_terms="${_cq_warn_terms:+${_cq_warn_terms},}${_cq_list}"
      fi
    done
  fi

  # 構造検査。chat は敬体規範 (2026-08-28) なので「〜だ」終止を逆向きに検査 (mode 2)、可読性 (連続漢字/読点) 同梱で python 1 fork。
  # 語彙 hit ゼロでも構造 block は発生するため fast path (_cq_any) の外で判定する。
  # 矢印チェーンは誤爆源を潰した上で block へ昇格済だから block 側で扱う。100字超文は 2026-08-28 に廃止 (字数で語を削る誘因になった)。
  # 連続漢字・読点は UI コピーや固有名詞で誤爆するため warn に据え置く
  _check_sentence_structure_counts "$text" 2 1
  local _cq_struct_block="" _cq_struct_warn=""
  (( _SS_ARROW > 0 )) && _cq_struct_block="${_cq_struct_block}矢印チェーン ${_SS_ARROW}行 (矢印列を動詞のある文章に展開する); "
  (( _SS_PLAIN_DA > 0 )) && _cq_struct_block="${_cq_struct_block}文末の断定「〜だ」${_SS_PLAIN_DA}件 (${_SS_PLAIN_DA_SAMPLE}。敬体で閉じる); "
  (( _SS_ENDING > 0 )) && _cq_struct_block="${_cq_struct_block}同一文末3連続 ${_SS_ENDING}箇所 (${_SS_ENDING_SAMPLE}。文をまとめるか 2 文目以降を下位 bullet に下げる。語尾の文字列だけを差し替えない); "
  (( _SS_KANJI_CNT > 0 )) && _cq_struct_warn="${_cq_struct_warn}連続漢字≥5: ${_SS_KANJI_CNT}種 (${_SS_KANJI_SAMPLE}) → 助詞挿入/訓読み開く; "
  (( _SS_TOUTEN > 0 )) && _cq_struct_warn="${_cq_struct_warn}読点≥4の文: ${_SS_TOUTEN}個 → 文分割; "
  (( _SS_POLITE > 0 )) && _cq_struct_warn="${_cq_struct_warn}常体終止「〜だ」: ${_SS_POLITE}文 → 敬体 (です・ます) に統一; "
  (( _SS_FLAT > 0 )) && _cq_struct_warn="${_cq_struct_warn}平坦bullet≥11+理由語: ${_SS_FLAT}group → 上位と下位の階層に組み替え (PRINCIPLES.md ## 箇条書き階層化); "
  (( _SS_TIME > 0 )) && _cq_struct_warn="${_cq_struct_warn}時限マーカー: ${_SS_TIME}件 (${_SS_TIME_SAMPLE}) → 時制中立表現 (pr-description.md ### 時限マーカー禁止); "
  (( _SS_STUFF > 0 )) && _cq_struct_warn="${_cq_struct_warn}括弧詰め込み: ${_SS_STUFF}件 (${_SS_STUFF_SAMPLE}) → 括弧の名詞羅列を本文の文に開く (PRINCIPLES.md ### 圧縮文を開く); "

  local _cq_block_detail=""
  if [[ -n "$_cq_block_terms" ]]; then
    _append_jp_quality_log "chat" "$_cq_block_terms" "block"
    _cq_block_detail="${_cq_detail%; }"
  fi
  if [[ -n "$_cq_struct_block" ]]; then
    _append_jp_quality_log "chat" "structural: ${_cq_struct_block%; }" "block"
    _cq_block_detail="${_cq_block_detail:+${_cq_block_detail}; }構造: ${_cq_struct_block%; }"
  fi
  if [[ -n "$_cq_tail_hits" ]]; then
    _append_jp_quality_log "chat" "turn締め語文末: ${_cq_tail_hits}" "block"
    _cq_block_detail="${_cq_block_detail:+${_cq_block_detail}; }turn締め語文末: ${_cq_tail_hits} (言い切って終えず、次の行に実際の内容を続けて書く。加えて 'superpowers:verification-before-completion' skill の Iron Law に従い、宣言前に検証 command を実行した evidence を書き込む)"
  fi
  if [[ -n "$_cq_block_detail" ]]; then
    _CHAT_BLOCK_REASON="chat 応答が plain JP 規範に反する: ${_cq_block_detail} — 直前の応答本文だけを規範に沿った開いた日本語に書き直して再送する。source: guidelines/writing/NG-DICTIONARY.md + guidelines/writing/PRINCIPLES.md"
  fi
  local _cq_warn_out=""
  if [[ -n "$_cq_warn_terms" ]]; then
    _append_jp_quality_log "chat" "$_cq_warn_terms" "warn"
    _cq_warn_out="語: ${_cq_warn_terms}"
  fi
  # 許可一覧外英単語 (反転方式)。上限 10 語で message 肥大を防ぐ
  local _cq_unknown_en
  _cq_unknown_en=$(_check_unknown_en_terms "$text" | head -10 | tr '\n' ',' | sed 's/,$//')
  if [[ -n "$_cq_unknown_en" ]]; then
    _append_jp_quality_log "chat" "unknown-en: ${_cq_unknown_en}" "warn"
    _cq_warn_out="${_cq_warn_out:+${_cq_warn_out}; }許可一覧外の英単語: ${_cq_unknown_en} → 日本語化するか backtick で囲む。定着語なら guidelines/writing/allowed-en-terms.txt に追加"
  fi
  if [[ -n "$_cq_struct_warn" ]]; then
    _append_jp_quality_log "chat" "structural: ${_cq_struct_warn%; }" "warn"
    _cq_warn_out="${_cq_warn_out:+${_cq_warn_out}; }${_cq_struct_warn%; }"
  fi
  if [[ -n "$_cq_warn_out" ]]; then
    _CHAT_WARN_MSG="${ICON_WARNING:-▲} chat 文体 warn: ${_cq_warn_out} — 次の応答は plain JP 規範 (guidelines/writing/PRINCIPLES.md) に沿って直す"
  fi
  # 遮断が無効なとき: log は残し、応答の書き直しも warn 通知も求めない
  if [[ "$_jpq_enforce" -ne 1 ]]; then
    _CHAT_BLOCK_REASON=""
    _CHAT_WARN_MSG=""
  fi
  return 0
}
