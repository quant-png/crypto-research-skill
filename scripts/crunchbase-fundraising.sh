#!/bin/bash
# crunchbase-fundraising.sh — Crunchbase fundraising rounds tracker
# Covers ALL sectors: AI, biotech, fintech, SaaS, crypto, healthcare, etc.
# Usage: ./crunchbase-fundraising.sh [mode] [filter]
# Modes:
#   today     — funding rounds announced today (default)
#   week      — this week's rounds
#   recent    — last 7 days
#   search    — search company by name/keyword
#   org       — lookup specific org's funding history
#   category  — filter by category (AI, biotech, fintech, etc.)
#   top       — largest raises (last 30 days)
# Examples:
#   ./crunchbase-fundraising.sh today
#   ./crunchbase-fundraising.sh week
#   ./crunchbase-fundraising.sh search "OpenAI"
#   ./crunchbase-fundraising.sh org openai
#   ./crunchbase-fundraising.sh category "artificial-intelligence"
#   ./crunchbase-fundraising.sh top
#
# Data source priority:
#   1. CRUNCHBASE_API_KEY set → Crunchbase API (structured, best quality)
#   2. BRAVE_API_KEY set      → Brave Search (scrapes crunchbase.com snippets)
#   3. Neither                → exit with instructions
#
# API docs: https://data.crunchbase.com/docs/using-the-api

set -euo pipefail

MODE="${1:-today}"
FILTER="${2:-}"

CB_KEY="${CRUNCHBASE_API_KEY:-}"
CB_BASE="https://api.crunchbase.com/api/v4"

BRAVE_KEY="${BRAVE_API_KEY:-}"
BRAVE_BASE="https://api.search.brave.com/res/v1/web/search"

# Determine data source
DATA_SOURCE=""
if [[ -n "$CB_KEY" ]]; then
  DATA_SOURCE="crunchbase"
elif [[ -n "$BRAVE_KEY" ]]; then
  DATA_SOURCE="brave"
fi

# ========================
# Pre-flight
# ========================
if [[ -z "$DATA_SOURCE" ]]; then
  echo "=========================================="
  echo "❌ No API key available (CRUNCHBASE_API_KEY or BRAVE_API_KEY)"
  echo "=========================================="
  echo ""
  echo "Option 1 (best): Crunchbase API key"
  echo "  1. Sign up at https://www.crunchbase.com"
  echo "  2. Subscribe to a Pro, Business, or API plan"
  echo "  3. export CRUNCHBASE_API_KEY=\"your_key_here\""
  echo ""
  echo "Option 2 (fallback): Brave Search API key"
  echo "  1. Get free key at https://brave.com/search/api/ (2,000 queries/mo)"
  echo "  2. export BRAVE_API_KEY=\"your_key_here\""
  echo "  ⚠️ Returns search snippets, not structured data"
  echo ""
  echo "💡 Alternative: Use fundraising-daily.sh for crypto-specific"
  echo "   fundraising (RootData + DefiLlama, no key needed)"
  exit 1
fi

# ========================
# Helpers
# ========================
fmt_usd() {
  local val="$1"
  if [[ "$val" == "null" || -z "$val" || "$val" == "0" ]]; then echo "Undisclosed"; return; fi
  echo "$val" | awk '{
    v=$1;
    if(v<0) { neg="-"; v=-v } else neg="";
    if(v>=1e9) printf "%s$%.2fB\n", neg, v/1e9;
    else if(v>=1e6) printf "%s$%.2fM\n", neg, v/1e6;
    else if(v>=1e3) printf "%s$%.0fK\n", neg, v/1e3;
    else printf "%s$%.0f\n", neg, v;
  }'
}

today_date() { date -u +%Y-%m-%d; }
days_ago_date() { date -u -d "$1 days ago" +%Y-%m-%d 2>/dev/null || date -u -v-"$1"d +%Y-%m-%d 2>/dev/null || echo "$(date -u +%Y-%m-%d)"; }

cb_post() {
  local endpoint="$1"
  local body="$2"
  curl -s --max-time 30 -X POST \
    -H "X-cb-user-key: $CB_KEY" \
    -H "Content-Type: application/json" \
    -d "$body" \
    "${CB_BASE}/${endpoint}" 2>/dev/null
}

cb_get() {
  local endpoint="$1"
  curl -s --max-time 30 \
    -H "X-cb-user-key: $CB_KEY" \
    -H "Content-Type: application/json" \
    "${CB_BASE}/${endpoint}" 2>/dev/null
}

