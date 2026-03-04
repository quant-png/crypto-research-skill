#!/bin/bash
# community-traction.sh — Fetch community traction metrics (Discord, Twitter, Telegram)
# Usage: ./community-traction.sh <project_name_or_id>
# Example: ./community-traction.sh Ethereum
# Example: ./community-traction.sh 12
#
# Fetches social links from RootData, then:
# - Discord: member count via invite API (free, no auth)
# - Twitter/X: follower count from RootData PRO (if available) + profile link
# - Telegram: member count by scraping t.me preview page

set -euo pipefail

INPUT="${1:?Usage: $0 <project_name_or_id>}"

RD_KEY="${ROOTDATA_API_KEY:-}"
RD_BASE="https://api.rootdata.com/open"

echo "=========================================="
echo "👥 Community Traction: $INPUT"
echo "=========================================="

# ========================
# Helper: RootData API call
# ========================
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

# ========================
# Step 1: Get social links from RootData
# ========================
get_social_links() {
  if [[ -z "$RD_KEY" ]]; then
    echo "⚠️ ROOTDATA_API_KEY not set — cannot auto-detect social links."
    echo "   Provide Discord/Twitter/Telegram links manually."
    return 1
  fi

  local project_id="$INPUT"

  # Resolve name to ID if not numeric
  if [[ ! "$INPUT" =~ ^[0-9]+$ ]]; then
    echo "🔍 Searching RootData for: $INPUT"
    local search_data
    search_data=$(rd_post "ser_inv" "{\"query\": \"$INPUT\"}")
    local code
    code=$(echo "$search_data" | jq -r '.result // 0')
    if [[ "$code" != "200" ]]; then
      echo "⚠️ RootData search failed"
      return 1
    fi
    project_id=$(echo "$search_data" | jq -r '[.data[] | select(.type == 1)][0].id // empty')
    if [[ -z "$project_id" ]]; then
      echo "⚠️ Project not found on RootData"
      return 1
    fi
    local pname
    pname=$(echo "$search_data" | jq -r '[.data[] | select(.type == 1)][0].name // "Unknown"')
    echo "Found: $pname (ID: $project_id)"
  fi

  echo "📋 Fetching project social links..."
  local data
  data=$(rd_post "get_item" "{\"project_id\": $project_id, \"include_team\": false, \"include_investors\": false}")
  local code
  code=$(echo "$data" | jq -r '.result // 0')
  if [[ "$code" != "200" ]]; then
    echo "⚠️ Failed to fetch project detail"
    return 1
  fi

  PROJECT_NAME=$(echo "$data" | jq -r '.data.project_name // "Unknown"')
  TWITTER_URL=$(echo "$data" | jq -r '.data.social_media.twitter // ""')
  DISCORD_URL=$(echo "$data" | jq -r '.data.social_media.discord // ""')
  TELEGRAM_URL=$(echo "$data" | jq -r '.data.social_media.telegram // ""')

  # PRO fields (may be empty on Basic tier)
  RD_FOLLOWERS=$(echo "$data" | jq -r '.data.followers // ""')
  RD_INFLUENCE=$(echo "$data" | jq -r '.data.influence // ""')
  RD_INFLUENCE_RANK=$(echo "$data" | jq -r '.data.influence_rank // ""')

  echo ""
  echo "Project: $PROJECT_NAME"
  echo "Social links found:"
  [[ -n "$TWITTER_URL" ]] && echo "  Twitter: $TWITTER_URL" || echo "  Twitter: not listed"
  [[ -n "$DISCORD_URL" ]] && echo "  Discord: $DISCORD_URL" || echo "  Discord: not listed"
  [[ -n "$TELEGRAM_URL" ]] && echo "  Telegram: $TELEGRAM_URL" || echo "  Telegram: not listed"
  return 0
}

