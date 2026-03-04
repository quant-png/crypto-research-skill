#!/bin/bash
# exa-search.sh — Semantic web search via Exa (through mcporter MCP bridge)
# Usage: ./exa-search.sh <query> [num_results]
# Examples:
#   ./exa-search.sh "Ethereum dencun upgrade impact"
#   ./exa-search.sh "Solana validator economics" 10
#
# Requires: mcporter (from Agent-Reach)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/agent-reach-check.sh"

QUERY="${1:?Usage: $0 <query> [num_results]}"
NUM="${2:-5}"

echo "=========================================="
echo "🔎 Exa Search: $QUERY"
echo "=========================================="

if [[ "$HAS_MCPORTER" != "1" ]]; then
  echo "⚠️ mcporter not installed."
  echo "Install via: npm install -g mcporter && mcporter config add exa https://mcp.exa.ai/mcp"
  echo "Or install Agent-Reach: pip install https://github.com/Panniantong/agent-reach/archive/main.zip && agent-reach install --env=auto"
  echo ""
  local_encoded=$(echo "$QUERY" | sed 's/ /+/g')
  echo "Manual search: https://exa.ai/search?q=${local_encoded}"
  exit 1
fi

echo ""

# Call Exa via mcporter MCP bridge
RESULT=$(mcporter call "exa.web_search_exa(query: \"$QUERY\", numResults: $NUM)" 2>/dev/null || true)

if [[ -z "$RESULT" ]]; then
  echo "⚠️ Exa search returned no results or mcporter call failed"
  echo ""
  local_encoded=$(echo "$QUERY" | sed 's/ /+/g')
  echo "Try manually: https://exa.ai/search?q=${local_encoded}"
  exit 1
fi

# Parse results — mcporter returns JSON
echo "$RESULT" | jq -r '
  if type == "array" then
    .[] |
    "📄 \(.title // "N/A")",
    "   URL: \(.url // "N/A")",
    "   \(.text // .snippet // "" | gsub("\n"; " ") | .[0:300])",
    ""
  elif type == "object" and .results then
    .results[] |
    "📄 \(.title // "N/A")",
    "   URL: \(.url // "N/A")",
    "   \(.text // .snippet // "" | gsub("\n"; " ") | .[0:300])",
    ""
  else
    tostring
  end
' 2>/dev/null || echo "$RESULT" | head -50

echo "=========================================="
echo "✅ Exa search complete."
echo "=========================================="
