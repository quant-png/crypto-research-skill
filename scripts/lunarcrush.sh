#!/bin/bash
# lunarcrush.sh — Fetch social sentiment data from LunarCrush API v4
# Usage: ./lunarcrush.sh <coin_symbol_or_name> [mode: summary|detail]
# Examples:
#   ./lunarcrush.sh bitcoin
#   ./lunarcrush.sh ETH detail
#
# Requires: LUNARCRUSH_API_KEY (free Discover plan available, or $24/mo for Pro)
# Get key at: https://lunarcrush.com/developers/api
#
# Returns: Galaxy Score, AltRank, sentiment, social dominance, social volume

set -euo pipefail

INPUT="${1:?Usage: $0 <coin_symbol_or_name> [mode: summary|detail]}"
MODE="${2:-summary}"

LC_KEY="${LUNARCRUSH_API_KEY:-}"
LC_BASE="https://lunarcrush.com/api4"

echo "=========================================="
echo "🌙 LunarCrush: $INPUT"
echo "=========================================="

if [[ -z "$LC_KEY" ]]; then
  echo "⚠️ LUNARCRUSH_API_KEY not set."
  echo "Get free Discover plan at: https://lunarcrush.com/developers/api"
  echo ""
  echo "Manual lookup: https://lunarcrush.com/coin/${INPUT}"
  exit 1
fi

# ========================
# Helper: LunarCrush GET
# ========================
lc_get() {
  local endpoint="$1"
  curl -s -L --max-time 15 \
    -H "Authorization: Bearer $LC_KEY" \
    -H "Accept: application/json" \
    "${LC_BASE}${endpoint}" 2>/dev/null || true
}

# ========================
# Fetch coin data
# ========================
# LunarCrush uses lowercase coin names/symbols
COIN=$(echo "$INPUT" | tr '[:upper:]' '[:lower:]')

DATA=$(lc_get "/public/coins/${COIN}/v1")

if [[ -z "$DATA" ]] || echo "$DATA" | jq -e '.error' &>/dev/null 2>&1; then
  # Try as symbol search
  DATA=$(lc_get "/public/coins/list/v1")
  if [[ -n "$DATA" ]]; then
    COIN_ID=$(echo "$DATA" | jq -r --arg q "$COIN" '.data[] | select(.symbol == ($q | ascii_upcase) or .name == ($q | ascii_downcase)) | .id // empty' 2>/dev/null | head -1)
    if [[ -n "$COIN_ID" ]]; then
      DATA=$(lc_get "/public/coins/${COIN_ID}/v1")
    fi
  fi
fi

if [[ -z "$DATA" ]] || echo "$DATA" | jq -e '.error' &>/dev/null 2>&1; then
  echo "⚠️ Could not fetch LunarCrush data for: $INPUT"
  echo "Check: https://lunarcrush.com/coin/${INPUT}"
  exit 1
fi

# ========================
# Parse response
# ========================
echo ""
echo "🎯 Social Metrics"
echo "---"

# Galaxy Score (0-100, overall social health)
GALAXY=$(echo "$DATA" | jq -r '.data.galaxy_score // .galaxy_score // empty' 2>/dev/null)
if [[ -n "$GALAXY" && "$GALAXY" != "null" ]]; then
  echo "  Galaxy Score: $GALAXY / 100"
  if [[ "${GALAXY%.*}" -ge 70 ]] 2>/dev/null; then
    echo "  📊 Strong social health"
  elif [[ "${GALAXY%.*}" -ge 40 ]] 2>/dev/null; then
    echo "  📊 Moderate social health"
  else
    echo "  📊 Weak social health"
  fi
fi

# AltRank (relative performance ranking, lower = better)
ALTRANK=$(echo "$DATA" | jq -r '.data.alt_rank // .alt_rank // empty' 2>/dev/null)
if [[ -n "$ALTRANK" && "$ALTRANK" != "null" ]]; then
  echo "  AltRank: #$ALTRANK"
fi

# Sentiment
SENTIMENT=$(echo "$DATA" | jq -r '.data.sentiment // .sentiment // empty' 2>/dev/null)
if [[ -n "$SENTIMENT" && "$SENTIMENT" != "null" ]]; then
  echo "  Sentiment: ${SENTIMENT}%"
fi

# Social dominance
DOMINANCE=$(echo "$DATA" | jq -r '.data.social_dominance // .social_dominance // empty' 2>/dev/null)
if [[ -n "$DOMINANCE" && "$DOMINANCE" != "null" ]]; then
  echo "  Social Dominance: ${DOMINANCE}%"
fi

# Social volume / interactions
SOCIAL_VOL=$(echo "$DATA" | jq -r '.data.social_volume // .social_volume // empty' 2>/dev/null)
if [[ -n "$SOCIAL_VOL" && "$SOCIAL_VOL" != "null" ]]; then
  echo "  Social Volume: $SOCIAL_VOL"
fi

INTERACTIONS=$(echo "$DATA" | jq -r '.data.social_interactions // .interactions // empty' 2>/dev/null)
if [[ -n "$INTERACTIONS" && "$INTERACTIONS" != "null" ]]; then
  echo "  Social Interactions: $INTERACTIONS"
fi

# Social contributors
CONTRIBUTORS=$(echo "$DATA" | jq -r '.data.social_contributors // .social_contributors // empty' 2>/dev/null)
if [[ -n "$CONTRIBUTORS" && "$CONTRIBUTORS" != "null" ]]; then
  echo "  Social Contributors: $CONTRIBUTORS"
fi

# Detail mode: show more metrics
if [[ "$MODE" == "detail" ]]; then
  echo ""
  echo "📈 Detailed Metrics"
  echo "---"

  # Market correlation with social
  CORRELATION=$(echo "$DATA" | jq -r '.data.correlation_rank // .correlation_rank // empty' 2>/dev/null)
  if [[ -n "$CORRELATION" && "$CORRELATION" != "null" ]]; then
    echo "  Price-Social Correlation Rank: #$CORRELATION"
  fi

  # News / media
  NEWS=$(echo "$DATA" | jq -r '.data.news // .news // empty' 2>/dev/null)
  if [[ -n "$NEWS" && "$NEWS" != "null" ]]; then
    echo "  News Articles: $NEWS"
  fi

  # Additional social breakdown
  echo "$DATA" | jq -r '
    (.data // .) |
    if .twitter_volume then "  Twitter Volume: \(.twitter_volume)" else empty end,
    if .reddit_volume then "  Reddit Volume: \(.reddit_volume)" else empty end,
    if .medium_volume then "  Medium Volume: \(.medium_volume)" else empty end,
    if .youtube_volume then "  YouTube Volume: \(.youtube_volume)" else empty end
  ' 2>/dev/null || true
fi

echo ""
echo "=========================================="
echo "✅ LunarCrush research complete."
echo "=========================================="
