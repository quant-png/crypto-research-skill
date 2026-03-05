#!/bin/bash
# coingecko-community.sh — Fetch community + developer data from CoinGecko
# Usage: ./coingecko-community.sh <coin_id_or_symbol>
# Examples:
#   ./coingecko-community.sh bitcoin
#   ./coingecko-community.sh ethereum
#   ./coingecko-community.sh uniswap
#
# CoinGecko free Demo plan: 30 calls/min, no key needed (or set COINGECKO_API_KEY for Pro).
# Returns: telegram members, reddit subscribers/activity, GitHub dev stats.
# Note: twitter_followers removed by CoinGecko since May 2025 (X API restrictions).

set -euo pipefail

INPUT="${1:?Usage: $0 <coin_id_or_symbol>}"

CG_KEY="${COINGECKO_API_KEY:-}"
CG_BASE="https://api.coingecko.com/api/v3"

# Use Pro base URL if key is set
if [[ -n "$CG_KEY" ]]; then
  CG_BASE="https://pro-api.coingecko.com/api/v3"
fi

echo "=========================================="
echo "📊 CoinGecko Community Data: $INPUT"
echo "=========================================="

# ========================
# Helper: CoinGecko GET
# ========================
cg_get() {
  local endpoint="$1"
  local url="${CG_BASE}${endpoint}"
  if [[ -n "$CG_KEY" ]]; then
    curl -s -L --max-time 15 "$url" \
      -H "x-cg-pro-api-key: $CG_KEY" \
      -H "Accept: application/json" 2>/dev/null || true
  else
    curl -s -L --max-time 15 "$url" \
      -H "Accept: application/json" 2>/dev/null || true
  fi
}

# ========================
# Step 1: Resolve coin ID
# ========================
COIN_ID="$INPUT"

# If input doesn't look like a standard coin ID, try to search
resolve_id() {
  local search_data
  search_data=$(cg_get "/search?query=${INPUT}")
  if [[ -n "$search_data" ]]; then
    local found_id
    found_id=$(echo "$search_data" | jq -r '.coins[0].id // empty' 2>/dev/null)
    if [[ -n "$found_id" ]]; then
      COIN_ID="$found_id"
      local found_name
      found_name=$(echo "$search_data" | jq -r '.coins[0].name // "Unknown"' 2>/dev/null)
      echo "Resolved: $found_name → $COIN_ID"
    fi
  fi
}

# Try direct fetch first; if it fails, resolve via search
DATA=$(cg_get "/coins/${COIN_ID}?localization=false&tickers=false&market_data=false&community_data=true&developer_data=true&sparkline=false")

if [[ -z "$DATA" ]] || echo "$DATA" | jq -e '.error' &>/dev/null 2>&1; then
  resolve_id
  DATA=$(cg_get "/coins/${COIN_ID}?localization=false&tickers=false&market_data=false&community_data=true&developer_data=true&sparkline=false")
fi

if [[ -z "$DATA" ]] || echo "$DATA" | jq -e '.error' &>/dev/null 2>&1; then
  echo "⚠️ Could not fetch CoinGecko data for: $INPUT"
  echo "Check coin ID at: https://www.coingecko.com/en/coins/${INPUT}"
  exit 1
fi

# ========================
# Step 2: Parse community_data
# ========================
echo ""
echo "👥 Community Data"
echo "---"

# Telegram
TG_MEMBERS=$(echo "$DATA" | jq -r '.community_data.telegram_channel_user_count // empty' 2>/dev/null)
if [[ -n "$TG_MEMBERS" && "$TG_MEMBERS" != "null" ]]; then
  echo "  Telegram: $TG_MEMBERS members"
fi

# Reddit
REDDIT_SUBS=$(echo "$DATA" | jq -r '.community_data.reddit_subscribers // empty' 2>/dev/null)
REDDIT_POSTS=$(echo "$DATA" | jq -r '.community_data.reddit_average_posts_48h // empty' 2>/dev/null)
REDDIT_COMMENTS=$(echo "$DATA" | jq -r '.community_data.reddit_average_comments_48h // empty' 2>/dev/null)
REDDIT_ACTIVE=$(echo "$DATA" | jq -r '.community_data.reddit_accounts_active_48h // empty' 2>/dev/null)

