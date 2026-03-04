#!/bin/bash
# web-reader.sh — Read web page content via Jina Reader
# Usage: ./web-reader.sh <url>
# Example: ./web-reader.sh https://blog.uniswap.org/uniswap-v4
#
# Returns markdown-formatted page content for AI analysis.
# No API key needed — uses Jina Reader (free, always available).

set -euo pipefail

URL="${1:?Usage: $0 <url>}"

echo "=========================================="
echo "🌐 Web Reader: $URL"
echo "=========================================="
echo ""

# Jina Reader — converts any URL to clean markdown
CONTENT=$(curl -s -L --max-time 30 \
  "https://r.jina.ai/${URL}" \
  -H "Accept: text/markdown" 2>/dev/null || true)

if [[ -z "$CONTENT" ]]; then
  echo "⚠️ Failed to fetch content from URL"
  echo "Try opening directly: $URL"
  exit 1
fi

# Output (truncate very long pages at 500 lines)
LINE_COUNT=$(echo "$CONTENT" | wc -l | tr -d ' ')
echo "$CONTENT" | head -500

if [[ "$LINE_COUNT" -gt 500 ]]; then
  echo ""
  echo "--- [Truncated: showing 500 of $LINE_COUNT lines] ---"
fi

echo ""
echo "=========================================="
echo "✅ Content fetched. Total lines: $LINE_COUNT | Chars: $(echo "$CONTENT" | wc -c | tr -d ' ')"
echo "=========================================="