check_error() {
  local data="$1"
  local err
  err=$(echo "$data" | jq -r '.error // .message // empty' 2>/dev/null)
  if [[ -n "$err" ]]; then
    echo "❌ Crunchbase API error: $err"
    # Check for common issues
    if echo "$err" | grep -qi "unauthorized\|invalid.*key\|403\|401"; then
      echo "   Your API key may be invalid or expired."
      echo "   Check: Account → Integrations → API key"
    elif echo "$err" | grep -qi "rate\|limit\|429"; then
      echo "   Rate limited (200 calls/min). Wait and retry."
    elif echo "$err" | grep -qi "permission\|access\|package"; then
      echo "   This endpoint may require a higher API plan."
      echo "   Basic plan only supports org search + entity lookup."
      echo "   Full funding_rounds search requires Enterprise/API plan."
    fi
    return 1
  fi
  return 0
}

# ========================
# Brave Search helpers
# ========================
brave_search() {
  local query="$1"
  local count="${2:-10}"
  curl -s --max-time 20 \
    -H "Accept: application/json" \
    -H "Accept-Encoding: gzip" \
    -H "X-Subscription-Token: $BRAVE_KEY" \
    "${BRAVE_BASE}?q=$(echo "$query" | sed 's/ /%20/g')&count=${count}&text_decorations=false&search_lang=en" 2>/dev/null
}

brave_search_funding_rounds() {
  local keyword="$1"
  local timeframe="${2:-today}"

  local time_query=""
  case "$timeframe" in
    today)   time_query="$(date -u +%Y-%m-%d)" ;;
    week)    time_query="this week $(date -u +%Y)" ;;
    recent)  time_query="last 7 days $(date -u +%Y)" ;;
    month)   time_query="last 30 days $(date -u +%Y)" ;;
    *)       time_query="$timeframe" ;;
  esac

  local query="site:crunchbase.com/funding_round ${keyword} funding round ${time_query}"
  echo "🔍 Brave Search: $query"
  echo ""

  local data
  data=$(brave_search "$query" 20)

  local count
  count=$(echo "$data" | jq '.web.results // [] | length' 2>/dev/null || echo "0")

  if [[ "$count" -eq 0 ]]; then
    # Fallback: broader search without site filter
    query="${keyword} funding round raised ${time_query} crunchbase"
    echo "   (no direct results, trying broader search...)"
    echo "🔍 Brave Search: $query"
    echo ""
    data=$(brave_search "$query" 20)
    count=$(echo "$data" | jq '.web.results // [] | length' 2>/dev/null || echo "0")
  fi

  if [[ "$count" -eq 0 ]]; then
    echo "  No results found."
    return 0
  fi

  echo "📊 Found $count results"
  echo ""

  echo "$data" | jq -r '.web.results[]? |
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
    "🏷️ \(.title // "N/A")",
    "  \(.description // "No snippet" | .[0:200])",
    "  🔗 \(.url // "")",
    ""
  ' 2>/dev/null

  # Extract extra snippets if available
  local has_extras
  has_extras=$(echo "$data" | jq '[.web.results[]? | select(.extra_snippets != null)] | length' 2>/dev/null || echo "0")
  if [[ "$has_extras" -gt 0 ]]; then
    echo ""
    echo "📝 Additional details from snippets:"
    echo "$data" | jq -r '.web.results[]? | select(.extra_snippets != null) |
      "  [\(.title // "N/A" | .[0:60])]:",
      (.extra_snippets[]? | "    • \(.[0:200])")
    ' 2>/dev/null
  fi
}

brave_search_org() {
  local org_name="$1"

  echo "🔍 Searching Crunchbase via Brave for: $org_name"
  echo ""

  # Search 1: org page on crunchbase
  local query="site:crunchbase.com/organization/${org_name}"
  local data
  data=$(brave_search "$query" 5)

  local count
  count=$(echo "$data" | jq '.web.results // [] | length' 2>/dev/null || echo "0")

  if [[ "$count" -eq 0 ]]; then
    # Try with name
    query="site:crunchbase.com/organization \"${org_name}\" funding"
    data=$(brave_search "$query" 5)
    count=$(echo "$data" | jq '.web.results // [] | length' 2>/dev/null || echo "0")
  fi

  if [[ "$count" -gt 0 ]]; then
    echo "📋 Organization Page:"
    echo "$data" | jq -r '.web.results[0] |
      "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
      "🏢 \(.title // "N/A")",
      "  \(.description // "No description")",
      "  🔗 \(.url // "")"
    ' 2>/dev/null

    # Show extra snippets for funding detail
    echo "$data" | jq -r '.web.results[0] | select(.extra_snippets != null) |
      "",
      "📝 Details:",
      (.extra_snippets[]? | "  • \(.[0:250])")
    ' 2>/dev/null
    echo ""
  fi

  # Search 2: funding rounds for this org
  query="site:crunchbase.com \"${org_name}\" funding round raised"
  local data2
  data2=$(brave_search "$query" 10)

  local count2
  count2=$(echo "$data2" | jq '.web.results // [] | length' 2>/dev/null || echo "0")

  if [[ "$count2" -gt 0 ]]; then
    echo ""
    echo "💰 Funding-Related Results:"
    echo "$data2" | jq -r '.web.results[]? |
      "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
      "  \(.title // "N/A")",
      "  \(.description // "" | .[0:200])",
      "  🔗 \(.url // "")",
      ""
    ' 2>/dev/null
  fi

  # Search 3: recent news
  query="${org_name} funding raised series site:techcrunch.com OR site:crunchbase.com OR site:bloomberg.com"
  local data3
  data3=$(brave_search "$query" 5)

  local count3
  count3=$(echo "$data3" | jq '.web.results // [] | length' 2>/dev/null || echo "0")

  if [[ "$count3" -gt 0 ]]; then
    echo ""
    echo "📰 Recent News:"
    echo "$data3" | jq -r '.web.results[:5][]? |
      "  • \(.title // "N/A")",
      "    \(.description // "" | .[0:150])",
      "    🔗 \(.url // "")",
      ""
    ' 2>/dev/null
  fi

  if [[ "$count" -eq 0 && "$count2" -eq 0 && "$count3" -eq 0 ]]; then
    echo "  No results found for '$org_name'."
    echo "  Try different spelling or the company's full name."
  fi
}