# ========================
# Step 2: Discord member count
# ========================
fetch_discord() {
  echo ""
  echo "💬 Discord"
  echo "---"

  if [[ -z "${DISCORD_URL:-}" ]]; then
    echo "  No Discord link found on RootData"
    return
  fi

  echo "  Link: $DISCORD_URL"

  # Extract invite code from various Discord URL formats
  # https://discord.gg/CODE
  # https://discord.com/invite/CODE
  # https://discord.gg/CODE?param=value
  local invite_code=""
  invite_code=$(echo "$DISCORD_URL" | grep -oE '(discord\.gg|discord\.com/invite)/([a-zA-Z0-9_-]+)' | sed 's|.*[/]||' || true)

  if [[ -z "$invite_code" ]]; then
    echo "  ⚠️ Could not extract invite code from URL"
    echo "  Check manually: $DISCORD_URL"
    return
  fi

  # Call Discord invite API (free, no auth needed)
  local discord_data
  discord_data=$(curl -s -L --max-time 10 \
    "https://discord.com/api/v9/invites/${invite_code}?with_counts=true" 2>/dev/null || true)

  if [[ -z "$discord_data" ]]; then
    echo "  ⚠️ Discord API request failed"
    return
  fi

  # Check for error
  local err_code
  err_code=$(echo "$discord_data" | jq -r '.code // ""' 2>/dev/null)
  if [[ "$err_code" == "10006" ]] || echo "$discord_data" | jq -e '.message' &>/dev/null 2>&1 && [[ "$err_code" != "" ]] && ! echo "$discord_data" | jq -e '.approximate_member_count' &>/dev/null 2>&1; then
    echo "  ⚠️ Invite may be expired or invalid"
    echo "  Check manually: $DISCORD_URL"
    return
  fi

  local members online guild_name
  members=$(echo "$discord_data" | jq -r '.approximate_member_count // "N/A"')
  online=$(echo "$discord_data" | jq -r '.approximate_presence_count // "N/A"')
  guild_name=$(echo "$discord_data" | jq -r '.guild.name // "N/A"')

  echo "  Server: $guild_name"
  echo "  Members: $members"
  echo "  Online: $online"

  # Calculate online ratio
  if [[ "$members" != "N/A" && "$online" != "N/A" && "$members" -gt 0 ]]; then
    local ratio
    ratio=$(echo "scale=1; $online * 100 / $members" | bc 2>/dev/null || true)
    if [[ -n "$ratio" ]]; then
      echo "  Online Ratio: ${ratio}%"
    fi
  fi

  # Size assessment
  if [[ "$members" != "N/A" ]]; then
    if [[ "$members" -ge 100000 ]]; then
      echo "  📊 LARGE community (100K+)"
    elif [[ "$members" -ge 30000 ]]; then
      echo "  📊 Strong community (30K+)"
    elif [[ "$members" -ge 10000 ]]; then
      echo "  📊 Medium community (10K+)"
    elif [[ "$members" -ge 1000 ]]; then
      echo "  📊 Small community (1K+)"
    else
      echo "  📊 Very small community (<1K)"
    fi
  fi
}

