#!/bin/bash
# compare.sh — Side-by-side comparison of two tokens via CoinMarketCap API
# Usage: ./compare.sh <symbol_a> <symbol_b>
# Example: ./compare.sh AAVE COMP
# Example: ./compare.sh ETH SOL

set -euo pipefail

INPUT_A="${1:?Usage: $0 <symbol_a> <symbol_b>}"
INPUT_B="${2:?Usage: $0 <symbol_a> <symbol_b>}"
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

resolve_id() {
  local input="$1"
  local input_upper
  input_upper=$(echo "$input" | tr '[:lower:]' '[:upper:]')

  local map_data
  map_data=$(cmc_get "/v1/cryptocurrency/map?symbol=${input_upper}&limit=1")
  if [[ $(echo "$map_data" | jq '.data | length // 0') -gt 0 ]]; then
    echo "$map_data" | jq -r '.data[0].id'
    return 0
  fi

  # Try as slug
  map_data=$(cmc_get "/v1/cryptocurrency/map?slug=$(echo "$input" | tr '[:upper:]' '[:lower:]')&limit=1")
  if [[ $(echo "$map_data" | jq '.data | length // 0') -gt 0 ]]; then
    echo "$map_data" | jq -r '.data[0].id'
    return 0
  fi

  echo ""
  return 1
}

echo "=========================================="
echo "⚔️ Token Comparison: $INPUT_A vs $INPUT_B"
echo "=========================================="

# Resolve IDs
echo "Resolving $INPUT_A..."
ID_A=$(resolve_id "$INPUT_A")
if [[ -z "$ID_A" ]]; then echo "❌ Not found: $INPUT_A"; exit 1; fi

sleep 1

echo "Resolving $INPUT_B..."
ID_B=$(resolve_id "$INPUT_B")
if [[ -z "$ID_B" ]]; then echo "❌ Not found: $INPUT_B"; exit 1; fi

# Fetch quotes for both in a single call
sleep 1
echo "Fetching market data..."
QUOTES=$(cmc_get "/v2/cryptocurrency/quotes/latest?id=${ID_A},${ID_B}&convert=USD")
Q_ERR=$(echo "$QUOTES" | jq -r '.status.error_code // 0')

if [[ "$Q_ERR" != "0" ]]; then
  echo "❌ Failed to fetch quotes: $(echo "$QUOTES" | jq -r '.status.error_message')"
  exit 1
fi

# Fetch info for both in a single call
sleep 1
echo "Fetching project info..."
INFOS=$(cmc_get "/v2/cryptocurrency/info?id=${ID_A},${ID_B}")

# Extract data for each token
extract_quote() {
  local id="$1"
  echo "$QUOTES" | jq --arg id "$id" '
    .data[$id] // .data[(.data | keys[] | select(. == $id))] |
    (if type == "array" then .[0] else . end)
  '
}

QA=$(extract_quote "$ID_A")
QB=$(extract_quote "$ID_B")

NAME_A=$(echo "$QA" | jq -r '.name')
NAME_B=$(echo "$QB" | jq -r '.name')
SYM_A=$(echo "$QA" | jq -r '.symbol')
SYM_B=$(echo "$QB" | jq -r '.symbol')

echo ""
echo "📊 $NAME_A ($SYM_A) vs $NAME_B ($SYM_B)"
echo "============================================================"
printf "%-22s | %-22s | %-22s | %s\n" "Metric" "$SYM_A" "$SYM_B" "Winner"
echo "--------------------------------------------------------------"

compare_field() {
  local label="$1"
  local jq_expr="$2"
  local higher_better="${3:-true}"

  local va vb
  va=$(echo "$QA" | jq -r "$jq_expr // 0" 2>/dev/null || echo "0")
  vb=$(echo "$QB" | jq -r "$jq_expr // 0" 2>/dev/null || echo "0")

  local winner=""
  if [[ "$higher_better" == "true" ]]; then
    winner=$(echo "$va $vb" | awk '{if ($1+0 > $2+0) print "A"; else if ($2+0 > $1+0) print "B"; else print "TIE"}')
  else
    winner=$(echo "$va $vb" | awk '{if ($1+0 < $2+0) print "A"; else if ($2+0 < $1+0) print "B"; else print "TIE"}')
  fi

  local winner_label=""
  case "$winner" in
    A) winner_label="◀ $SYM_A" ;;
    B) winner_label="$SYM_B ▶" ;;
    *) winner_label="TIE" ;;
  esac

  printf "%-22s | %-22s | %-22s | %s\n" "$label" "$va" "$vb" "$winner_label"
}

# Market data
compare_field "CMC Rank" ".cmc_rank" "false"
compare_field "Price (USD)" ".quote.USD.price | . * 10000 | round / 10000" "true"
compare_field "Market Cap ($M)" ".quote.USD.market_cap | . / 1e6 | round" "true"
compare_field "FDV ($M)" ".quote.USD.fully_diluted_market_cap | . / 1e6 | round" "false"
compare_field "24h Volume ($M)" ".quote.USD.volume_24h | . / 1e6 | round" "true"
compare_field "MCap Dominance %" ".quote.USD.market_cap_dominance | . * 100 | round / 100" "true"
compare_field "Market Pairs" ".num_market_pairs" "true"