brave_search_category() {
  local category="$1"
  local timeframe="${2:-week}"

  local time_query=""
  case "$timeframe" in
    today)   time_query="today $(date -u +%Y-%m-%d)" ;;
    week)    time_query="this week $(date -u +%B) $(date -u +%Y)" ;;
    month)   time_query="$(date -u +%B) $(date -u +%Y)" ;;
    *)       time_query="$timeframe" ;;
  esac

  echo "🏷️ Category: $category"
  echo ""

  # Search crunchbase for category funding
  local query="${category} startup funding round raised ${time_query} site:crunchbase.com OR site:techcrunch.com"
  echo "🔍 Brave Search: $query"
  echo ""

  local data
  data=$(brave_search "$query" 20)

  local count
  count=$(echo "$data" | jq '.web.results // [] | length' 2>/dev/null || echo "0")

  if [[ "$count" -eq 0 ]]; then
    echo "  No results found for '$category' funding."
    return 0
  fi

  echo "📊 Found $count results"
  echo ""

  echo "$data" | jq -r '.web.results[]? |
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
    "🏷️ \(.title // "N/A")",
    "  \(.description // "" | .[0:200])",
    "  🔗 \(.url // "")",
    ""
  ' 2>/dev/null
}

brave_search_top() {
  echo "🔍 Searching for largest recent raises..."
  echo ""

  local query="largest funding round raised 2025 2026 site:crunchbase.com OR site:techcrunch.com OR site:bloomberg.com"
  local data
  data=$(brave_search "$query" 20)

  local count
  count=$(echo "$data" | jq '.web.results // [] | length' 2>/dev/null || echo "0")

  if [[ "$count" -eq 0 ]]; then
    echo "  No results found."
    return 0
  fi

  echo "📊 Found $count results"
  echo ""

  echo "$data" | jq -r '.web.results[]? |
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
    "🏷️ \(.title // "N/A")",
    "  \(.description // "" | .[0:200])",
    "  🔗 \(.url // "")",
    ""
  ' 2>/dev/null
}

brave_autocomplete_search() {
  local query="$1"

  echo "🔍 Searching for: $query"
  echo ""

  local data
  data=$(brave_search "site:crunchbase.com/organization \"${query}\"" 10)

  local count
  count=$(echo "$data" | jq '.web.results // [] | length' 2>/dev/null || echo "0")

  if [[ "$count" -eq 0 ]]; then
    # Try broader search
    data=$(brave_search "crunchbase \"${query}\" company funding" 10)
    count=$(echo "$data" | jq '.web.results // [] | length' 2>/dev/null || echo "0")
  fi

  if [[ "$count" -eq 0 ]]; then
    echo "  No matching organizations found."
    return 0
  fi

  echo "📊 Found $count matches:"
  echo ""

  echo "$data" | jq -r '.web.results[]? |
    "  • \(.title // "N/A")",
    "    \(.description // "No description" | .[0:150])",
    "    🔗 \(.url // "")",
    ""
  ' 2>/dev/null

  # Suggest org lookup
  echo ""
  echo "💡 To see more detail for a specific org:"
  echo "   $0 org <name>"
}

echo "=========================================="
echo "🏢 Crunchbase Fundraising Tracker"
if [[ "$DATA_SOURCE" == "brave" ]]; then
  echo "   (via Brave Search — snippets only)"
fi
echo "=========================================="
echo "  Mode: $MODE"
echo "  Source: $DATA_SOURCE"
echo "  Date: $(date -u '+%Y-%m-%d %H:%M UTC')"
echo ""

