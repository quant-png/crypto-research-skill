#!/bin/bash
# rootdata-research.sh — Project research via RootData API (team, investors, funding)
# Usage: ./rootdata-research.sh <project_name_or_id> [mode]
# Modes: full (default), team, funding, vc <org_id>
# Example: ./rootdata-research.sh Ethereum
# Example: ./rootdata-research.sh 12 team
# Example: ./rootdata-research.sh "" vc 219

set -euo pipefail

INPUT="${1:?Usage: $0 <project_name_or_id> [mode: full|team|funding|vc]}"
MODE="${2:-full}"
VC_ID="${3:-}"

RD_KEY="${ROOTDATA_API_KEY:-}"
RD_BASE="https://api.rootdata.com/open"

if [[ -z "$RD_KEY" ]]; then
  echo "❌ ROOTDATA_API_KEY is not set."
  echo "Apply for a key at: https://www.rootdata.com/Api"
  exit 1
fi

rd_post() {
  local endpoint="$1"
  local body="$2"
  curl -s -X POST \
    -H "apikey: $RD_KEY" \
    -H "language: en" \
    -H "Content-Type: application/json" \
    -d "$body" \
    "${RD_BASE}/${endpoint}" 2>/dev/null
}

check_result() {
  local data="$1"
  local code
  code=$(echo "$data" | jq -r '.result // 0')
  if [[ "$code" != "200" ]]; then
    local msg
    msg=$(echo "$data" | jq -r '.message // "Unknown error"')
    echo "❌ RootData API Error ($code): $msg"
    return 1
  fi
  return 0
}

