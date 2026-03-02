#!/bin/bash
# fundraising-daily.sh — Daily crypto fundraising rounds tracker
# Usage: ./fundraising-daily.sh [mode] [filter]
# Modes:
#   today     — fundraising rounds published today (default)
#   week      — this week's rounds
#   recent    — last 7 days
#   search    — search by keyword (requires filter arg)
#   top       — top raises by amount
# Example: ./fundraising-daily.sh today
# Example: ./fundraising-daily.sh search "AI"
# Example: ./fundraising-daily.sh week
#
# Data sources:
#   Primary: RootData /open/get_fac (2 credits/record, detailed investor info)
#   Fallback: DefiLlama /api/raises (free, no key needed)

set -euo pipefail

MODE="${1:-today}"
FILTER="${2:-}"

RD_KEY="${ROOTDATA_API_KEY:-}"
RD_BASE="https://api.rootdata.com/open"
DL_BASE="https://api.llama.fi"

# ========================
# Helpers
# ========================
fmt_usd() {
  local val="$1"
  if [[ "$val" == "null" || -z "$val" || "$val" == "0" ]]; then echo "N/A"; return; fi
  echo "$val" | awk '{
    v=$1;
    if(v<0) { neg="-"; v=-v } else neg="";
    if(v>=1e9) printf "%s$%.2fB\n", neg, v/1e9;
    else if(v>=1e6) printf "%s$%.2fM\n", neg, v/1e6;
    else if(v>=1e3) printf "%s$%.2fK\n", neg, v/1e3;
    else printf "%s$%.0f\n", neg, v;
  }'
}

now_ts() { date +%s; }
today_start_ts() { date -d "$(date +%Y-%m-%d) 00:00:00" +%s 2>/dev/null || date -d today +%s 2>/dev/null || echo "$(( $(now_ts) - $(now_ts) % 86400 ))"; }
days_ago_ts() { echo "$(( $(now_ts) - $1 * 86400 ))"; }

# Millisecond timestamps for RootData
now_ms() { echo "$(( $(now_ts) * 1000 ))"; }
days_ago_ms() { echo "$(( $(days_ago_ts "$1") * 1000 ))"; }

echo "=========================================="
echo "💰 Crypto Fundraising Daily"
echo "=========================================="
echo "  Mode: $MODE"
echo "  Date: $(date '+%Y-%m-%d %H:%M UTC')"
echo ""

