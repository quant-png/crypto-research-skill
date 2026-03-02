#!/bin/bash
# cmc-research.sh — CoinMarketCap project info, quotes, and market data
# Usage: ./cmc-research.sh <symbol_or_slug> [mode]
# Modes: full (default), info, quote, global, fear
# Example: ./cmc-research.sh ETH
# Example: ./cmc-research.sh ethereum info
# Example: ./cmc-research.sh "" global
# Example: ./cmc-research.sh "" fear

set -euo pipefail

INPUT="${1:?Usage: $0 <symbol_or_slug> [mode: full|info|quote|global|fear]}"
MODE="${2:-full}"
CMC_KEY="${CMC_PRO_API_KEY:-}"
CMC_BASE="https://pro-api.coinmarketcap.com"

if [[ -z "$CMC_KEY" ]]; then
  echo "❌ CMC_PRO_API_KEY is not set."
  echo "Get a free key at: https://pro.coinmarketcap.com"
  echo "Then: export CMC_PRO_API_KEY=\"your_key_here\""
  exit 1
fi

cmc_get() {
  local endpoint="$1"
  curl -s "${CMC_BASE}${endpoint}" \
    -H "X-CMC_PRO_API_KEY: $CMC_KEY" \
    -H "Accept: application/json" 2>/dev/null
}

check_error() {
  local data="$1"
  local err_code
  err_code=$(echo "$data" | jq -r '.status.error_code // 0')
  if [[ "$err_code" != "0" ]]; then
    local err_msg
    err_msg=$(echo "$data" | jq -r '.status.error_message // "Unknown error"')
    echo "❌ CMC API Error ($err_code): $err_msg"
    return 1
  fi
  return 0
}

# --- Global Market Metrics ---
do_global() {
  echo ""
  echo "🌍 Global Market Metrics (CoinMarketCap)"
  echo "=========================================="
  local data
  data=$(cmc_get "/v1/global-metrics/quotes/latest?convert=USD")
  check_error "$data" || return

  echo "$data" | jq -r '.data | 
    "Active Cryptocurrencies: \(.active_cryptocurrencies)",
    "Active Exchanges: \(.active_exchanges)",
    "Active Market Pairs: \(.active_market_pairs)",
    "",
    "BTC Dominance: \(.btc_dominance | . * 100 | round / 100)%",
    "ETH Dominance: \(.eth_dominance | . * 100 | round / 100)%",
    "",
    "Total Market Cap: $\(.quote.USD.total_market_cap / 1e9 | . * 100 | round / 100)B",
    "Total 24h Volume: $\(.quote.USD.total_volume_24h / 1e9 | . * 100 | round / 100)B",
    "DeFi Market Cap: $\(.quote.USD.defi_market_cap / 1e9 | . * 100 | round / 100)B",
    "DeFi 24h Volume: $\(.quote.USD.defi_volume_24h / 1e9 | . * 100 | round / 100)B",
    "Stablecoin 24h Vol: $\(.quote.USD.stablecoin_volume_24h / 1e9 | . * 100 | round / 100)B",
    "",
    "Last Updated: \(.last_updated)"
  ' 2>/dev/null || echo "⚠️ Failed to parse global metrics"
}

# --- Fear & Greed Index ---
do_fear_greed() {
  echo ""
  echo "😱📈 Fear & Greed Index (CoinMarketCap)"
  echo "=========================================="
  local data
  data=$(cmc_get "/v3/fear-and-greed/latest")
  check_error "$data" || return

  local value classification
  value=$(echo "$data" | jq -r '.data.value // "N/A"')
  classification=$(echo "$data" | jq -r '.data.value_classification // "N/A"')

  echo "Current Value: $value / 100"
  echo "Classification: $classification"

  # Visual gauge
  if [[ "$value" != "N/A" ]]; then
    local bar=""
    local filled=$((value / 5))
    for ((i=0; i<20; i++)); do
      if [[ $i -lt $filled ]]; then bar+="█"; else bar+="░"; fi
    done
    echo "Gauge: [$bar] $value"
    echo ""
    if [[ "$value" -le 25 ]]; then
      echo "💡 Extreme Fear — historically a good buying opportunity"
    elif [[ "$value" -le 45 ]]; then
      echo "💡 Fear — market is cautious"
    elif [[ "$value" -le 55 ]]; then
      echo "💡 Neutral — market is balanced"
    elif [[ "$value" -le 75 ]]; then
      echo "💡 Greed — market may be overheated"
    else
      echo "💡 Extreme Greed — historically a sell signal"
    fi
  fi
}

