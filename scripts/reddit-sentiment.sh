#!/bin/bash
# reddit-sentiment.sh — Reddit crypto discussions via JSON API
# Usage: ./reddit-sentiment.sh <query> [subreddit]
# Examples:
#   ./reddit-sentiment.sh Ethereum
#   ./reddit-sentiment.sh Solana solana
#   ./reddit-sentiment.sh "Uniswap v4" defi
#
# No API key needed — uses Reddit's public JSON endpoints.

set -euo pipefail

QUERY="${1:?Usage: $0 <query> [subreddit]}"
SUBREDDIT="${2:-cryptocurrency}"
UA="crypto-research-skill/2.5"

echo "=========================================="
echo "🗣️ Reddit: $QUERY (r/$SUBREDDIT)"
echo "=========================================="

# ========================
# Search within subreddit
# ========================
echo ""
echo "📋 Top posts (last 30 days)"
echo "---"

ENCODED_QUERY=$(echo "$QUERY" | sed 's/ /+/g')
SEARCH_DATA=$(curl -s -L --max-time 15 \
  "https://www.reddit.com/r/${SUBREDDIT}/search.json?q=${ENCODED_QUERY}&restrict_sr=1&sort=relevance&t=month&limit=10" \
  -H "User-Agent: $UA" 2>/dev/null || true)

if [[ -n "$SEARCH_DATA" ]] && echo "$SEARCH_DATA" | jq -e '.data.children' &>/dev/null 2>&1; then
  RESULT_COUNT=$(echo "$SEARCH_DATA" | jq '.data.children | length' 2>/dev/null || echo "0")
  if [[ "$RESULT_COUNT" -gt 0 ]]; then
    echo "$SEARCH_DATA" | jq -r '.data.children[:10][] | .data |
      "[\(.score // 0) pts, \(.num_comments // 0) comments] \(.title // "N/A" | .[0:120])",
      "  r/\(.subreddit // "?") · \(.created_utc // 0 | todate) · https://reddit.com\(.permalink // "" | .[0:100])",
      ""
    ' 2>/dev/null || echo "  Parse error"
  else
    echo "  No results found in r/$SUBREDDIT for: $QUERY"
  fi
else
  echo "  ⚠️ Reddit search failed or returned no data"
  echo "  Try: https://www.reddit.com/r/${SUBREDDIT}/search/?q=${ENCODED_QUERY}"
fi

sleep 1  # Respect rate limits between requests

# ========================
# Hot posts from the subreddit
# ========================
echo ""
echo "🔥 Hot in r/$SUBREDDIT"
echo "---"

HOT_DATA=$(curl -s -L --max-time 15 \
  "https://www.reddit.com/r/${SUBREDDIT}/hot.json?limit=5" \
  -H "User-Agent: $UA" 2>/dev/null || true)

if [[ -n "$HOT_DATA" ]] && echo "$HOT_DATA" | jq -e '.data.children' &>/dev/null 2>&1; then
  echo "$HOT_DATA" | jq -r '.data.children[:5][] | .data |
    "[\(.score // 0) pts] \(.title // "N/A" | .[0:120])",
    "  \(.num_comments // 0) comments · https://reddit.com\(.permalink // "" | .[0:100])",
    ""
  ' 2>/dev/null || echo "  Parse error"
else
  echo "  ⚠️ Could not fetch hot posts"
fi

echo "=========================================="
echo "✅ Reddit research complete."
echo "=========================================="
