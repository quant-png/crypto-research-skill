#!/bin/bash
# defillama-research.sh — TVL, Fees, Revenue data from DefiLlama
# Usage: ./defillama-research.sh <protocol_slug> [mode]
# Modes: full (default), tvl, fees, revenue
# Example: ./defillama-research.sh aave
# Example: ./defillama-research.sh uniswap fees
# No API key required!

set -euo pipefail

INPUT="${1:?Usage: $0 <protocol_slug> [mode: full|tvl|fees|revenue]}"
MODE="${2:-full}"
SLUG=$(echo "$INPUT" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

DL_BASE="https://api.llama.fi"

fmt_usd() {
  local val="$1"
  if [[ "$val" == "null" || -z "$val" ]]; then echo "N/A"; return; fi
  echo "$val" | awk '{
    v=$1;
    if(v<0) { neg="-"; v=-v } else neg="";
    if(v>=1e9) printf "%s$%.2fB\n", neg, v/1e9;
    else if(v>=1e6) printf "%s$%.2fM\n", neg, v/1e6;
    else if(v>=1e3) printf "%s$%.2fK\n", neg, v/1e3;
    else printf "%s$%.2f\n", neg, v;
  }'
}

fmt_pct() {
  local val="$1"
  if [[ "$val" == "null" || -z "$val" ]]; then echo "N/A"; return; fi
  printf "%.2f%%" "$val"
}

echo "=========================================="
echo "📊 DefiLlama Research: $SLUG"
echo "=========================================="

# ========================
# TVL Data
# ========================
do_tvl() {
  echo ""
  echo "🔒 TVL Data"
  echo "---"

  local data
  data=$(curl -s "${DL_BASE}/protocol/${SLUG}" 2>/dev/null)

  # Check if valid
  if echo "$data" | jq -e '.name' &>/dev/null; then
    local name category chains tvl
    name=$(echo "$data" | jq -r '.name // "N/A"')
    category=$(echo "$data" | jq -r '.category // "N/A"')
    chains=$(echo "$data" | jq -r '.chains // [] | join(", ")')
    tvl=$(echo "$data" | jq -r '.currentChainTvls | to_entries | map(select(.key | test("^[A-Z]"))) | map(.value) | add // 0')

    echo "Protocol: $name"
    echo "Category: $category"
    echo "Chains: $chains"
    echo "Total TVL: $(fmt_usd "$tvl")"

    # Chain breakdown (top 5)
    echo ""
    echo "TVL by Chain (top 5):"
    echo "$data" | jq -r '
      .currentChainTvls | to_entries
      | map(select(.key | test("^[A-Z]")))
      | sort_by(-.value)[:5][]
      | "  \(.key): $\(.value / 1e6 | . * 100 | round / 100)M"
    ' 2>/dev/null || echo "  [Chain breakdown unavailable]"

    # TVL changes (from recent history)
    local tvl_history_len
    tvl_history_len=$(echo "$data" | jq '.tvl | length // 0')
    if [[ "$tvl_history_len" -gt 30 ]]; then
      local current_tvl day7_tvl day30_tvl
      current_tvl=$(echo "$data" | jq '.tvl[-1].totalLiquidityUSD // 0')
      day7_tvl=$(echo "$data" | jq '.tvl[-8].totalLiquidityUSD // 0')
      day30_tvl=$(echo "$data" | jq '.tvl[-31].totalLiquidityUSD // 0')

      if [[ "$day7_tvl" != "0" && "$day7_tvl" != "null" ]]; then
        local change_7d
        change_7d=$(echo "$current_tvl $day7_tvl" | awk '{printf "%.2f", ($1-$2)/$2*100}')
        echo ""
        echo "TVL Change 7d: ${change_7d}%"
      fi
      if [[ "$day30_tvl" != "0" && "$day30_tvl" != "null" ]]; then
        local change_30d
        change_30d=$(echo "$current_tvl $day30_tvl" | awk '{printf "%.2f", ($1-$2)/$2*100}')
        echo "TVL Change 30d: ${change_30d}%"
      fi
    fi

    # Raises (funding from DefiLlama)
    local raises_count
    raises_count=$(echo "$data" | jq '.raises // [] | length')
    if [[ "$raises_count" -gt 0 ]]; then
      echo ""
      echo "💰 Funding Rounds (from DefiLlama):"
      echo "$data" | jq -r '.raises[] |
        "  \(.date // "N/A"): $\((.amount // 0) / 1e6 | . * 100 | round / 100)M — \(.round // "N/A") — investors: \(.leadInvestors // [] | join(", "))"
      ' 2>/dev/null || true
    fi

    # Description
    local desc
    desc=$(echo "$data" | jq -r '.description // ""')
    if [[ -n "$desc" && "$desc" != "null" ]]; then
      echo ""
      echo "📝 Description: ${desc:0:300}"
    fi

    # Social links
    local url twitter
    url=$(echo "$data" | jq -r '.url // "N/A"')
    twitter=$(echo "$data" | jq -r '.twitter // "N/A"')
    echo ""
    echo "🌐 Website: $url"
    echo "🐦 Twitter: ${twitter:+https://twitter.com/$twitter}"
    echo "📊 DefiLlama: https://defillama.com/protocol/${SLUG}"

  else
    echo "❌ Protocol '$SLUG' not found on DefiLlama"
    echo "   Try: curl -s https://api.llama.fi/protocols | jq '.[].slug' | grep -i '${INPUT}'"
    return 1
  fi
}