# --- Resolve CMC ID ---
resolve_id() {
  local input="$1"
  local input_upper
  input_upper=$(echo "$input" | tr '[:lower:]' '[:upper:]')

  # Try as symbol first
  local map_data
  map_data=$(cmc_get "/v1/cryptocurrency/map?symbol=${input_upper}&limit=3")

  if check_error "$map_data" 2>/dev/null; then
    local count
    count=$(echo "$map_data" | jq '.data | length')
    if [[ "$count" -gt 0 ]]; then
      CMC_ID=$(echo "$map_data" | jq -r '.data[0].id')
      CMC_SLUG=$(echo "$map_data" | jq -r '.data[0].slug')
      CMC_SYMBOL=$(echo "$map_data" | jq -r '.data[0].symbol')
      CMC_NAME=$(echo "$map_data" | jq -r '.data[0].name')
      return 0
    fi
  fi

  # Try as slug
  map_data=$(cmc_get "/v1/cryptocurrency/map?slug=${input}&limit=1")
  if check_error "$map_data" 2>/dev/null; then
    local count
    count=$(echo "$map_data" | jq '.data | length')
    if [[ "$count" -gt 0 ]]; then
      CMC_ID=$(echo "$map_data" | jq -r '.data[0].id')
      CMC_SLUG=$(echo "$map_data" | jq -r '.data[0].slug')
      CMC_SYMBOL=$(echo "$map_data" | jq -r '.data[0].symbol')
      CMC_NAME=$(echo "$map_data" | jq -r '.data[0].name')
      return 0
    fi
  fi

  echo "❌ Token not found: $input"
  echo "Try the exact symbol (e.g., BTC, ETH) or slug (e.g., bitcoin, ethereum)"
  return 1
}