# ========================
# Search Funding Rounds
# ========================
do_search_funding() {
  local date_from="$1"
  local date_to="${2:-$(today_date)}"
  local min_amount="${3:-0}"
  local limit="${4:-25}"
  local category_uuid="${5:-}"

  echo "📡 Searching Crunchbase funding rounds..."
  echo "   Period: $date_from → $date_to"
  if [[ "$min_amount" -gt 0 ]]; then
    echo "   Min amount: $(fmt_usd "$min_amount")"
  fi
  echo ""

  # Build query predicates
  local predicates=""
  predicates="
    {
      \"type\": \"predicate\",
      \"field_id\": \"announced_on\",
      \"operator_id\": \"gte\",
      \"values\": [\"$date_from\"]
    },
    {
      \"type\": \"predicate\",
      \"field_id\": \"announced_on\",
      \"operator_id\": \"lte\",
      \"values\": [\"$date_to\"]
    }"

  if [[ "$min_amount" -gt 0 ]]; then
    predicates="$predicates,
    {
      \"type\": \"predicate\",
      \"field_id\": \"money_raised\",
      \"operator_id\": \"gte\",
      \"values\": [{\"value\": $min_amount, \"currency\": \"usd\"}]
    }"
  fi

  if [[ -n "$category_uuid" ]]; then
    predicates="$predicates,
    {
      \"type\": \"predicate\",
      \"field_id\": \"funded_organization_categories\",
      \"operator_id\": \"includes\",
      \"values\": [\"$category_uuid\"]
    }"
  fi

  local body
  body=$(cat <<EOF
{
  "field_ids": [
    "identifier",
    "announced_on",
    "funded_organization_identifier",
    "funded_organization_description",
    "funded_organization_categories",
    "funded_organization_location",
    "money_raised",
    "investment_type",
    "num_investors",
    "lead_investor_identifiers",
    "investor_identifiers",
    "pre_money_valuation",
    "short_description"
  ],
  "order": [
    {
      "field_id": "announced_on",
      "sort": "desc"
    }
  ],
  "query": [
    $predicates
  ],
  "limit": $limit
}
EOF
  )

  local data
  data=$(cb_post "searches/funding_rounds" "$body")

  if ! check_error "$data"; then
    echo ""
    echo "💡 If you have a Basic plan, funding_rounds search may not be available."
    echo "   Try: $0 search <company_name>  (uses autocomplete + entity lookup instead)"
    return 1
  fi

  local total count
  total=$(echo "$data" | jq '.count // 0' 2>/dev/null)
  count=$(echo "$data" | jq '.entities // [] | length' 2>/dev/null)

  echo "📊 Found $total total rounds (showing $count)"
  echo ""

  if [[ "$count" -eq 0 ]]; then
    echo "  No funding rounds found for this period."
    return 0
  fi

  # Display each round
  echo "$data" | jq -r '.entities[]? | .properties as $p |
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
    "🏷️ \($p.funded_organization_identifier.value // "Unknown")",
    "  Round: \($p.investment_type // "N/A")",
    "  Amount: \(
      if $p.money_raised then
        "$" + (if $p.money_raised.value >= 1e9 then (($p.money_raised.value / 1e9 * 100 | round) / 100 | tostring) + "B"
        elif $p.money_raised.value >= 1e6 then (($p.money_raised.value / 1e6 * 100 | round) / 100 | tostring) + "M"
        elif $p.money_raised.value >= 1e3 then (($p.money_raised.value / 1e3 | round) | tostring) + "K"
        else ($p.money_raised.value | tostring) end) + " " + ($p.money_raised.currency // "USD")
      else "Undisclosed" end
    )",
    "  Valuation: \(
      if $p.pre_money_valuation then
        "$" + (if $p.pre_money_valuation.value >= 1e9 then (($p.pre_money_valuation.value / 1e9 * 100 | round) / 100 | tostring) + "B"
        elif $p.pre_money_valuation.value >= 1e6 then (($p.pre_money_valuation.value / 1e6 * 100 | round) / 100 | tostring) + "M"
        else ($p.pre_money_valuation.value | tostring) end)
      else "N/A" end
    )",
    "  Date: \($p.announced_on // "N/A")",
    "  Description: \(($p.funded_organization_description // $p.short_description // "N/A") | .[0:120])",
    "  Categories: \($p.funded_organization_categories // [] | map(.value) | join(", ") | if . == "" then "N/A" else .[0:80] end)",
    "  Location: \($p.funded_organization_location // [] | map(.value) | join(", ") | if . == "" then "N/A" else . end)",
    "  Lead: \($p.lead_investor_identifiers // [] | map(.value) | join(", ") | if . == "" then "N/A" else . end)",
    "  Investors (\($p.num_investors // 0)): \($p.investor_identifiers // [] | map(.value) | join(", ") | if . == "" then "N/A" else .[0:120] end)",
    "  🔗 https://www.crunchbase.com/funding_round/\($p.identifier.permalink // "")"
  ' 2>/dev/null

  # Summary
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "📈 Summary ($count of $total shown):"

  local total_amount
  total_amount=$(echo "$data" | jq '[.entities[]?.properties.money_raised.value // 0] | add // 0' 2>/dev/null)
  echo "  Total Disclosed: $(fmt_usd "$total_amount")"

  # By round type
  echo ""
  echo "  By Round Type:"
  echo "$data" | jq -r '
    [.entities[]?.properties | {type: (.investment_type // "Unknown"), amount: (.money_raised.value // 0)}]
    | group_by(.type) | map({type: .[0].type, count: length, total: (map(.amount) | add)})
    | sort_by(-.total)[] |
    "    \(.type): \(.count) rounds — $\(.total | if . >= 1e9 then (. / 1e9 * 100 | round / 100 | tostring) + "B" elif . >= 1e6 then (. / 1e6 * 100 | round / 100 | tostring) + "M" elif . >= 1e3 then (. / 1e3 | round | tostring) + "K" else "0" end)"
  ' 2>/dev/null || true

  # Largest raises
  echo ""
  echo "  🏆 Largest Raises:"
  echo "$data" | jq -r '
    [.entities[]?.properties | select(.money_raised.value > 0)]
    | sort_by(-.money_raised.value)[:5][] |
    "    \(.funded_organization_identifier.value // "Unknown") — $\(.money_raised.value | if . >= 1e9 then (. / 1e9 * 100 | round / 100 | tostring) + "B" elif . >= 1e6 then (. / 1e6 * 100 | round / 100 | tostring) + "M" elif . >= 1e3 then (. / 1e3 | round | tostring) + "K" else tostring end) (\(.investment_type // "N/A"))"
  ' 2>/dev/null || true
}

# ========================
# Autocomplete Search
# ========================
do_autocomplete() {
  local query="$1"

  echo "🔍 Searching Crunchbase for: $query"
  echo ""

  local data
  data=$(cb_get "autocompletes?query=$(echo "$query" | sed 's/ /%20/g')&collection_ids=organizations&limit=10")

  if ! check_error "$data"; then return 1; fi

  local count
  count=$(echo "$data" | jq '.entities // [] | length' 2>/dev/null)

  if [[ "$count" -eq 0 ]]; then
    echo "  No matching organizations found."
    return 0
  fi

  echo "📊 Found $count matches:"
  echo ""

  echo "$data" | jq -r '.entities[]? |
    "  • \(.identifier.value // "Unknown") [\(.identifier.permalink // "")]",
    "    \(.short_description // "No description")",
    "    🔗 https://www.crunchbase.com/organization/\(.identifier.permalink // "")",
    ""
  ' 2>/dev/null

  # Offer to lookup first result
  local first_permalink
  first_permalink=$(echo "$data" | jq -r '.entities[0].identifier.permalink // ""' 2>/dev/null)
  if [[ -n "$first_permalink" ]]; then
    echo ""
    echo "💡 To see funding history for the top result:"
    echo "   $0 org $first_permalink"
  fi
}

# ========================
# Organization Entity Lookup (with funding rounds)
# ========================
do_org_lookup() {
  local permalink="$1"

  echo "📡 Looking up organization: $permalink"
  echo ""

  local data
  data=$(cb_get "entities/organizations/${permalink}?card_ids=raised_funding_rounds,founders&field_ids=identifier,short_description,categories,location_identifiers,founded_on,website,linkedin,num_employees_enum,funding_total,last_funding_type,last_funding_at,num_funding_rounds,rank_org_company,revenue_range")

  if ! check_error "$data"; then return 1; fi

  # Properties
  local props
  props=$(echo "$data" | jq '.properties // {}' 2>/dev/null)

  local name desc founded website linkedin employees funding_total last_type last_date num_rounds rank
  name=$(echo "$props" | jq -r '.identifier.value // "Unknown"')
  desc=$(echo "$props" | jq -r '.short_description // "N/A"')
  founded=$(echo "$props" | jq -r '.founded_on // "N/A"')
  website=$(echo "$props" | jq -r '.website.value // "N/A"')
  linkedin=$(echo "$props" | jq -r '.linkedin.value // "N/A"')
  employees=$(echo "$props" | jq -r '.num_employees_enum // "N/A"')
  funding_total=$(echo "$props" | jq -r '.funding_total.value // 0')
  last_type=$(echo "$props" | jq -r '.last_funding_type // "N/A"')
  last_date=$(echo "$props" | jq -r '.last_funding_at // "N/A"')
  num_rounds=$(echo "$props" | jq -r '.num_funding_rounds // 0')
  rank=$(echo "$props" | jq -r '.rank_org_company // "N/A"')

  local categories
  categories=$(echo "$props" | jq -r '.categories // [] | map(.value) | join(", ")' 2>/dev/null)
  local location
  location=$(echo "$props" | jq -r '.location_identifiers // [] | map(.value) | join(", ")' 2>/dev/null)

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🏢 $name"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "📝 $desc"
  echo ""
  echo "📋 Company Info:"
  echo "  Founded: $founded"
  echo "  Categories: ${categories:-N/A}"
  echo "  Location: ${location:-N/A}"
  echo "  Employees: $employees"
  echo "  Crunchbase Rank: #$rank"
  echo "  Website: $website"
  echo "  LinkedIn: $linkedin"
  echo ""
  echo "💰 Funding Overview:"
  echo "  Total Raised: $(fmt_usd "$funding_total")"
  echo "  Funding Rounds: $num_rounds"
  echo "  Last Round: $last_type ($last_date)"
  echo ""

  # Founders
  local founders_count
  founders_count=$(echo "$data" | jq '.cards.founders // [] | length' 2>/dev/null)
  if [[ "$founders_count" -gt 0 ]]; then
    echo "👥 Founders:"
    echo "$data" | jq -r '.cards.founders[]? |
      "  • \(.identifier.value // "Unknown") — \(.short_description // "")"
    ' 2>/dev/null
    echo ""
  fi

  # Funding rounds detail
  local rounds_count
  rounds_count=$(echo "$data" | jq '.cards.raised_funding_rounds // [] | length' 2>/dev/null)
  if [[ "$rounds_count" -gt 0 ]]; then
    echo "📊 Funding Rounds ($rounds_count):"
    echo "---"
    echo "$data" | jq -r '.cards.raised_funding_rounds[]? | .properties // . |
      "  \(.announced_on // "N/A") | \(.investment_type // "N/A") | \(
        if .money_raised then
          "$" + (if .money_raised.value >= 1e9 then ((.money_raised.value / 1e9 * 100 | round) / 100 | tostring) + "B"
          elif .money_raised.value >= 1e6 then ((.money_raised.value / 1e6 * 100 | round) / 100 | tostring) + "M"
          elif .money_raised.value >= 1e3 then ((.money_raised.value / 1e3 | round) | tostring) + "K"
          else (.money_raised.value | tostring) end)
        else "Undisclosed" end
      ) | investors: \(.num_investors // 0)"
    ' 2>/dev/null
  else
    echo "  No funding round details available."
    echo "  (May require Full API plan for detailed round data)"
  fi

  echo ""
  echo "🔗 https://www.crunchbase.com/organization/$permalink"
}

# ========================
# Category-filtered search
# ========================
do_category_search() {
  local category="$1"
  local days="${2:-7}"

  # Common category UUIDs (Crunchbase uses UUIDs for categories)
  # These are well-known IDs that rarely change
  declare -A CATEGORY_MAP=(
    ["artificial-intelligence"]="c4d8caf3-5fe7-359b-1638-55db9c8c0612"
    ["ai"]="c4d8caf3-5fe7-359b-1638-55db9c8c0612"
    ["machine-learning"]="5ea0cdb7-d7df-0e74-34a5-5e8e1363884b"
    ["ml"]="5ea0cdb7-d7df-0e74-34a5-5e8e1363884b"
    ["biotechnology"]="58842728-36d6-a921-4e61-a5e0f56cfe46"
    ["biotech"]="58842728-36d6-a921-4e61-a5e0f56cfe46"
    ["fintech"]="267e4616-e1cb-3ad1-cbb4-2e813d88df41"
    ["financial-services"]="267e4616-e1cb-3ad1-cbb4-2e813d88df41"
    ["health-care"]="80f3b2f8-74ff-7eb7-5e01-b0ad9abc7003"
    ["healthcare"]="80f3b2f8-74ff-7eb7-5e01-b0ad9abc7003"
    ["saas"]="5c4e69df-b90d-2e0e-b4d3-90c6448dcb47"
    ["blockchain"]="42de2a85-cc37-4fb6-9e97-d3a8fd1ed0e4"
    ["crypto"]="42de2a85-cc37-4fb6-9e97-d3a8fd1ed0e4"
    ["cryptocurrency"]="42de2a85-cc37-4fb6-9e97-d3a8fd1ed0e4"
    ["e-commerce"]="275ddcbc-27de-ff4f-4e50-6dc26ebf9570"
    ["ecommerce"]="275ddcbc-27de-ff4f-4e50-6dc26ebf9570"
    ["robotics"]="27de8b02-fbaa-ec3d-a034-5e6e63258990"
    ["cybersecurity"]="6cb685e1-7930-d4e7-207d-2d0edb924ac6"
    ["security"]="6cb685e1-7930-d4e7-207d-2d0edb924ac6"
    ["clean-technology"]="06ef7097-116e-7084-da58-98e734e3c4ee"
    ["cleantech"]="06ef7097-116e-7084-da58-98e734e3c4ee"
    ["climate"]="06ef7097-116e-7084-da58-98e734e3c4ee"
    ["edtech"]="1e5a0caa-75cf-b82c-08c5-66293a0bf677"
    ["education"]="1e5a0caa-75cf-b82c-08c5-66293a0bf677"
    ["gaming"]="d042e4a5-ed6f-82f6-e7a5-7ef8d083e4b3"
    ["real-estate"]="1de64aed-f4e1-8c30-cbc5-c9da2ac11e7c"
    ["food"]="da3cec06-b8ba-c1f1-4e79-b5fdcf2a6856"
    ["aerospace"]="c45085b5-10f7-e1c5-1aab-12ede21f99bc"
    ["space"]="c45085b5-10f7-e1c5-1aab-12ede21f99bc"
    ["semiconductor"]="7ed4a37c-10fc-f22d-fe56-7f1dd0c0deb0"
    ["chip"]="7ed4a37c-10fc-f22d-fe56-7f1dd0c0deb0"
    ["quantum"]="b49f1d96-81de-0e7e-5ec5-bd65ec6b15c2"
    ["defi"]="b6612eb5-2e16-de8c-7a52-ce57e2e2b11e"
    ["web3"]="93b7e547-3a33-8c31-1476-a2ea0260b3f5"
    ["autonomous-vehicles"]="f0e2fd32-f9ea-f3c7-f45a-b6e6f744fa86"
    ["self-driving"]="f0e2fd32-f9ea-f3c7-f45a-b6e6f744fa86"
    ["drug-discovery"]="e7eddc0e-7e9a-3ac5-fbf1-d5a7a1249fb4"
    ["energy"]="c3bdca80-a455-2b34-f74d-5a0e79c04aec"
  )

  local cat_lower
  cat_lower=$(echo "$category" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

  local cat_uuid="${CATEGORY_MAP[$cat_lower]:-}"

  echo "🏷️ Category: $category"

  if [[ -z "$cat_uuid" ]]; then
    echo "⚠️ Category UUID not in local map for '$category'"
    echo "   Trying search without category filter..."
    echo ""
    echo "   Available categories:"
    echo "   AI/ML, Biotech, Fintech, Healthcare, SaaS, Blockchain/Crypto,"
    echo "   E-commerce, Robotics, Cybersecurity, CleanTech, EdTech,"
    echo "   Gaming, Aerospace/Space, Semiconductor, Quantum, DeFi, Web3,"
    echo "   Drug Discovery, Energy, Autonomous Vehicles"
    echo ""
    # Fall back to text-based approach
    do_search_funding "$(days_ago_date "$days")" "$(today_date)" 0 25
    return
  fi

  echo "   UUID: $cat_uuid"
  echo ""

  do_search_funding "$(days_ago_date "$days")" "$(today_date)" 0 25 "$cat_uuid"
}

# ========================
# Main
# ========================

# Brave Search fallback dispatcher
if [[ "$DATA_SOURCE" == "brave" ]]; then
  echo "⚠️ Using Brave Search fallback (no CRUNCHBASE_API_KEY)"
  echo "   Results are search snippets, not structured API data."
  echo ""

  case "$MODE" in
    today)
      echo "📅 Today's Fundraising Rounds (via Brave Search)"
      echo "---"
      brave_search_funding_rounds "" "today"
      ;;
    week)
      echo "📅 This Week's Fundraising Rounds (via Brave Search)"
      echo "---"
      brave_search_funding_rounds "" "week"
      ;;
    recent)
      echo "📅 Recent Fundraising (via Brave Search)"
      echo "---"
      brave_search_funding_rounds "" "recent"
      ;;
    search)
      if [[ -z "$FILTER" ]]; then
        echo "❌ Usage: $0 search <company_name>"
        exit 1
      fi
      brave_autocomplete_search "$FILTER"
      ;;
    org)
      if [[ -z "$FILTER" ]]; then
        echo "❌ Usage: $0 org <company_name>"
        exit 1
      fi
      brave_search_org "$FILTER"
      ;;
    category|cat)
      if [[ -z "$FILTER" ]]; then
        echo "❌ Usage: $0 category <category>"
        echo "   Example: $0 category AI"
        echo "   Example: $0 category biotech"
        exit 1
      fi
      brave_search_category "$FILTER" "${3:-week}"
      ;;
    top)
      echo "🏆 Top Recent Fundraising Rounds (via Brave Search)"
      echo "---"
      brave_search_top
      ;;
    *)
      echo "Unknown mode: $MODE"
      echo "Usage: $0 [mode] [filter]"
      exit 1
      ;;
  esac

  echo ""
  echo "=========================================="
  echo "✅ Brave Search scan complete."
  echo "=========================================="
  echo ""
  echo "⚠️ Brave Search returns snippets, not structured data."
  echo "   For full structured results, set CRUNCHBASE_API_KEY."
  echo ""
  echo "📌 Browse directly:"
  echo "  Crunchbase: https://www.crunchbase.com/discover/funding_rounds"
  echo "  Recent:     https://www.crunchbase.com/discover/funding_rounds/recent"
  exit 0
