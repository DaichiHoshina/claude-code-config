#!/usr/bin/env bash
# Notion/Slack (外向き文章送信 MCP) case body checker (extracted from pre-tool-use.sh)
# 多重 source 防止
if [[ "${_NOTION_CHECKERS_LOADED:-}" == "1" ]]; then
    return 0
fi
_NOTION_CHECKERS_LOADED=1

# ====================================
# "mcp__claude_ai_Notion__..." / "mcp__claude_ai_Slack__..." tool 分岐の本体。
# pre-tool-use.sh の case "$TOOL_NAME" in から挙動を変えずに分離したもの。
# GUARD_CLASS / MESSAGE / ADDITIONAL_CONTEXT は呼び出し元 (pre-tool-use.sh) の
# グローバル変数をそのまま読み書きする。
# ====================================
_handle_notion_slack_tool() {
  local INPUT="$1"
  local TOOL_NAME="$2"

  # 対象: 文章を外向きに送信・投稿・作成する MCP
  # 除外 (構造操作で文章を記述しない):
  #   notion-duplicate-page / notion-move-pages / notion-update-view / notion-update-data-source
  #   slack_add_reaction
  GUARD_CLASS="Safe"

  # AI定型語チェック: text / content param + nested field を全連結して block
  # Notion children: paragraph/heading/bulleted_list_item/numbered_list_item の rich_text[].text.content
  # Slack blocks: blocks[].text.text
  local _mcp_text
  _mcp_text=$(jq -r '
    [
      (.tool_input.text // empty),
      (.tool_input.content // empty),
      (.tool_input.children[]?
        | (.paragraph?.rich_text[]?.text?.content // empty),
          (.heading_1?.rich_text[]?.text?.content // empty),
          (.heading_2?.rich_text[]?.text?.content // empty),
          (.heading_3?.rich_text[]?.text?.content // empty),
          (.bulleted_list_item?.rich_text[]?.text?.content // empty),
          (.numbered_list_item?.rich_text[]?.text?.content // empty),
          (.quote?.rich_text[]?.text?.content // empty),
          (.callout?.rich_text[]?.text?.content // empty),
          (.toggle?.rich_text[]?.text?.content // empty)
      ),
      (.tool_input.blocks[]?.text?.text // empty)
    ] | map(select(. != null and . != "")) | join("\n")
  ' <<< "$INPUT")
  if [[ -n "$_mcp_text" ]]; then
    _block_if_ai_jargon "$_mcp_text" "$TOOL_NAME"
  fi

  # 任意診断を明示的に有効化した場合だけ、追加の文章規範を注入する
  _inject_ng_dict_on_commit_compose
  _inject_today_commits
}