# --- Project Info ---
do_info() {
  echo ""
  echo "📋 Project Info: $CMC_NAME ($CMC_SYMBOL)"
  echo "=========================================="
  local data
  data=$(cmc_get "/v2/cryptocurrency/info?id=${CMC_ID}")
  check_error "$data" || return

  # Basic metadata
  echo "$data" | jq -r --arg id "$CMC_ID" '
    .data[$id] // .data[(.data | keys[0])] |
    "Name: \(.name) (\(.symbol))",
    "Slug: \(.slug)",
    "Category: \(.category // "N/A")",
    "Date Added to CMC: \(.date_added // "N/A")",
    "Date Launched: \(.date_launched // "N/A")",
    "Infinite Supply: \(.infinite_supply // false)",
    "Self-Reported Circulating: \(.self_reported_circulating_supply // "N/A")",
    "Self-Reported MCap: \(.self_reported_market_cap // "N/A")",
    ""
  ' 2>/dev/null

  # Description
  echo "📝 Description:"
  echo "---"
  echo "$data" | jq -r --arg id "$CMC_ID" '
    .data[$id] // .data[(.data | keys[0])] |
    .description // "No description available"
  ' 2>/dev/null | head -20
  echo "..."

  # Tags
  echo ""
  echo "🏷️ Tags:"
  echo "$data" | jq -r --arg id "$CMC_ID" '
    .data[$id] // .data[(.data | keys[0])] |
    [.tags // [] | .[] | .name // .] | join(", ")
  ' 2>/dev/null || echo "N/A"

  # Platform / Contract
  echo ""
  echo "🔗 Contract Platform:"
  echo "$data" | jq -r --arg id "$CMC_ID" '
    .data[$id] // .data[(.data | keys[0])] |
    if .platform != null then
      "Chain: \(.platform.name // "N/A")",
      "Contract: \(.platform.token_address // "N/A")"
    else
      "Native coin (no parent platform)"
    end
  ' 2>/dev/null

  # URLs
  echo ""
  echo "🌐 Official Links:"
  echo "$data" | jq -r --arg id "$CMC_ID" '
    .data[$id] // .data[(.data | keys[0])] | .urls |
    "Website: \(.website // ["N/A"] | join(", "))",
    "Explorer: \(.explorer // ["N/A"] | join(", "))",
    "Source Code: \(.source_code // ["N/A"] | join(", "))",
    "Twitter: \(.twitter // ["N/A"] | join(", "))",
    "Reddit: \(.reddit // ["N/A"] | join(", "))",
    "Chat: \(.chat // ["N/A"] | join(", "))",
    "Announcement: \(.announcement // ["N/A"] | join(", "))",
    "Message Board: \(.message_board // ["N/A"] | join(", "))",
    "Technical Doc: \(.technical_doc // ["N/A"] | join(", "))"
  ' 2>/dev/null
}

# --- Quotes / Market Data ---
do_quote() {
  echo ""
  echo "📊 Market Data: $CMC_NAME ($CMC_SYMBOL)"
  echo "=========================================="
  local data
  data=$(cmc_get "/v2/cryptocurrency/quotes/latest?id=${CMC_ID}&convert=USD")
  check_error "$data" || return

  echo "$data" | jq -r --arg id "$CMC_ID" '
    .data[$id] // .data[(.data | keys[0])] | .[0] // . |
    "CMC Rank: #\(.cmc_rank // "N/A")",
    "Price: $\(.quote.USD.price // 0 | . * 10000 | round / 10000)",
    "Market Cap: $\(.quote.USD.market_cap // 0 | . / 1e6 | . * 100 | round / 100)M",
    "FDV: $\(.quote.USD.fully_diluted_market_cap // 0 | . / 1e6 | . * 100 | round / 100)M",
    "24h Volume: $\(.quote.USD.volume_24h // 0 | . / 1e6 | . * 100 | round / 100)M",
    "Volume Change 24h: \(.quote.USD.volume_change_24h // 0 | . * 100 | round / 100)%",
    "MCap Dominance: \(.quote.USD.market_cap_dominance // 0 | . * 100 | round / 100)%",
    "",
    "📈 Price Changes:",
    "  1h:  \(.quote.USD.percent_change_1h // 0 | . * 100 | round / 100)%",
    "  24h: \(.quote.USD.percent_change_24h // 0 | . * 100 | round / 100)%",
    "  7d:  \(.quote.USD.percent_change_7d // 0 | . * 100 | round / 100)%",
    "  30d: \(.quote.USD.percent_change_30d // 0 | . * 100 | round / 100)%",
    "  90d: \(.quote.USD.percent_change_90d // 0 | . * 100 | round / 100)%",
    "",
    "💰 Supply:",
    "  Circulating: \(.circulating_supply // 0)",
    "  Total: \(.total_supply // 0)",
    "  Max: \(.max_supply // "Unlimited")",
    "  Infinite Supply: \(.infinite_supply // false)",
    "",
    "🏪 Market Pairs: \(.num_market_pairs // "N/A")",
    "Last Updated: \(.quote.USD.last_updated // "N/A")"
  ' 2>/dev/null || echo "⚠️ Failed to parse quote data"

  # Vol/MCap and FDV/MCap ratios
  echo ""
  echo "📐 Key Ratios:"
  echo "$data" | jq -r --arg id "$CMC_ID" '
    .data[$id] // .data[(.data | keys[0])] | .[0] // . |
    .quote.USD as $q |
    (if $q.market_cap > 0 then ($q.volume_24h / $q.market_cap * 10000 | round / 10000) else 0 end) as $vol_mcap |
    (if $q.market_cap > 0 and $q.fully_diluted_market_cap > 0 then ($q.fully_diluted_market_cap / $q.market_cap * 100 | round / 100) else 0 end) as $fdv_mcap |
    "Vol/MCap: \($vol_mcap)",
    (if $vol_mcap < 0.01 then "  🟠 LOW LIQUIDITY" elif $vol_mcap > 0.05 then "  ✅ Healthy liquidity" else "  🟡 Moderate" end),
    "FDV/MCap: \($fdv_mcap)x",
    (if $fdv_mcap > 10 then "  🚩 HIGH dilution risk" elif $fdv_mcap > 3 then "  🟡 Moderate dilution" else "  ✅ Reasonable" end)
  ' 2>/dev/null
}

# ========================
# Main Execution
# ========================

echo "=========================================="
echo "🔍 CoinMarketCap Research"
echo "=========================================="

case "$MODE" in
  global)
    do_global
    ;;
  fear)
    do_fear_greed
    ;;
  *)
    resolve_id "$INPUT" || exit 1
    echo "Resolved: $CMC_NAME ($CMC_SYMBOL) — CMC ID: $CMC_ID, Slug: $CMC_SLUG"

    case "$MODE" in
      info)
        do_info
        ;;
      quote)
        do_quote
        ;;
      full)
        do_info
        sleep 1  # respect rate limit
        do_quote
        sleep 1
        do_fear_greed
        ;;
      *)
        echo "Unknown mode: $MODE"
        echo "Usage: $0 <symbol_or_slug> [full|info|quote|global|fear]"
        exit 1
        ;;
    esac
    ;;
esac

echo ""
echo "=========================================="
echo "✅ CMC research complete."
echo "=========================================="