# ========================
# Fees & Revenue Data
# ========================
do_fees() {
  echo ""
  echo "💵 Fees & Revenue"
  echo "---"

  local fees_data
  fees_data=$(curl -s "${DL_BASE}/summary/fees/${SLUG}?dataType=dailyFees" 2>/dev/null)

  local has_data
  has_data=$(echo "$fees_data" | jq -e '.name' 2>/dev/null && echo "yes" || echo "no")

  if [[ "$has_data" == "yes" ]]; then
    local name
    name=$(echo "$fees_data" | jq -r '.name // "N/A"')
    echo "Protocol: $name"

    # Daily fees - get latest from totalDataChart
    local latest_fees
    latest_fees=$(echo "$fees_data" | jq -r '
      .totalDataChart // [] | last | .[1] // "N/A"
    ' 2>/dev/null)
    echo "Latest Daily Fees: $(fmt_usd "$latest_fees")"

    # Total 24h/48h from the summary
    local total24h total48h
    total24h=$(echo "$fees_data" | jq -r '.total24h // "N/A"')
    total48h=$(echo "$fees_data" | jq -r '.total48hto24h // "N/A"')
    echo "24h Fees: $(fmt_usd "$total24h")"

    if [[ "$total24h" != "N/A" && "$total48h" != "N/A" && "$total24h" != "null" && "$total48h" != "null" ]]; then
      local fee_change
      fee_change=$(echo "$total24h $total48h" | awk '{if($2!=0) printf "%.2f", ($1-$2)/$2*100; else print "N/A"}')
      echo "Fees Change (24h vs prior): ${fee_change}%"
    fi

    # Chain breakdown
    local chain_fees
    chain_fees=$(echo "$fees_data" | jq -r '
      .totalDataChartBreakdown // [] | last | .[1] // {} | to_entries
      | sort_by(-.value)[:5][]
      | "  \(.key): $\(.value / 1e3 | . * 100 | round / 100)K"
    ' 2>/dev/null)
    if [[ -n "$chain_fees" ]]; then
      echo ""
      echo "Fees by Chain (latest, top 5):"
      echo "$chain_fees"
    fi
  else
    echo "⚠️ No fees data available for '$SLUG' on DefiLlama"
  fi

  # Revenue
  echo ""
  local rev_data
  rev_data=$(curl -s "${DL_BASE}/summary/fees/${SLUG}?dataType=dailyRevenue" 2>/dev/null)

  local has_rev
  has_rev=$(echo "$rev_data" | jq -e '.total24h' 2>/dev/null && echo "yes" || echo "no")

  if [[ "$has_rev" == "yes" ]]; then
    local rev24h
    rev24h=$(echo "$rev_data" | jq -r '.total24h // "N/A"')
    echo "24h Revenue (protocol): $(fmt_usd "$rev24h")"

    # Revenue vs Fees ratio
    if [[ "$total24h" != "N/A" && "$rev24h" != "N/A" && "$total24h" != "null" && "$rev24h" != "null" ]]; then
      local rev_ratio
      rev_ratio=$(echo "$rev24h $total24h" | awk '{if($2!=0) printf "%.1f%%", $1/$2*100; else print "N/A"}')
      echo "Revenue/Fees Ratio: $rev_ratio (protocol take rate)"
    fi

    # Holders revenue
    local holders_data holders24h
    holders_data=$(curl -s "${DL_BASE}/summary/fees/${SLUG}?dataType=dailyHoldersRevenue" 2>/dev/null)
    holders24h=$(echo "$holders_data" | jq -r '.total24h // "N/A"' 2>/dev/null)
    if [[ "$holders24h" != "N/A" && "$holders24h" != "null" && "$holders24h" != "0" ]]; then
      echo "24h Token Holders Revenue: $(fmt_usd "$holders24h")"
    fi
  else
    echo "⚠️ No revenue data available for '$SLUG'"
  fi

  echo ""
  echo "📊 DefiLlama Fees: https://defillama.com/fees/${SLUG}"
}

# ========================
# DEX Volume (bonus)
# ========================
do_volume() {
  local vol_data
  vol_data=$(curl -s "${DL_BASE}/summary/dexs/${SLUG}" 2>/dev/null)

  local has_vol
  has_vol=$(echo "$vol_data" | jq -e '.total24h' 2>/dev/null && echo "yes" || echo "no")

  if [[ "$has_vol" == "yes" ]]; then
    echo ""
    echo "📈 DEX Volume"
    echo "---"
    local vol24h change_1d
    vol24h=$(echo "$vol_data" | jq -r '.total24h // "N/A"')
    change_1d=$(echo "$vol_data" | jq -r '.change_1d // "N/A"')
    echo "24h Volume: $(fmt_usd "$vol24h")"
    if [[ "$change_1d" != "N/A" && "$change_1d" != "null" ]]; then
      echo "Volume Change 24h: $(fmt_pct "$change_1d")"
    fi
  fi
}

# ========================
# Main
# ========================
case "$MODE" in
  tvl)
    do_tvl
    ;;
  fees|revenue)
    do_fees
    ;;
  full)
    do_tvl
    do_fees
    do_volume
    ;;
  *)
    echo "Unknown mode: $MODE"
    echo "Usage: $0 <protocol_slug> [full|tvl|fees|revenue]"
    exit 1
    ;;
esac

echo ""
echo "=========================================="
echo "✅ DefiLlama research complete."
echo "=========================================="
