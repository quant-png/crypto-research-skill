#!/bin/bash
# quick-research.sh — Quick token research via CoinMarketCap API
# Usage: ./quick-research.sh <symbol_or_slug>
# Example: ./quick-research.sh ETH
# Example: ./quick-research.sh ethereum

set -euo pipefail

INPUT="${1:?Usage: $0 <symbol_or_slug>}"
CMC_KEY="${CMC_PRO_API_KEY:-}"
CMC_BASE="https://pro-api.coinmarketcap.com"

if [[ -z "$CMC_KEY" ]]; then
  echo "❌ CMC_PRO_API_KEY is not set."
  echo "Get a free key at: https://pro.coinmarketcap.com"
  exit 1
fi

cmc_get() {
  curl -s "${CMC_BASE}${1}" -H "X-CMC_PRO_API_KEY: $CMC_KEY" 2>/dev/null
}

echo "=========================================="
echo "🔍 Quick Research: $INPUT"
echo "=========================================="

# --- 0. Resolve ID ---
INPUT_UPPER=$(echo "$INPUT" | tr '[:lower:]' '[:upper:]')
MAP_DATA=$(cmc_get "/v1/cryptocurrency/map?symbol=${INPUT_UPPER}&limit=1")

if [[ $(echo "$MAP_DATA" | jq '.data | length // 0') -eq 0 ]]; then
  MAP_DATA=$(cmc_get "/v1/cryptocurrency/map?slug=$(echo "$INPUT" | tr '[:upper:]' '[:lower:]')&limit=1")
  if [[ $(echo "$MAP_DATA" | jq '.data | length // 0') -eq 0 ]]; then
    echo "❌ Token not found on CoinMarketCap: $INPUT"
    exit 1
  fi
fi

CMC_ID=$(echo "$MAP_DATA" | jq -r '.data[0].id')
CMC_NAME=$(echo "$MAP_DATA" | jq -r '.data[0].name')
CMC_SYMBOL=$(echo "$MAP_DATA" | jq -r '.data[0].symbol')
CMC_SLUG=$(echo "$MAP_DATA" | jq -r '.data[0].slug')

echo "Resolved: $CMC_NAME ($CMC_SYMBOL) — ID: $CMC_ID"

# --- 1. Market Data ---
echo ""
echo "📊 Market Data"
echo "---"
QUOTE_DATA=$(cmc_get "/v2/cryptocurrency/quotes/latest?id=${CMC_ID}&convert=USD")
Q_ERR=$(echo "$QUOTE_DATA" | jq -r '.status.error_code // 0')

if [[ "$Q_ERR" != "0" ]]; then
  echo "⚠️ Failed to fetch quotes: $(echo "$QUOTE_DATA" | jq -r '.status.error_message')"
else
  echo "$QUOTE_DATA" | jq -r --arg id "$CMC_ID" '
    .data[$id] // .data[(.data | keys[0])] | (if type == "array" then .[0] else . end) |
    "Name: \(.name) (\(.symbol))",
    "CMC Rank: #\(.cmc_rank // "N/A")",
    "Price: $\(.quote.USD.price // 0 | . * 10000 | round / 10000)",
    "Market Cap: $\(.quote.USD.market_cap // 0 | . / 1e6 | . * 100 | round / 100)M",
    "FDV: $\(.quote.USD.fully_diluted_market_cap // 0 | . / 1e6 | . * 100 | round / 100)M",
    "24h Volume: $\(.quote.USD.volume_24h // 0 | . / 1e6 | . * 100 | round / 100)M",
    "Volume Change 24h: \(.quote.USD.volume_change_24h // 0 | . * 100 | round / 100)%",
    "Market Pairs: \(.num_market_pairs // "N/A")",
    "MCap Dominance: \(.quote.USD.market_cap_dominance // 0 | . * 100 | round / 100)%",
    "",
    "Price Changes:",
    "  1h:  \(.quote.USD.percent_change_1h // 0 | . * 100 | round / 100)%",
    "  24h: \(.quote.USD.percent_change_24h // 0 | . * 100 | round / 100)%",
    "  7d:  \(.quote.USD.percent_change_7d // 0 | . * 100 | round / 100)%",
    "  30d: \(.quote.USD.percent_change_30d // 0 | . * 100 | round / 100)%",
    "  90d: \(.quote.USD.percent_change_90d // 0 | . * 100 | round / 100)%",
    "",
    "Supply:",
    "  Circulating: \(.circulating_supply // 0)",
    "  Total: \(.total_supply // 0)",
    "  Max: \(.max_supply // "Unlimited")",
    "  Infinite Supply: \(.infinite_supply // false)"
  ' 2>/dev/null || echo "⚠️ Failed to parse market data"
fi