if [[ -n "$REDDIT_SUBS" && "$REDDIT_SUBS" != "null" ]]; then
  echo "  Reddit Subscribers: $REDDIT_SUBS"
fi
if [[ -n "$REDDIT_ACTIVE" && "$REDDIT_ACTIVE" != "null" && "$REDDIT_ACTIVE" != "0" ]]; then
  echo "  Reddit Active (48h): $REDDIT_ACTIVE accounts"
fi
if [[ -n "$REDDIT_POSTS" && "$REDDIT_POSTS" != "null" ]]; then
  echo "  Reddit Posts (avg 48h): $REDDIT_POSTS"
fi
if [[ -n "$REDDIT_COMMENTS" && "$REDDIT_COMMENTS" != "null" ]]; then
  echo "  Reddit Comments (avg 48h): $REDDIT_COMMENTS"
fi

# ========================
# Step 3: Parse developer_data
# ========================
echo ""
echo "💻 Developer Data (GitHub)"
echo "---"

FORKS=$(echo "$DATA" | jq -r '.developer_data.forks // empty' 2>/dev/null)
STARS=$(echo "$DATA" | jq -r '.developer_data.stars // empty' 2>/dev/null)
SUBSCRIBERS=$(echo "$DATA" | jq -r '.developer_data.subscribers // empty' 2>/dev/null)
TOTAL_ISSUES=$(echo "$DATA" | jq -r '.developer_data.total_issues // empty' 2>/dev/null)
CLOSED_ISSUES=$(echo "$DATA" | jq -r '.developer_data.closed_issues // empty' 2>/dev/null)
PR_MERGED=$(echo "$DATA" | jq -r '.developer_data.pull_requests_merged // empty' 2>/dev/null)
PR_CONTRIBUTORS=$(echo "$DATA" | jq -r '.developer_data.pull_request_contributors // empty' 2>/dev/null)
ADDITIONS=$(echo "$DATA" | jq -r '.developer_data.code_additions_deletions_4_weeks.additions // empty' 2>/dev/null)
DELETIONS=$(echo "$DATA" | jq -r '.developer_data.code_additions_deletions_4_weeks.deletions // empty' 2>/dev/null)
COMMIT_4W=$(echo "$DATA" | jq -r '.developer_data.commit_count_4_weeks // empty' 2>/dev/null)

if [[ -n "$STARS" && "$STARS" != "null" ]]; then
  echo "  Stars: $STARS | Forks: ${FORKS:-N/A} | Watchers: ${SUBSCRIBERS:-N/A}"
fi
if [[ -n "$TOTAL_ISSUES" && "$TOTAL_ISSUES" != "null" ]]; then
  echo "  Issues: ${CLOSED_ISSUES:-0}/${TOTAL_ISSUES} closed"
fi
if [[ -n "$PR_MERGED" && "$PR_MERGED" != "null" ]]; then
  echo "  PRs Merged: $PR_MERGED | Contributors: ${PR_CONTRIBUTORS:-N/A}"
fi
if [[ -n "$COMMIT_4W" && "$COMMIT_4W" != "null" ]]; then
  echo "  Commits (4 weeks): $COMMIT_4W"
fi
if [[ -n "$ADDITIONS" && "$ADDITIONS" != "null" ]]; then
  echo "  Code Changes (4w): +${ADDITIONS} / ${DELETIONS:-0}"
fi

# ========================
# Step 4: Dev activity assessment
# ========================
if [[ -n "$COMMIT_4W" && "$COMMIT_4W" != "null" ]]; then
  echo ""
  if [[ "$COMMIT_4W" -ge 100 ]] 2>/dev/null; then
    echo "  📊 Very active development (100+ commits/4w)"
  elif [[ "$COMMIT_4W" -ge 30 ]] 2>/dev/null; then
    echo "  📊 Active development (30+ commits/4w)"
  elif [[ "$COMMIT_4W" -ge 10 ]] 2>/dev/null; then
    echo "  📊 Moderate development (10+ commits/4w)"
  elif [[ "$COMMIT_4W" -gt 0 ]] 2>/dev/null; then
    echo "  📊 Low activity (< 10 commits/4w)"
  else
    echo "  ⚠️ No commits in last 4 weeks"
  fi
fi

echo ""
echo "=========================================="
echo "✅ CoinGecko community data complete."
echo "=========================================="