# ========================
# VC Detail Mode
# ========================
do_vc() {
  local org_id="$1"
  echo ""
  echo "🏦 VC / Investor Detail (RootData)"
  echo "=========================================="

  local data
  data=$(rd_post "get_org" "{\"org_id\": $org_id, \"include_team\": true, \"include_investments\": true}")
  check_result "$data" || return

  # Basic info
  echo "$data" | jq -r '.data |
    "Name: \(.org_name // "N/A")",
    "Established: \(.establishment_date // "N/A")",
    "Category: \(.category // [] | join(", "))",
    "Active: \(.active // "N/A")",
    "",
    "📝 Description:",
    (.description // "N/A"),
    "",
    "🌐 Links:",
    "  Website: \(.social_media.website // "N/A")",
    "  Twitter: \(.social_media.twitter // "N/A")",
    "  LinkedIn: \(.social_media.linkedin // "N/A")",
    "",
    "🔗 RootData: \(.rootdataurl // "N/A")"
  ' 2>/dev/null

  # Team
  local team_count
  team_count=$(echo "$data" | jq '.data.team_members // [] | length')
  if [[ "$team_count" -gt 0 ]]; then
    echo ""
    echo "👥 Team Members ($team_count):"
    echo "$data" | jq -r '.data.team_members[] |
      "  • \(.name // "N/A") — \(.position // "N/A")"
    ' 2>/dev/null
  fi

  # Portfolio
  local inv_count
  inv_count=$(echo "$data" | jq '.data.investments // [] | length')
  if [[ "$inv_count" -gt 0 ]]; then
    echo ""
    echo "📁 Portfolio ($inv_count investments, showing top 20):"
    echo "$data" | jq -r '.data.investments[:20][] |
      "  • \(.name // "N/A")"
    ' 2>/dev/null
  fi
}

# ========================
# Resolve Project ID
# ========================
resolve_project() {
  local input="$1"

  # If input is numeric, use as project_id directly
  if [[ "$input" =~ ^[0-9]+$ ]]; then
    PROJECT_ID="$input"
    return 0
  fi

  echo "🔍 Searching RootData for: $input"
  local search_data
  search_data=$(rd_post "ser_inv" "{\"query\": \"$input\"}")
  check_result "$search_data" || return 1

  local count
  count=$(echo "$search_data" | jq '.data | length // 0')
  if [[ "$count" -eq 0 ]]; then
    echo "❌ No results found for: $input"
    return 1
  fi

  # Find first project (type=1)
  PROJECT_ID=$(echo "$search_data" | jq -r '[.data[] | select(.type == 1)][0].id // empty')
  if [[ -z "$PROJECT_ID" ]]; then
    # No project found, show all results
    echo "⚠️ No project type found. Results:"
    echo "$search_data" | jq -r '.data[:5][] |
      "  [\(if .type == 1 then "Project" elif .type == 2 then "VC" else "People" end)] \(.name) (ID: \(.id))"
    ' 2>/dev/null
    return 1
  fi

  local pname
  pname=$(echo "$search_data" | jq -r '[.data[] | select(.type == 1)][0].name // "Unknown"')
  echo "Found: $pname (ID: $PROJECT_ID)"

  # Show other matches if any
  local other_projects
  other_projects=$(echo "$search_data" | jq '[.data[] | select(.type == 1)] | length')
  if [[ "$other_projects" -gt 1 ]]; then
    echo ""
    echo "ℹ️ Other project matches:"
    echo "$search_data" | jq -r '[.data[] | select(.type == 1)][1:5][] |
      "  • \(.name) (ID: \(.id)) — \(.introduce[:60] // "")..."
    ' 2>/dev/null
  fi
}

# ========================
# Project Detail
# ========================
do_project() {
  local show_team="${1:-true}"
  local show_investors="${2:-true}"

  echo ""
  echo "📋 Project Detail (RootData)"
  echo "=========================================="

  local data
  data=$(rd_post "get_item" "{\"project_id\": $PROJECT_ID, \"include_team\": $show_team, \"include_investors\": $show_investors}")
  check_result "$data" || return

  # --- Basic Info ---
  echo "$data" | jq -r '.data |
    "Project: \(.project_name // "N/A")",
    "Token: \(.token_symbol // "N/A")",
    "One-liner: \(.one_liner // "N/A")",
    "Established: \(.establishment_date // "N/A")",
    "Active: \(.active // "N/A")",
    "Tags: \(.tags // [] | join(", "))",
    "Ecosystem: \(.ecosystem // [] | join(", "))",
    "",
    "Total Funding: $\((.total_funding // 0) | if . > 1e9 then (. / 1e9 | . * 100 | round / 100 | tostring) + "B" elif . > 1e6 then (. / 1e6 | . * 100 | round / 100 | tostring) + "M" elif . > 1e3 then (. / 1e3 | . * 100 | round / 100 | tostring) + "K" else tostring end)"
  ' 2>/dev/null

  # --- Description ---
  echo ""
  echo "📝 Description:"
  echo "---"
  echo "$data" | jq -r '.data.description // "No description available"' 2>/dev/null | head -30
  echo ""

  # --- Social Media ---
  echo "🌐 Links:"
  echo "$data" | jq -r '.data.social_media //  {} |
    "  Website: \(.website // "N/A")",
    "  Twitter: \(.twitter // "N/A")",
    "  Discord: \(.discord // "N/A")",
    "  Medium: \(.medium // "N/A")",
    "  LinkedIn: \(.linkedin // "N/A")",
    "  Telegram: \(.telegram // "N/A")"
  ' 2>/dev/null

  echo "$data" | jq -r '.data | "  RootData: \(.rootdataurl // "N/A")"' 2>/dev/null

  # --- Contract ---
  local contract
  contract=$(echo "$data" | jq -r '.data.contract_address // "N/A"' 2>/dev/null)
  if [[ "$contract" != "N/A" && "$contract" != "null" && -n "$contract" ]]; then
    echo ""
    echo "📜 Contract: $contract"
  fi

  # --- Market Data (PRO fields, may be empty on Basic) ---
  local price
  price=$(echo "$data" | jq -r '.data.price // "N/A"' 2>/dev/null)
  if [[ "$price" != "N/A" && "$price" != "null" && -n "$price" ]]; then
    echo ""
    echo "📊 Market (from RootData):"
    echo "$data" | jq -r '.data |
      "  Price: $\(.price // "N/A")",
      "  Market Cap: $\(.market_cap // "N/A")",
      "  FDV: $\(.fully_diluted_market_cap // "N/A")"
    ' 2>/dev/null
  fi

  # --- Team Members ---
  if [[ "$show_team" == "true" ]]; then
    local team_count
    team_count=$(echo "$data" | jq '.data.team_members // [] | length')
    echo ""
    echo "👥 Team Members ($team_count)"
    echo "---"

    if [[ "$team_count" -gt 0 ]]; then
      echo "$data" | jq -r '.data.team_members[] |
        "• \(.name // "Unknown") — \(.position // "N/A")" +
        (if (.linkedin // "") != "" then "\n    LinkedIn: \(.linkedin)" else "" end) +
        (if (.twitter // "") != "" then "\n    Twitter: \(.twitter)" else "" end)
      ' 2>/dev/null

      # Team assessment
      echo ""
      local has_linkedin
      has_linkedin=$(echo "$data" | jq '[.data.team_members[] | select((.linkedin // "") != "")] | length')
      local has_twitter
      has_twitter=$(echo "$data" | jq '[.data.team_members[] | select((.twitter // "") != "")] | length')

      if [[ "$team_count" -eq 0 ]]; then
        echo "🚩 No team information available — anonymous team"
      elif [[ "$has_linkedin" -gt 0 ]]; then
        echo "✅ Team has LinkedIn profiles ($has_linkedin/$team_count members)"
      else
        echo "🟡 Team listed but no LinkedIn profiles found"
      fi

      if [[ "$has_twitter" -gt 0 ]]; then
        echo "✅ Team has Twitter presence ($has_twitter/$team_count members)"
      fi
    else
      echo "⚠️ No team member data available on RootData"
    fi
  fi

  # --- Investors ---
  if [[ "$show_investors" == "true" ]]; then
    local inv_count
    inv_count=$(echo "$data" | jq '.data.investors // [] | length')
    echo ""
    echo "💰 Investors ($inv_count)"
    echo "---"

    if [[ "$inv_count" -gt 0 ]]; then
      echo "$data" | jq -r '.data.investors[] |
        "• \(.name // "Unknown")"
      ' 2>/dev/null

      # Check for tier-1 VCs
      echo ""
      local tier1_vcs="a16z|Andreessen|Paradigm|Sequoia|Coinbase Ventures|Binance Labs|Polychain|Pantera|Multicoin|Framework|Dragonfly|Electric Capital|Lightspeed|Galaxy Digital|HashKey|Animoca|Jump Crypto"
      local tier1_found
      tier1_found=$(echo "$data" | jq -r '.data.investors[].name' 2>/dev/null | grep -iE "$tier1_vcs" || true)

      if [[ -n "$tier1_found" ]]; then
        echo "✅ Tier-1 VCs detected:"
        echo "$tier1_found" | while read -r vc; do
          echo "  ⭐ $vc"
        done
      else
        echo "ℹ️ No well-known tier-1 VCs detected (this is not necessarily negative)"
      fi
    else
      echo "⚠️ No investor data available on RootData"
    fi
  fi

  # --- Similar Projects ---
  local similar_count
  similar_count=$(echo "$data" | jq '.data.similar_project // [] | length')
  if [[ "$similar_count" -gt 0 ]]; then
    echo ""
    echo "🔄 Similar Projects:"
    echo "$data" | jq -r '.data.similar_project[:5][] |
      "  • \(.name // "Unknown")"
    ' 2>/dev/null
  fi

  # --- Supported Exchanges (PRO) ---
  local exchange_count
  exchange_count=$(echo "$data" | jq '.data.support_exchanges // [] | length' 2>/dev/null || echo "0")
  if [[ "$exchange_count" -gt 0 ]]; then
    echo ""
    echo "🏪 Listed Exchanges ($exchange_count):"
    echo "$data" | jq -r '.data.support_exchanges[:10][] |
      "  • \(.name // "Unknown")"
    ' 2>/dev/null
  fi
}

# ========================
# Main
# ========================

echo "=========================================="
echo "🔍 RootData Research"
echo "=========================================="

case "$MODE" in
  vc)
    if [[ -z "$VC_ID" ]]; then
      # If INPUT is a number, use it as vc id
      if [[ "$INPUT" =~ ^[0-9]+$ ]]; then
        do_vc "$INPUT"
      else
        echo "Usage for VC mode: $0 <vc_org_id> vc"
        echo "Or: $0 \"\" vc <org_id>"
        exit 1
      fi
    else
      do_vc "$VC_ID"
    fi
    ;;
  *)
    resolve_project "$INPUT" || exit 1
    case "$MODE" in
      team)
        do_project "true" "false"
        ;;
      funding)
        do_project "false" "true"
        ;;
      full)
        do_project "true" "true"
        ;;
      *)
        echo "Unknown mode: $MODE"
        echo "Usage: $0 <name_or_id> [full|team|funding|vc]"
        exit 1
        ;;
    esac
    ;;
esac

echo ""
echo "=========================================="
echo "✅ RootData research complete."
echo "=========================================="