# --- 2. Project Info ---
sleep 1
echo ""
echo "📋 Project Info"
echo "---"
INFO_DATA=$(cmc_get "/v2/cryptocurrency/info?id=${CMC_ID}")
I_ERR=$(echo "$INFO_DATA" | jq -r '.status.error_code // 0')

if [[ "$I_ERR" != "0" ]]; then
  echo "⚠️ Failed to fetch info: $(echo "$INFO_DATA" | jq -r '.status.error_message')"
else
  # Description
  DESC=$(echo "$INFO_DATA" | jq -r --arg id "$CMC_ID" '
    .data[$id] // .data[(.data | keys[0])] | .description // "N/A"
  ' 2>/dev/null)
  echo "Description: ${DESC:0:300}..."
  echo ""

  # Tags & dates
  echo "$INFO_DATA" | jq -r --arg id "$CMC_ID" '
    .data[$id] // .data[(.data | keys[0])] |
    "Category: \(.category // "N/A")",
    "Tags: \([.tags // [] | .[] | .name // .] | .[0:10] | join(", "))",
    "Date Added: \(.date_added // "N/A")",
    "Date Launched: \(.date_launched // "N/A")"
  ' 2>/dev/null || true

  # Contract platform
  echo ""
  echo "$INFO_DATA" | jq -r --arg id "$CMC_ID" '
    .data[$id] // .data[(.data | keys[0])] |
    if .platform != null then
      "Contract Platform: \(.platform.name // "N/A")",
      "Contract Address: \(.platform.token_address // "N/A")"
    else
      "Type: Native coin (no parent platform)"
    end
  ' 2>/dev/null || true

  # Key links
  echo ""
  echo "🌐 Links:"
  echo "$INFO_DATA" | jq -r --arg id "$CMC_ID" '
    .data[$id] // .data[(.data | keys[0])] | .urls |
    "  Website: \((.website // [])[:2] | join(", "))",
    "  Explorer: \((.explorer // [])[:2] | join(", "))",
    "  Source Code: \((.source_code // [])[:2] | join(", "))",
    "  Twitter: \((.twitter // [])[:1] | join(", "))",
    "  Reddit: \((.reddit // [])[:1] | join(", "))",
    "  Chat: \((.chat // [])[:2] | join(", "))"
  ' 2>/dev/null || true
fi

# --- 3. Quick Risk Flags ---
echo ""
echo "⚠️ Quick Risk Flags"
echo "---"

if [[ "$Q_ERR" == "0" ]]; then
  echo "$QUOTE_DATA" | jq -r --arg id "$CMC_ID" '
    .data[$id] // .data[(.data | keys[0])] | (if type == "array" then .[0] else . end) |
    .quote.USD as $q |

    (if $q.market_cap > 0 then ($q.volume_24h / $q.market_cap * 10000 | round / 10000) else 0 end) as $vol_mcap |
    "Vol/MCap: \($vol_mcap)",
    (if $vol_mcap < 0.01 then "  🟠 LOW LIQUIDITY — Vol/MCap < 1%" elif $vol_mcap > 0.05 then "  ✅ Healthy liquidity" else "  🟡 Moderate" end),

    (if $q.market_cap > 0 and $q.fully_diluted_market_cap > 0 then ($q.fully_diluted_market_cap / $q.market_cap * 100 | round / 100) else 0 end) as $fdv_mcap |
    "FDV/MCap: \($fdv_mcap)x",
    (if $fdv_mcap > 10 then "  🚩 HIGH — Heavy dilution risk (>10x)" elif $fdv_mcap > 3 then "  🟡 MEDIUM — Moderate dilution (3-10x)" else "  ✅ LOW — Reasonable" end),

    (if (.num_market_pairs // 0) < 5 then "  🟠 Very few market pairs (\(.num_market_pairs // 0))" elif (.num_market_pairs // 0) < 20 then "  🟡 Limited market pairs (\(.num_market_pairs // 0))" else "  ✅ Listed on \(.num_market_pairs // 0) pairs" end),

    (if .infinite_supply == true then "  🟡 Infinite supply — inflationary token" else "" end),

    (if ($q.volume_change_24h // 0) < -50 then "  🟡 Volume dropped \($q.volume_change_24h | . * 100 | round / 100)% in 24h" else "" end)
  ' 2>/dev/null | grep -v '^$' || true
fi

if [[ "$I_ERR" == "0" ]]; then
  SRC=$(echo "$INFO_DATA" | jq -r --arg id "$CMC_ID" '
    .data[$id] // .data[(.data | keys[0])] | .urls.source_code // [] | length
  ' 2>/dev/null || echo "0")
  if [[ "$SRC" == "0" ]]; then
    echo "  🟡 No source code / GitHub link on CMC"
  else
    echo "  ✅ Source code available"
  fi
fi

echo ""
echo "=========================================="
echo "✅ Quick research complete. Run full analysis for deeper insights."
echo "=========================================="