# ========================
# Step 3: Twitter / X metrics
# ========================
fetch_twitter() {
  echo ""
  echo "🐦 Twitter / X"
  echo "---"

  if [[ -z "${TWITTER_URL:-}" ]]; then
    echo "  No Twitter link found on RootData"
    return
  fi

  echo "  Link: $TWITTER_URL"

  # Extract handle from URL
  local handle=""
  handle=$(echo "$TWITTER_URL" | grep -oE '(twitter\.com|x\.com)/([a-zA-Z0-9_]+)' | sed 's|.*[/]||' || true)
  if [[ -n "$handle" ]]; then
    echo "  Handle: @$handle"
  fi

  # RootData PRO fields (followers/influence)
  if [[ -n "${RD_FOLLOWERS:-}" && "${RD_FOLLOWERS}" != "null" && "${RD_FOLLOWERS}" != "" ]]; then
    echo "  Followers (RootData): $RD_FOLLOWERS"
  fi

  if [[ -n "${RD_INFLUENCE:-}" && "${RD_INFLUENCE}" != "null" && "${RD_INFLUENCE}" != "" ]]; then
    echo "  Influence Score (RootData): $RD_INFLUENCE"
  fi

  if [[ -n "${RD_INFLUENCE_RANK:-}" && "${RD_INFLUENCE_RANK}" != "null" && "${RD_INFLUENCE_RANK}" != "" ]]; then
    echo "  Influence Rank (RootData): #$RD_INFLUENCE_RANK"
  fi

  # Try to get follower count via scraping (best effort)
  # Twitter/X doesn't allow easy scraping, so we try a social-blade style approach
  if [[ -n "$handle" ]]; then
    # Try to fetch from Nitter or similar public mirrors
    local follower_count=""

    # Try socialcounts.org API (free, no auth)
    local social_data
    social_data=$(curl -s -L --max-time 10 \
      "https://api.socialcounts.org/twitter-live-follower-count/${handle}" 2>/dev/null || true)
    if [[ -n "$social_data" ]]; then
      follower_count=$(echo "$social_data" | jq -r '.est_sub // .followerCount // .followers // ""' 2>/dev/null || true)
    fi

    if [[ -n "$follower_count" && "$follower_count" != "null" && "$follower_count" != "" ]]; then
      echo "  Followers (live): $follower_count"

      # Size assessment
      if [[ "$follower_count" -ge 1000000 ]] 2>/dev/null; then
        echo "  📊 MASSIVE following (1M+)"
      elif [[ "$follower_count" -ge 500000 ]] 2>/dev/null; then
        echo "  📊 Very large following (500K+)"
      elif [[ "$follower_count" -ge 100000 ]] 2>/dev/null; then
        echo "  📊 Large following (100K+)"
      elif [[ "$follower_count" -ge 30000 ]] 2>/dev/null; then
        echo "  📊 Strong following (30K+)"
      elif [[ "$follower_count" -ge 10000 ]] 2>/dev/null; then
        echo "  📊 Medium following (10K+)"
      elif [[ "$follower_count" -ge 1000 ]] 2>/dev/null; then
        echo "  📊 Small following (1K+)"
      else
        echo "  📊 Very small following (<1K)"
      fi
    else
      echo "  ℹ️ Follower count not available via free APIs"
      echo "  Check manually: $TWITTER_URL"
    fi
  fi
}