# ========================
# RootData Fundraising
# ========================
do_rootdata_fundraising() {
  local begin_ms="$1"
  local end_ms="$2"
  local page="${3:-1}"
  local page_size="${4:-20}"

  if [[ -z "$RD_KEY" ]]; then
    echo "⚠️ ROOTDATA_API_KEY not set — skipping RootData"
    echo "   Apply at: https://www.rootdata.com/Api"
    return 1
  fi

  echo "📡 Fetching from RootData..."
  echo ""

  local body
  if [[ -n "$begin_ms" && -n "$end_ms" ]]; then
    body="{\"begin_time\": $begin_ms, \"end_time\": $end_ms, \"page\": $page, \"page_size\": $page_size}"
  else
    body="{\"page\": $page, \"page_size\": $page_size}"
  fi

  local data
  data=$(curl -s --max-time 20 -X POST \
    -H "apikey: $RD_KEY" \
    -H "language: en" \
    -H "Content-Type: application/json" \
    -d "$body" \
    "${RD_BASE}/get_fac" 2>/dev/null)

  local code
  code=$(echo "$data" | jq -r '.result // 0' 2>/dev/null)
  if [[ "$code" != "200" ]]; then
    local msg
    msg=$(echo "$data" | jq -r '.message // "Unknown error"' 2>/dev/null)
    echo "❌ RootData API error ($code): $msg"
    return 1
  fi

  local total
  total=$(echo "$data" | jq -r '.data.total // 0' 2>/dev/null)
  local count
  count=$(echo "$data" | jq '.data.items // [] | length' 2>/dev/null)

  echo "📊 Found $total total rounds (showing $count)"
  echo ""

  if [[ "$count" -eq 0 ]]; then
    echo "  No fundraising rounds found for this period."
    return 0
  fi

  # Display each round
  echo "$data" | jq -r '.data.items[] |
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
    "🏷️ \(.name // "Unknown")",
    "  Round: \(.rounds // "N/A")",
    "  Amount: $\((.amount // 0) | if . >= 1e6 then (. / 1e6 | . * 100 | round / 100 | tostring) + "M" elif . >= 1e3 then (. / 1e3 | round | tostring) + "K" else tostring end)",
    "  Valuation: $\((.valuation // 0) | if . == 0 then "N/A" elif . >= 1e9 then (. / 1e9 | . * 100 | round / 100 | tostring) + "B" elif . >= 1e6 then (. / 1e6 | . * 100 | round / 100 | tostring) + "M" else tostring end)",
    "  Date: \(.published_time // "N/A")",
    "  Investors: \(.invests // [] | map(.name) | join(", ") | if . == "" then "N/A" else . end)"
  ' 2>/dev/null

  # Summary stats
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "📈 Summary:"

  # Total amount raised
  local total_amount
  total_amount=$(echo "$data" | jq '[.data.items[].amount // 0] | add // 0' 2>/dev/null)
  echo "  Total Amount: $(fmt_usd "$total_amount")"

  # Round type breakdown
  echo ""
  echo "  Round Types:"
  echo "$data" | jq -r '.data.items | group_by(.rounds // "Unknown") | map({round: .[0].rounds // "Unknown", count: length, total: (map(.amount // 0) | add)}) | sort_by(-.total)[] |
    "    \(.round): \(.count) rounds — $\(.total | if . >= 1e6 then (. / 1e6 | . * 100 | round / 100 | tostring) + "M" else (. / 1e3 | round | tostring) + "K" end)"
  ' 2>/dev/null || true

  # Most active investors in this batch
  echo ""
  echo "  Top Investors (this batch):"
  echo "$data" | jq -r '[.data.items[].invests // [] | .[]] | group_by(.name) | map({name: .[0].name, count: length}) | sort_by(-.count)[:10][] |
    "    \(.name): \(.count) deals"
  ' 2>/dev/null || true

  return 0
}