fi

# ========================
# Crunchbase API path (existing behavior)
# ========================
case "$MODE" in
  today)
    echo "📅 Today's Fundraising Rounds (All Sectors)"
    echo "---"
    do_search_funding "$(today_date)" "$(today_date)" 0 25
    ;;

  week)
    echo "📅 This Week's Fundraising Rounds (All Sectors)"
    echo "---"
    do_search_funding "$(days_ago_date 7)" "$(today_date)" 0 25
    ;;

  recent)
    echo "📅 Recent Fundraising (last 7 days, All Sectors)"
    echo "---"
    do_search_funding "$(days_ago_date 7)" "$(today_date)" 0 25
    ;;

  search)
    if [[ -z "$FILTER" ]]; then
      echo "❌ Usage: $0 search <company_name>"
      echo "   Example: $0 search \"OpenAI\""
      echo "   Example: $0 search \"Anthropic\""
      exit 1
    fi
    do_autocomplete "$FILTER"
    ;;

  org)
    if [[ -z "$FILTER" ]]; then
      echo "❌ Usage: $0 org <permalink>"
      echo "   Example: $0 org openai"
      echo "   Example: $0 org anthropic"
      echo ""
      echo "   Find permalink: $0 search <name>"
      exit 1
    fi
    do_org_lookup "$FILTER"
    ;;

  category|cat)
    if [[ -z "$FILTER" ]]; then
      echo "❌ Usage: $0 category <category_name> [days]"
      echo ""
      echo "   Popular categories:"
      echo "     AI / ML           — artificial-intelligence, machine-learning"
      echo "     Biotech           — biotechnology, drug-discovery"
      echo "     Fintech           — fintech, financial-services"
      echo "     Healthcare        — healthcare"
      echo "     SaaS              — saas"
      echo "     Crypto/Web3       — blockchain, crypto, defi, web3"
      echo "     Cybersecurity     — cybersecurity"
      echo "     CleanTech/Energy  — cleantech, climate, energy"
      echo "     Robotics          — robotics"
      echo "     Aerospace/Space   — aerospace, space"
      echo "     Semiconductor     — semiconductor, chip"
      echo "     Quantum           — quantum"
      echo "     EdTech            — edtech, education"
      echo "     Gaming            — gaming"
      echo "     E-commerce        — ecommerce"
      echo ""
      echo "   Example: $0 category AI"
      echo "   Example: $0 category biotech 30"
      exit 1
    fi
    local_days="${3:-7}"
    do_category_search "$FILTER" "$local_days"
    ;;

  top)
    echo "🏆 Top Fundraising Rounds (last 30 days, $10M+ only)"
    echo "---"
    do_search_funding "$(days_ago_date 30)" "$(today_date)" 10000000 25
    ;;

  *)
    echo "Unknown mode: $MODE"
    echo ""
    echo "Usage: $0 [mode] [filter]"
    echo ""
    echo "Modes:"
    echo "  today              — today's funding rounds (default)"
    echo "  week               — this week's rounds"
    echo "  recent             — last 7 days"
    echo "  search <name>      — search company by name"
    echo "  org <permalink>    — lookup org's funding history"
    echo "  category <cat>     — filter by sector (AI, biotech, fintech...)"
    echo "  top                — largest raises (last 30 days, \$10M+)"
    echo ""
    echo "Examples:"
    echo "  $0 today"
    echo "  $0 search \"OpenAI\""
    echo "  $0 org anthropic"
    echo "  $0 category AI"
    echo "  $0 category biotech 30"
    echo "  $0 top"
    exit 1
    ;;
esac

echo ""
echo "=========================================="
echo "✅ Crunchbase fundraising scan complete."
echo "=========================================="
echo ""
echo "📌 Browse more:"
echo "  Crunchbase: https://www.crunchbase.com/discover/funding_rounds"
echo "  Recent:     https://www.crunchbase.com/discover/funding_rounds/recent"
echo "  By sector:  https://www.crunchbase.com/discover/organization.companies"
echo ""
echo "📌 Crypto-specific (RootData + DefiLlama):"
echo "  Use: fundraising-daily.sh today"