# ========================
# Step 4: Telegram metrics
# ========================
fetch_telegram() {
  echo ""
  echo "📱 Telegram"
  echo "---"

  if [[ -z "${TELEGRAM_URL:-}" ]]; then
    echo "  No Telegram link found on RootData"
    return
  fi

  echo "  Link: $TELEGRAM_URL"

  # Extract handle/channel from URL
  # https://t.me/channel_name
  # https://telegram.me/channel_name
  local tg_handle=""
  tg_handle=$(echo "$TELEGRAM_URL" | grep -oE '(t\.me|telegram\.me)/([a-zA-Z0-9_]+)' | sed 's|.*[/]||' || true)

  if [[ -z "$tg_handle" ]]; then
    echo "  ⚠️ Could not extract handle from URL"
    echo "  Check manually: $TELEGRAM_URL"
    return
  fi

  echo "  Handle: @$tg_handle"

  # Scrape t.me page for member count (public, no auth)
  # The t.me preview pages include member counts in the HTML
  local tg_page
  tg_page=$(curl -s -L --max-time 10 \
    "https://t.me/${tg_handle}" 2>/dev/null || true)

  if [[ -z "$tg_page" ]]; then
    echo "  ⚠️ Could not fetch Telegram page"
    return
  fi

  # Extract member count from meta tags or page content
  # Pattern: "N members" or "N subscribers" in the page
  local members=""
  members=$(echo "$tg_page" | grep -oE '[0-9 ]+members' | head -1 | grep -oE '[0-9 ]+' | tr -d ' ' || true)
  if [[ -z "$members" ]]; then
    members=$(echo "$tg_page" | grep -oE '[0-9 ]+subscribers' | head -1 | grep -oE '[0-9 ]+' | tr -d ' ' || true)
  fi
  # Also try comma-formatted numbers
  if [[ -z "$members" ]]; then
    members=$(echo "$tg_page" | grep -oE '[0-9,]+ members' | head -1 | grep -oE '[0-9,]+' | tr -d ',' || true)
  fi
  if [[ -z "$members" ]]; then
    members=$(echo "$tg_page" | grep -oE '[0-9,]+ subscribers' | head -1 | grep -oE '[0-9,]+' | tr -d ',' || true)
  fi

  # Also try "N online" for groups
  local online=""
  online=$(echo "$tg_page" | grep -oE '[0-9 ]+online' | head -1 | grep -oE '[0-9 ]+' | tr -d ' ' || true)
  if [[ -z "$online" ]]; then
    online=$(echo "$tg_page" | grep -oE '[0-9,]+ online' | head -1 | grep -oE '[0-9,]+' | tr -d ',' || true)
  fi

  if [[ -n "$members" ]]; then
    echo "  Members: $members"
    [[ -n "$online" ]] && echo "  Online: $online"

    # Size assessment
    if [[ "$members" -ge 100000 ]] 2>/dev/null; then
      echo "  📊 LARGE community (100K+)"
    elif [[ "$members" -ge 30000 ]] 2>/dev/null; then
      echo "  📊 Strong community (30K+)"
    elif [[ "$members" -ge 10000 ]] 2>/dev/null; then
      echo "  📊 Medium community (10K+)"
    elif [[ "$members" -ge 1000 ]] 2>/dev/null; then
      echo "  📊 Small community (1K+)"
    else
      echo "  📊 Very small community (<1K)"
    fi
  else
    echo "  ℹ️ Member count not available from preview page"
    echo "  Check manually: $TELEGRAM_URL"
  fi
}

# ========================
# Step 5: Community Traction Summary
# ========================
print_summary() {
  echo ""
  echo "📊 Community Traction Summary"
  echo "=========================================="
  echo ""
  echo "Evaluation Guide:"
  echo "  • Discord 100K+ / Twitter 500K+ / TG 100K+ = Top-tier community"
  echo "  • Discord 30K+  / Twitter 100K+ / TG 30K+  = Strong community"
  echo "  • Discord 10K+  / Twitter 30K+  / TG 10K+  = Growing community"
  echo "  • Below these thresholds = Early-stage or niche"
  echo ""
  echo "Red Flags:"
  echo "  • No Discord/TG at all = unusual for crypto projects"
  echo "  • Very low online ratio (<1%) = possible bot-inflated numbers"
  echo "  • Large Discord but tiny TG (or vice versa) = check regional focus"
  echo "  • Rapid member growth + low engagement = bot farming risk"
  echo ""
  echo "Green Flags:"
  echo "  • Healthy online ratio (5-15%) in Discord"
  echo "  • Consistent growth across all platforms"
  echo "  • Active TG with real discussions"
  echo "  • Twitter engagement > follower count suggests quality audience"
}

# ========================
# Main
# ========================

# Initialize variables
PROJECT_NAME=""
TWITTER_URL=""
DISCORD_URL=""
TELEGRAM_URL=""
RD_FOLLOWERS=""
RD_INFLUENCE=""
RD_INFLUENCE_RANK=""

if get_social_links; then
  fetch_discord
  fetch_twitter
  fetch_telegram
  print_summary
else
  echo ""
  echo "⚠️ Could not auto-detect social links."
  echo ""
  echo "ℹ️ To check community manually:"
  echo "  • Discord: look up the project's Discord invite link"
  echo "  • Twitter: search for the project on X/Twitter"
  echo "  • Telegram: search for the project group on Telegram"
  print_summary
fi

echo ""
echo "=========================================="
echo "✅ Community traction research complete."
echo "=========================================="