# ========================
# DefiLlama Raises (fallback)
# ========================
do_defillama_raises() {
  local days="$1"
  local keyword="${2:-}"

  echo "📡 Fetching from DefiLlama raises..."
  echo ""

  local data
  data=$(curl -s --max-time 20 "${DL_BASE}/raises" 2>/dev/null)

  if [[ -z "$data" ]] || ! echo "$data" | jq -e '.' &>/dev/null 2>&1; then
    echo "❌ DefiLlama raises endpoint unavailable"
    echo "   Check manually: https://defillama.com/raises"
    return 1
  fi

  local total_all
  total_all=$(echo "$data" | jq 'if type == "object" then .raises // [] | length elif type == "array" then length else 0 end' 2>/dev/null)
  
  # Normalize: DL might return {raises: [...]} or just [...]
  local raises_json
  raises_json=$(echo "$data" | jq 'if type == "object" then .raises // [] elif type == "array" then . else [] end' 2>/dev/null)

  if [[ "$total_all" -eq 0 ]]; then
    echo "⚠️ No raises data available from DefiLlama"
    return 1
  fi

  # Filter by date
  local cutoff_ts
  cutoff_ts=$(days_ago_ts "$days")
  
  local filtered
  if [[ -n "$keyword" ]]; then
    # Filter by keyword + date
    local kw_lower
    kw_lower=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')
    filtered=$(echo "$raises_json" | jq --arg cutoff "$cutoff_ts" --arg kw "$kw_lower" '
      [.[] | select(
        (.date // 0 | tonumber) >= ($cutoff | tonumber) and
        ((.name // "" | ascii_downcase | contains($kw)) or
         (.category // "" | ascii_downcase | contains($kw)) or
         (.chains // [] | map(ascii_downcase) | any(contains($kw))) or
         (.leadInvestors // [] | map(ascii_downcase) | any(contains($kw))))
      )] | sort_by(-.date)[:30]
    ' 2>/dev/null)
  else
    # Filter by date only
    filtered=$(echo "$raises_json" | jq --arg cutoff "$cutoff_ts" '
      [.[] | select((.date // 0 | tonumber) >= ($cutoff | tonumber))]
      | sort_by(-.date)[:30]
    ' 2>/dev/null)
  fi

  local count
  count=$(echo "$filtered" | jq 'length' 2>/dev/null)

  echo "📊 Found $count raises in last ${days} days${keyword:+ matching \"$keyword\"}"
  echo ""

  if [[ "$count" -eq 0 ]]; then
    echo "  No matching raises found."
    echo "  Browse all: https://defillama.com/raises"
    return 0
  fi

  # Display
  echo "$filtered" | jq -r '.[] |
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
    "🏷️ \(.name // "Unknown")",
    "  Round: \(.round // "N/A")",
    "  Amount: $\((.amount // 0) | if . >= 1e6 then (. / 1e6 | . * 100 | round / 100 | tostring) + "M" elif . >= 1e3 then (. / 1e3 | round | tostring) + "K" elif . > 0 then tostring else "Undisclosed" end)",
    "  Valuation: $\((.valuation // 0) | if . == 0 then "N/A" elif . >= 1e9 then (. / 1e9 | . * 100 | round / 100 | tostring) + "B" elif . >= 1e6 then (. / 1e6 | . * 100 | round / 100 | tostring) + "M" else tostring end)",
    "  Category: \(.category // "N/A")",
    "  Chains: \(.chains // [] | join(", ") | if . == "" then "N/A" else . end)",
    "  Lead: \(.leadInvestors // [] | join(", ") | if . == "" then "N/A" else . end)",
    "  Other: \(.otherInvestors // [] | join(", ") | if . == "" then "—" else .[:120] end)",
    "  Date: \((.date // 0) | todate | split("T")[0])",
    "  Source: \(.source // "N/A")"
  ' 2>/dev/null

  # Summary
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "📈 Summary:"
  
  local total_amount
  total_amount=$(echo "$filtered" | jq '[.[].amount // 0] | add // 0' 2>/dev/null)
  echo "  Total Disclosed Amount: $(fmt_usd "$total_amount")"
  echo "  Rounds: $count"

  # By round type
  echo ""
  echo "  By Round Type:"
  echo "$filtered" | jq -r 'group_by(.round // "Unknown") | map({round: .[0].round // "Unknown", count: length, total: (map(.amount // 0) | add)}) | sort_by(-.count)[] |
    "    \(.round): \(.count) rounds — $\(.total | if . >= 1e6 then (. / 1e6 | . * 100 | round / 100 | tostring) + "M" elif . >= 1e3 then (. / 1e3 | round | tostring) + "K" else "0" end)"
  ' 2>/dev/null || true

  # By category
  echo ""
  echo "  By Category (top 10):"
  echo "$filtered" | jq -r 'group_by(.category // "Other") | map({cat: .[0].category // "Other", count: length, total: (map(.amount // 0) | add)}) | sort_by(-.total)[:10][] |
    "    \(.cat): \(.count) rounds — $\(.total | if . >= 1e6 then (. / 1e6 | . * 100 | round / 100 | tostring) + "M" elif . >= 1e3 then (. / 1e3 | round | tostring) + "K" else "0" end)"
  ' 2>/dev/null || true

  # Most active lead investors
  echo ""
  echo "  Most Active Lead Investors:"
  echo "$filtered" | jq -r '[.[].leadInvestors // [] | .[]] | group_by(.) | map({name: .[0], count: length}) | sort_by(-.count)[:10][] |
    "    \(.name): \(.count) deals"
  ' 2>/dev/null || true

  # Largest raises
  echo ""
  echo "  🏆 Largest Raises:"
  echo "$filtered" | jq -r 'sort_by(-.amount)[:5][] |
    "    \(.name // "Unknown") — $\((.amount // 0) | if . >= 1e6 then (. / 1e6 | . * 100 | round / 100 | tostring) + "M" elif . >= 1e3 then (. / 1e3 | round | tostring) + "K" else "Undisclosed" end) (\(.round // "N/A"))"
  ' 2>/dev/null || true

  echo ""
  echo "📊 Full list: https://defillama.com/raises"
  echo "📊 RootData:  https://www.rootdata.com/Fundraising"
}

# ========================
# Main
# ========================
case "$MODE" in
  today)
    echo "📅 Today's Fundraising Rounds"
    echo "---"
    if [[ -n "$RD_KEY" ]]; then
      do_rootdata_fundraising "$(days_ago_ms 1)" "$(now_ms)" 1 20
    fi
    echo ""
    do_defillama_raises 1
    ;;

  week)
    echo "📅 This Week's Fundraising Rounds"
    echo "---"
    if [[ -n "$RD_KEY" ]]; then
      do_rootdata_fundraising "$(days_ago_ms 7)" "$(now_ms)" 1 30
    fi
    echo ""
    do_defillama_raises 7
    ;;

  recent)
    echo "📅 Recent Fundraising (last 7 days)"
    echo "---"
    do_defillama_raises 7
    ;;

  search)
    if [[ -z "$FILTER" ]]; then
      echo "❌ Usage: $0 search <keyword>"
      echo "   Example: $0 search AI"
      echo "   Example: $0 search DeFi"
      echo "   Example: $0 search Solana"
      exit 1
    fi
    echo "🔍 Searching fundraising for: $FILTER (last 30 days)"
    echo "---"
    # RootData search first
    if [[ -n "$RD_KEY" ]]; then
      echo "📡 RootData search..."
      local_search=$(curl -s --max-time 15 -X POST \
        -H "apikey: $RD_KEY" \
        -H "language: en" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"$FILTER\"}" \
        "${RD_BASE}/ser_inv" 2>/dev/null)

      local_count=$(echo "$local_search" | jq '[.data[] | select(.type == 1)] | length' 2>/dev/null || echo "0")
      if [[ "$local_count" -gt 0 ]]; then
        echo "  Found $local_count projects matching '$FILTER' on RootData"
        echo "$local_search" | jq -r '[.data[] | select(.type == 1)][:5][] |
          "  • \(.name) (ID: \(.id)) — \(.introduce[:80] // "")..."
        ' 2>/dev/null || true
        echo ""
      fi
    fi
    do_defillama_raises 30 "$FILTER"
    ;;

  top)
    echo "🏆 Top Fundraising Rounds (last 30 days by amount)"
    echo "---"
    do_defillama_raises 30
    ;;

  *)
    echo "Unknown mode: $MODE"
    echo ""
    echo "Usage: $0 [mode] [filter]"
    echo ""
    echo "Modes:"
    echo "  today    — today's rounds (default)"
    echo "  week     — this week's rounds"
    echo "  recent   — last 7 days"
    echo "  search   — search by keyword (e.g., $0 search AI)"
    echo "  top      — top raises by amount (last 30 days)"
    exit 1
    ;;
esac

echo ""
echo "=========================================="
echo "✅ Fundraising scan complete."
echo "=========================================="
echo ""
echo "📌 Other sources to check:"
echo "  RootData:    https://www.rootdata.com/Fundraising"
echo "  CryptoRank:  https://cryptorank.io/funding-rounds"
echo "  DefiLlama:   https://defillama.com/raises"
echo "  Messari:     https://messari.io/screener/fundraising"
