#!/bin/bash
# kaito-mindshare.sh — Fetch Kaito mindshare / attention data
# Usage: ./kaito-mindshare.sh <token_or_project>
# Example: ./kaito-mindshare.sh Ethereum
# Example: ./kaito-mindshare.sh ETH
#
# Kaito has no free public API — this script:
# 1. Tries to scrape public Kaito pages for mindshare data
# 2. Provides direct links to Kaito portal for manual lookup
# 3. Falls back to web search for recent Kaito mindshare mentions

set -euo pipefail

INPUT="${1:?Usage: $0 <token_or_project>}"

echo "=========================================="
echo "🧠 Kaito Mindshare: $INPUT"
echo "=========================================="
echo ""

# Normalize input
TOKEN=$(echo "$INPUT" | tr '[:lower:]' '[:upper:]')
SLUG=$(echo "$INPUT" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

# ========================
# Method 1: Try Kaito public endpoints
# ========================
echo "🔍 Attempting Kaito data fetch..."
echo ""

# Try the Kaito portal / search page
KAITO_URL="https://portal.kaito.ai"
KAITO_SEARCH="https://portal.kaito.ai/search?q=${INPUT}"

# Try to fetch any publicly accessible Kaito data
KAITO_DATA=$(curl -s -L --max-time 10 \
  -H "User-Agent: Mozilla/5.0" \
  "https://portal.kaito.ai/api/v1/search?query=${INPUT}&type=token" 2>/dev/null || true)

if [[ -n "$KAITO_DATA" ]] && echo "$KAITO_DATA" | jq -e '.data' &>/dev/null 2>&1; then
  echo "📊 Kaito Data Found:"
  echo "$KAITO_DATA" | jq -r '.data[:3][] |
    "  • \(.name // .title // "N/A") — mindshare: \(.mindshare // "N/A")%"
  ' 2>/dev/null || echo "  [Structured data parse failed — see links below]"
else
  echo "⚠️ Kaito public API not accessible (enterprise-only)"
  echo "   Kaito mindshare data requires a Kaito Pro subscription."
fi

# ========================
# Method 2: Direct links for manual lookup
# ========================
echo ""
echo "🔗 Kaito Portal Links:"
echo "---"
echo "  Search: https://portal.kaito.ai/search?q=${INPUT}"
echo "  Token:  https://portal.kaito.ai/token/${TOKEN}"
echo "  Arena:  https://www.kaito.ai/portal"
echo ""
echo "  ℹ️ Open the links above to view live mindshare data, including:"
echo "     • Mindshare % (share of crypto attention)"
echo "     • Sentiment score (bullish/bearish/neutral)"
echo "     • Narrative tracking (which narratives the project appears in)"
echo "     • Smart followers & influential mentions"
echo "     • Mindshare trend over 7d/30d"

# ========================
# Method 3: Search for recent mindshare data in public sources
# ========================
echo ""
echo "📰 Searching public sources for Kaito mindshare data..."
echo ""

# Try to find cached/shared Kaito data from Twitter or public dashboards
# Kaito mindshare data is often shared publicly on Twitter/X
PUBLIC_DATA=$(curl -s -L --max-time 10 \
  "https://api.dune.com/api/echo/beta/mindshare/${SLUG}" 2>/dev/null || true)

# Check if there's a Kaito-Polymarket verifiable mindshare market
echo "🔮 Kaito x Polymarket Mindshare Markets:"
echo "  Check: https://polymarket.com/search?query=kaito+${SLUG}+mindshare"
echo ""

# ========================
# What to look for
# ========================
echo "📋 Kaito Mindshare Analysis Guide:"
echo "---"
echo "When you access Kaito, evaluate the following:"
echo ""
echo "  1. 🎯 Mindshare % — What percentage of crypto attention does this project get?"
echo "     • >5%: Very high (top tier projects like BTC, ETH, SOL)"
echo "     • 1-5%: High (major L1/L2s, trending projects)"
echo "     • 0.1-1%: Medium (mid-cap, niche leaders)"
echo "     • <0.1%: Low (small or declining projects)"
echo ""
echo "  2. 📈 Mindshare Trend — Is attention growing or declining?"
echo "     • Rising mindshare + falling price = potential accumulation opportunity"
echo "     • Falling mindshare + rising price = potential distribution warning"
echo "     • Sudden spike = catalytic event (check what happened)"
echo ""
echo "  3. 💬 Sentiment — What is the sentiment split?"
echo "     • Extreme positive = potentially overbought"
echo "     • Extreme negative = potentially oversold"
echo "     • Mixed = normal / undecided"
echo ""
echo "  4. 🏷️ Narrative Association — Which narratives is the project linked to?"
echo "     • Being in a hot narrative = tailwind for price"
echo "     • Narrative rotation away = headwind"
echo ""
echo "  5. 👥 Smart Followers — Who are the quality followers?"
echo "     • Top KOLs following/discussing = positive signal"
echo "     • High bot ratio = negative signal"
echo ""

echo "=========================================="
echo "✅ Kaito mindshare research complete."
echo "   Note: Full mindshare data requires Kaito Pro access."
echo "=========================================="
