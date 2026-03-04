#!/bin/bash
# social-sentiment.sh — Twitter/X social intelligence via xreach
# Usage: ./social-sentiment.sh <query_or_handle> [mode: search|account|tweet]
# Examples:
#   ./social-sentiment.sh Ethereum
#   ./social-sentiment.sh @VitalikButerin account
#   ./social-sentiment.sh https://x.com/user/status/123 tweet

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/agent-reach-check.sh"

INPUT="${1:?Usage: $0 <query_or_handle> [mode: search|account|tweet]}"
MODE="${2:-search}"

# Auto-detect mode from input
if [[ "$INPUT" == http* ]]; then
  MODE="tweet"
elif [[ "$INPUT" == @* ]]; then
  MODE="account"
fi

require_xreach() {
  if [[ "$HAS_XREACH" != "1" ]]; then
    echo "⚠️ xreach not installed."
    echo "Install via: npm install -g xreach-cli"
    echo "Or install Agent-Reach: pip install https://github.com/Panniantong/agent-reach/archive/main.zip && agent-reach install --env=auto"
    echo ""
    local encoded
    encoded=$(echo "$INPUT" | sed 's/ /+/g')
    echo "Manual search: https://x.com/search?q=${encoded}&f=live"
    exit 1
  fi
}

echo "=========================================="
echo "🐦 Twitter/X: $INPUT (mode: $MODE)"
echo "=========================================="

do_search() {
  require_xreach
  local query="$INPUT"
  echo ""
  echo "Searching tweets for: $query"
  echo "---"

  local data
  data=$(xreach search "$query" --json -n 15 2>/dev/null || true)

  if [[ -z "$data" || "$data" == "[]" || "$data" == "null" ]]; then
    echo "No results found"
    return
  fi

  echo "$data" | jq -r '
    if type == "array" then
      .[:15][] |
      "[@\(.author.username // .user.screen_name // "unknown")] \(.text // .full_text // "" | gsub("\n"; " ") | .[0:200])",
      "  ❤️ \(.likes // .favorite_count // 0) | 🔁 \(.retweets // .retweet_count // 0) | \(.created_at // "")",
      ""
    else
      "Unexpected response format"
    end
  ' 2>/dev/null || echo "$data" | head -50
}

do_account() {
  require_xreach
  local handle="${INPUT#@}"
  echo ""
  echo "Recent tweets from @$handle"
  echo "---"

  local data
  data=$(xreach tweets "@${handle}" --json -n 10 2>/dev/null || true)

  if [[ -z "$data" || "$data" == "[]" || "$data" == "null" ]]; then
    echo "No tweets found or account inaccessible"
    return
  fi

  echo "$data" | jq -r '
    if type == "array" then
      .[:10][] |
      "\(.text // .full_text // "" | gsub("\n"; " ") | .[0:200])",
      "  ❤️ \(.likes // .favorite_count // 0) | 🔁 \(.retweets // .retweet_count // 0) | \(.created_at // "")",
      ""
    else
      "Unexpected response format"
    end
  ' 2>/dev/null || echo "$data" | head -50
}

do_tweet() {
  require_xreach
  echo ""
  echo "Tweet details"
  echo "---"

  local data
  data=$(xreach tweet "$INPUT" --json 2>/dev/null || true)

  if [[ -z "$data" || "$data" == "null" ]]; then
    echo "Could not fetch tweet"
    return
  fi

  echo "$data" | jq -r '
    "Author: @\(.author.username // .user.screen_name // "N/A")",
    "Text: \(.text // .full_text // "N/A" | gsub("\n"; " "))",
    "❤️ \(.likes // .favorite_count // 0) | 🔁 \(.retweets // .retweet_count // 0) | 💬 \(.replies // .reply_count // 0)",
    "Date: \(.created_at // "N/A")"
  ' 2>/dev/null || echo "$data" | head -20
}

case "$MODE" in
  search)  do_search ;;
  account) do_account ;;
  tweet)   do_tweet ;;
  *)       echo "Unknown mode: $MODE. Use: search, account, tweet"; exit 1 ;;
esac

echo ""
echo "=========================================="
echo "✅ Twitter/X research complete."
echo "=========================================="
