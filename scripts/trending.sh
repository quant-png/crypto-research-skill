#!/bin/bash
# trending.sh — Market overview via CoinMarketCap API
# Usage: ./trending.sh

set -euo pipefail

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
echo "🔥 Crypto Market Overview (CoinMarketCap)"
echo "=========================================="

# --- 1. Global Metrics ---
echo ""
echo "🌍 Global Market"
echo "---"
GLOBAL=$(cmc_get "/v1/global-metrics/quotes/latest?convert=USD")
G_ERR=$(echo "$GLOBAL" | jq -r '.status.error_code // 0')

if [[ "$G_ERR" != "0" ]]; then
  echo "⚠️ Failed to fetch global metrics"
else
  echo "$GLOBAL" | jq -r '.data |
    "Total Market Cap: $\(.quote.USD.total_market_cap / 1e9 | . * 100 | round / 100)B",
    "Total 24h Volume: $\(.quote.USD.total_volume_24h / 1e9 | . * 100 | round / 100)B",
    "BTC Dominance: \(.btc_dominance | . * 100 | round / 100)%",
    "ETH Dominance: \(.eth_dominance | . * 100 | round / 100)%",
    "Active Cryptos: \(.active_cryptocurrencies)",
    "Active Exchanges: \(.active_exchanges)",
    "Active Market Pairs: \(.active_market_pairs)",
    "",
    "DeFi Market Cap: $\(.quote.USD.defi_market_cap / 1e9 | . * 100 | round / 100)B",
    "DeFi 24h Volume: $\(.quote.USD.defi_volume_24h / 1e9 | . * 100 | round / 100)B",
    "Stablecoin 24h Vol: $\(.quote.USD.stablecoin_volume_24h / 1e9 | . * 100 | round / 100)B"
  ' 2>/dev/null || echo "⚠️ Failed to parse global data"
fi

# --- 2. Fear & Greed ---
sleep 1
echo ""
echo "😱📈 Fear & Greed Index"
echo "---"
FG=$(cmc_get "/v3/fear-and-greed/latest")
FG_ERR=$(echo "$FG" | jq -r '.status.error_code // 0')

if [[ "$FG_ERR" != "0" ]]; then
  echo "⚠️ Failed to fetch Fear & Greed"
else
  FG_VAL=$(echo "$FG" | jq -r '.data.value // "N/A"')
  FG_CLASS=$(echo "$FG" | jq -r '.data.value_classification // "N/A"')
  echo "Value: $FG_VAL / 100 — $FG_CLASS"

  if [[ "$FG_VAL" != "N/A" ]]; then
    BAR=""
    FILLED=$((FG_VAL / 5))
    for ((i=0; i<20; i++)); do
      if [[ $i -lt $FILLED ]]; then BAR+="█"; else BAR+="░"; fi
    done
    echo "[$BAR] $FG_VAL"
  fi
fi

# --- 3. Top 15 by Market Cap ---
sleep 1
echo ""
echo "📈 Top 15 by Market Cap"
echo "---"
LISTINGS=$(cmc_get "/v1/cryptocurrency/listings/latest?limit=15&convert=USD")
L_ERR=$(echo "$LISTINGS" | jq -r '.status.error_code // 0')

if [[ "$L_ERR" != "0" ]]; then
  echo "⚠️ Failed to fetch listings"
else
  echo "$LISTINGS" | jq -r '
    .data[] |
    "#\(.cmc_rank) \(.name) (\(.symbol)): $\(.quote.USD.price | . * 10000 | round / 10000) | MCap: $\(.quote.USD.market_cap / 1e9 | . * 100 | round / 100)B | 1h: \(.quote.USD.percent_change_1h | . * 100 | round / 100)% | 24h: \(.quote.USD.percent_change_24h | . * 100 | round / 100)% | 7d: \(.quote.USD.percent_change_7d | . * 100 | round / 100)%"
  ' 2>/dev/null || echo "⚠️ Failed to parse listings"
fi

# --- 4. Top Categories ---
sleep 1
echo ""
echo "🏷️ Top Crypto Categories"
echo "---"
CATS=$(cmc_get "/v1/cryptocurrency/categories?limit=10")
C_ERR=$(echo "$CATS" | jq -r '.status.error_code // 0')

if [[ "$C_ERR" != "0" ]]; then
  echo "⚠️ Failed to fetch categories"
else
  echo "$CATS" | jq -r '
    .data[:10][] |
    "\(.name): \(.num_tokens) tokens | MCap: $\((.market_cap // 0) / 1e9 | . * 100 | round / 100)B | Vol: $\((.volume // 0) / 1e9 | . * 100 | round / 100)B | 24h: \((.volume_change // 0) | . * 100 | round / 100)%"
  ' 2>/dev/null || echo "⚠️ Failed to parse categories"
fi

# --- 5. DefiLlama Top Protocols (no key needed, complements CMC) ---
echo ""
echo "🏦 Top DeFi Protocols by TVL (DefiLlama)"
echo "---"
curl -s "https://api.llama.fi/protocols" 2>/dev/null | jq -r '
  [.[:10] | .[] | {
    name: .name,
    tvl: (.tvl / 1e9 | . * 100 | round / 100),
    category: .category,
    chains: (.chains | length)
  }]
  | .[]
  | "\(.name): $\(.tvl)B TVL | \(.category) | \(.chains) chains"
' 2>/dev/null || echo "⚠️ DefiLlama unavailable"

echo ""
echo "=========================================="
echo "✅ Market overview complete. Use 'research <token>' for deep dives."
echo "=========================================="