echo ""
echo "📈 PRICE CHANGES"
echo "--------------------------------------------------------------"
compare_field "1h Change %" ".quote.USD.percent_change_1h | . * 100 | round / 100" "true"
compare_field "24h Change %" ".quote.USD.percent_change_24h | . * 100 | round / 100" "true"
compare_field "7d Change %" ".quote.USD.percent_change_7d | . * 100 | round / 100" "true"
compare_field "30d Change %" ".quote.USD.percent_change_30d | . * 100 | round / 100" "true"
compare_field "90d Change %" ".quote.USD.percent_change_90d | . * 100 | round / 100" "true"

echo ""
echo "💰 SUPPLY"
echo "--------------------------------------------------------------"
compare_field "Circulating" ".circulating_supply | round" "false"
compare_field "Total Supply" ".total_supply | round" "false"
compare_field "Max Supply" ".max_supply // 0 | round" "false"

# Vol/MCap and FDV/MCap ratios
echo ""
echo "📐 KEY RATIOS"
echo "--------------------------------------------------------------"

VOL_MCAP_A=$(echo "$QA" | jq 'if .quote.USD.market_cap > 0 then (.quote.USD.volume_24h / .quote.USD.market_cap * 10000 | round / 10000) else 0 end')
VOL_MCAP_B=$(echo "$QB" | jq 'if .quote.USD.market_cap > 0 then (.quote.USD.volume_24h / .quote.USD.market_cap * 10000 | round / 10000) else 0 end')
FDV_MCAP_A=$(echo "$QA" | jq 'if .quote.USD.market_cap > 0 and .quote.USD.fully_diluted_market_cap > 0 then (.quote.USD.fully_diluted_market_cap / .quote.USD.market_cap * 100 | round / 100) else 0 end')
FDV_MCAP_B=$(echo "$QB" | jq 'if .quote.USD.market_cap > 0 and .quote.USD.fully_diluted_market_cap > 0 then (.quote.USD.fully_diluted_market_cap / .quote.USD.market_cap * 100 | round / 100) else 0 end')

WINNER_VM=$(echo "$VOL_MCAP_A $VOL_MCAP_B" | awk '{if ($1+0 > $2+0) print "◀ '"$SYM_A"'"; else if ($2+0 > $1+0) print "'"$SYM_B"' ▶"; else print "TIE"}')
WINNER_FM=$(echo "$FDV_MCAP_A $FDV_MCAP_B" | awk '{if ($1+0 < $2+0) print "◀ '"$SYM_A"'"; else if ($2+0 < $1+0) print "'"$SYM_B"' ▶"; else print "TIE"}')

printf "%-22s | %-22s | %-22s | %s\n" "Vol/MCap" "$VOL_MCAP_A" "$VOL_MCAP_B" "$WINNER_VM"
printf "%-22s | %-22s | %-22s | %s\n" "FDV/MCap (lower=好)" "${FDV_MCAP_A}x" "${FDV_MCAP_B}x" "$WINNER_FM"

# Project info comparison
I_ERR=$(echo "$INFOS" | jq -r '.status.error_code // 0')
if [[ "$I_ERR" == "0" ]]; then
  echo ""
  echo "📋 PROJECT INFO"
  echo "--------------------------------------------------------------"

  IA=$(echo "$INFOS" | jq --arg id "$ID_A" '.data[$id] // .data[(.data | keys[0])]')
  IB=$(echo "$INFOS" | jq --arg id "$ID_B" '.data[$id] // .data[(.data | keys[1])]')

  TAGS_A=$(echo "$IA" | jq -r '[.tags // [] | .[] | .name // .] | .[0:5] | join(", ")' 2>/dev/null || echo "N/A")
  TAGS_B=$(echo "$IB" | jq -r '[.tags // [] | .[] | .name // .] | .[0:5] | join(", ")' 2>/dev/null || echo "N/A")
  SRC_A=$(echo "$IA" | jq -r '.urls.source_code // [] | length' 2>/dev/null || echo "0")
  SRC_B=$(echo "$IB" | jq -r '.urls.source_code // [] | length' 2>/dev/null || echo "0")
  DATE_A=$(echo "$IA" | jq -r '.date_added // "N/A"' 2>/dev/null || echo "N/A")
  DATE_B=$(echo "$IB" | jq -r '.date_added // "N/A"' 2>/dev/null || echo "N/A")

  printf "%-22s | %-22s | %-22s\n" "Tags" "${TAGS_A:0:22}" "${TAGS_B:0:22}"
  printf "%-22s | %-22s | %-22s\n" "Has Source Code" "$([ "$SRC_A" -gt 0 ] && echo "✅ Yes" || echo "❌ No")" "$([ "$SRC_B" -gt 0 ] && echo "✅ Yes" || echo "❌ No")"
  printf "%-22s | %-22s | %-22s\n" "CMC Date Added" "${DATE_A:0:10}" "${DATE_B:0:10}"
  printf "%-22s | %-22s | %-22s\n" "Infinite Supply" "$(echo "$QA" | jq -r '.infinite_supply // false')" "$(echo "$QB" | jq -r '.infinite_supply // false')"
fi

echo ""
echo "=========================================="
echo "✅ Comparison complete."
echo "=========================================="
