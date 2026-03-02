#!/bin/bash
# dune-search.sh — Search for related Dune Analytics dashboards
# Usage: ./dune-search.sh <project_name>
# Example: ./dune-search.sh Uniswap
# Example: ./dune-search.sh Aave
#
# If DUNE_API_KEY is set: uses Dune API to list queries
# Otherwise: provides curated links + search URLs

set -euo pipefail

INPUT="${1:?Usage: $0 <project_name>}"
DUNE_KEY="${DUNE_API_KEY:-}"

SLUG=$(echo "$INPUT" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
SEARCH_TERM=$(echo "$INPUT" | tr ' ' '+')

echo "=========================================="
echo "📊 Dune Analytics: $INPUT"
echo "=========================================="

# ========================
# Curated popular dashboards
# ========================
# Map of known project -> top Dune dashboard URLs
declare -A KNOWN_DASHBOARDS=(
  ["ethereum"]="https://dune.com/hildobby/eth2-staking"
  ["uniswap"]="https://dune.com/hagaetc/dex-metrics"
  ["aave"]="https://dune.com/llama/aave"
  ["lido"]="https://dune.com/LidoAnalytical/Lido-Finance-Extended"
  ["makerdao"]="https://dune.com/SebVentures/maker---accounting_1"
  ["maker"]="https://dune.com/SebVentures/maker---accounting_1"
  ["compound"]="https://dune.com/messari/Messari:-Compound-Macro-Financial-Statements"
  ["opensea"]="https://dune.com/rchen8/opensea"
  ["blur"]="https://dune.com/pandajackson42/blur"
  ["arbitrum"]="https://dune.com/Henrystats/arbitrum-metrics"
  ["optimism"]="https://dune.com/Henrystats/optimism-metrics"
  ["polygon"]="https://dune.com/Henrystats/polygon-metrics"
  ["base"]="https://dune.com/Henrystats/base"
  ["solana"]="https://dune.com/ilemi/solana-overview"
  ["jupiter"]="https://dune.com/ilemi/jupiter-aggregator"
  ["curve"]="https://dune.com/mrblock_buidl/Curve.fi"
  ["gmx"]="https://dune.com/shogun/gmx-analytics-arbitrum"
  ["dydx"]="https://dune.com/shogun/dydx-v4-stats"
  ["eigenlayer"]="https://dune.com/hahahash/eigenlayer"
  ["pendle"]="https://dune.com/pendle/pendle"
  ["hyperliquid"]="https://dune.com/uwusanaaa/hyperliquid"
  ["ens"]="https://dune.com/makoto/ens"
  ["nft"]="https://dune.com/hildobby/nfts"
  ["stablecoins"]="https://dune.com/21co/stablecoins"
  ["layerzero"]="https://dune.com/cryptoded/layerzero"
  ["across"]="https://dune.com/eliasimos/across-bridge"
  ["wormhole"]="https://dune.com/pzagor/wormhole"
  ["celestia"]="https://dune.com/jhackworth/celestia"
  ["raydium"]="https://dune.com/ilemi/raydium"
  ["pancakeswap"]="https://dune.com/Chef_Nomi/pancakeswap"
  ["sushiswap"]="https://dune.com/hagaetc/sushi"
)

# Check curated dashboards
echo ""
echo "📌 Known Dashboards:"
echo "---"

SLUG_LOWER=$(echo "$SLUG" | tr '[:upper:]' '[:lower:]')
FOUND_CURATED=false

for key in "${!KNOWN_DASHBOARDS[@]}"; do
  if [[ "$SLUG_LOWER" == *"$key"* || "$key" == *"$SLUG_LOWER"* ]]; then
    echo "  ⭐ ${KNOWN_DASHBOARDS[$key]}"
    FOUND_CURATED=true
  fi
done

if [[ "$FOUND_CURATED" == "false" ]]; then
  echo "  No curated dashboard found for '$INPUT'"
fi

# ========================
# Dune Search Links
# ========================
echo ""
echo "🔍 Dune Search Links:"
echo "---"
echo "  Dashboards: https://dune.com/browse/dashboards?q=${SEARCH_TERM}"
echo "  Queries:    https://dune.com/browse/queries?q=${SEARCH_TERM}"
echo "  All:        https://dune.com/search?q=${SEARCH_TERM}"

# ========================
# API-based search (if key available)
# ========================
if [[ -n "$DUNE_KEY" ]]; then
  echo ""
  echo "🔑 Dune API Search (using your API key):"
  echo "---"

  # List user's own queries that match
  USER_QUERIES=$(curl -s --max-time 15 \
    -H "X-DUNE-API-KEY: $DUNE_KEY" \
    "https://api.dune.com/api/v1/query?limit=10&name=${SEARCH_TERM}" 2>/dev/null || true)

  if echo "$USER_QUERIES" | jq -e '.queries' &>/dev/null 2>&1; then
    count=$(echo "$USER_QUERIES" | jq '.queries | length // 0')
    if [[ "$count" -gt 0 ]]; then
      echo "  Found $count matching queries:"
      echo "$USER_QUERIES" | jq -r '.queries[:10][] |
        "  • [\(.query_id)] \(.name // "Untitled") — https://dune.com/queries/\(.query_id)"
      ' 2>/dev/null
    else
      echo "  No matching queries found in your account"
    fi
  fi

  # Try to get results from a well-known query
  echo ""
  echo "  💡 Tip: You can execute any Dune query via API:"
  echo "     curl -X POST 'https://api.dune.com/api/v1/query/{QUERY_ID}/execute' \\"
  echo "       -H 'X-DUNE-API-KEY: \$DUNE_API_KEY'"
  echo "     curl 'https://api.dune.com/api/v1/query/{QUERY_ID}/results' \\"
  echo "       -H 'X-DUNE-API-KEY: \$DUNE_API_KEY'"
else
  echo ""
  echo "💡 Dune API:"
  echo "---"
  echo "  Set DUNE_API_KEY to search via API (free: 2500 credits/mo)"
  echo "  Get key: https://dune.com/settings/api"
  echo ""
  echo "  With a key you can:"
  echo "  • Execute SQL queries against on-chain data"
  echo "  • Fetch cached results from existing dashboards"
  echo "  • Create custom analytics pipelines"
fi

# ========================
# Suggested searches by category
# ========================
echo ""
echo "🏷️ Suggested Dashboard Searches:"
echo "---"

# Generate relevant search variations
echo "  General:       https://dune.com/browse/dashboards?q=${SEARCH_TERM}"
echo "  TVL/Metrics:   https://dune.com/browse/dashboards?q=${SEARCH_TERM}+metrics"
echo "  Revenue/Fees:  https://dune.com/browse/dashboards?q=${SEARCH_TERM}+revenue"
echo "  Users/Growth:  https://dune.com/browse/dashboards?q=${SEARCH_TERM}+users"
echo "  Token:         https://dune.com/browse/dashboards?q=${SEARCH_TERM}+token"
echo "  Treasury:      https://dune.com/browse/dashboards?q=${SEARCH_TERM}+treasury"

# ========================
# Tips
# ========================
echo ""
echo "📋 How to use Dune dashboards:"
echo "---"
echo "  1. Click a dashboard link above"
echo "  2. Look for dashboards with most ⭐ stars (more reliable)"
echo "  3. Key metrics to check:"
echo "     • Daily/weekly active users (DAU/WAU)"
echo "     • Transaction volume and count"
echo "     • Revenue and fee generation"
echo "     • Token holder distribution"
echo "     • Treasury and governance data"
echo "  4. You can fork any query and customize it"

echo ""
echo "=========================================="
echo "✅ Dune search complete."
echo "=========================================="
