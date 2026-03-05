#!/bin/bash
# community-traction.sh — Fetch community traction metrics
# Usage: ./community-traction.sh <project_name_or_id>
# Example: ./community-traction.sh Ethereum
# Example: ./community-traction.sh 12
#
# Data priority:
#   1. CoinGecko community_data + developer_data (free, richest data)
#   2. Telegram Bot API (free, accurate member count if TELEGRAM_BOT_TOKEN set)
#   3. Discord Invite API (free, no auth)
#   4. RootData social links + t.me scraping (fallback)
#   5. LunarCrush social sentiment (optional, if LUNARCRUSH_API_KEY set)

set -euo pipefail

INPUT="${1:?Usage: $0 <project_name_or_id>}"

RD_KEY="${ROOTDATA_API_KEY:-}"
RD_BASE="https://api.rootdata.com/open"
TG_BOT="${TELEGRAM_BOT_TOKEN:-}"

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
# Step 1: Resolve project & get social links from RootData
# ========================
PROJECT_NAME=""
TWITTER_URL=""
DISCORD_URL=""
TELEGRAM_URL=""
RD_FOLLOWERS=""
RD_INFLUENCE=""
RD_INFLUENCE_RANK=""

get_social_links() {
  if [[ -z "$RD_KEY" ]]; then
    return 1
  fi

  local project_id="$INPUT"

  # Resolve name to ID if not numeric
  if [[ ! "$INPUT" =~ ^[0-9]+$ ]]; then
    local search_data
    search_data=$(rd_post "ser_inv" "{\"query\": \"$INPUT\"}")
    local code
    code=$(echo "$search_data" | jq -r '.result // 0')
    if [[ "$code" != "200" ]]; then
      return 1
    fi
    project_id=$(echo "$search_data" | jq -r '[.data[] | select(.type == 1)][0].id // empty')
    if [[ -z "$project_id" ]]; then
      return 1
    fi
    PROJECT_NAME=$(echo "$search_data" | jq -r '[.data[] | select(.type == 1)][0].name // "Unknown"')
  fi

  local data
  data=$(rd_post "get_item" "{\"project_id\": $project_id, \"include_team\": false, \"include_investors\": false}")
  local code
  code=$(echo "$data" | jq -r '.result // 0')
  if [[ "$code" != "200" ]]; then
    return 1
  fi

  PROJECT_NAME=$(echo "$data" | jq -r '.data.project_name // "Unknown"')
  TWITTER_URL=$(echo "$data" | jq -r '.data.social_media.twitter // ""')
  DISCORD_URL=$(echo "$data" | jq -r '.data.social_media.discord // ""')
  TELEGRAM_URL=$(echo "$data" | jq -r '.data.social_media.telegram // ""')
  RD_FOLLOWERS=$(echo "$data" | jq -r '.data.followers // ""')
  RD_INFLUENCE=$(echo "$data" | jq -r '.data.influence // ""')
  RD_INFLUENCE_RANK=$(echo "$data" | jq -r '.data.influence_rank // ""')

  echo "Project: $PROJECT_NAME"
  return 0
}

# ========================
# Step 2: CoinGecko community_data + developer_data (primary)
# ========================
fetch_coingecko() {
  echo ""
  echo "📊 CoinGecko Community & Dev Data"
  echo "---"

  local CG_KEY="${COINGECKO_API_KEY:-}"
  local CG_BASE="https://api.coingecko.com/api/v3"
  if [[ -n "$CG_KEY" ]]; then
    CG_BASE="https://pro-api.coingecko.com/api/v3"
  fi

  cg_get() {
    local endpoint="$1"
    if [[ -n "$CG_KEY" ]]; then
      curl -s -L --max-time 15 "${CG_BASE}${endpoint}" \
        -H "x-cg-pro-api-key: $CG_KEY" -H "Accept: application/json" 2>/dev/null || true
    else
      curl -s -L --max-time 15 "${CG_BASE}${endpoint}" \
        -H "Accept: application/json" 2>/dev/null || true
    fi
  }

  # Resolve coin ID
  local coin_id
  coin_id=$(echo "$INPUT" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  local data
  data=$(cg_get "/coins/${coin_id}?localization=false&tickers=false&market_data=false&community_data=true&developer_data=true&sparkline=false")

  # If direct fetch fails, search
  if [[ -z "$data" ]] || echo "$data" | jq -e '.error' &>/dev/null 2>&1; then
    local search
    search=$(cg_get "/search?query=${INPUT}")
    if [[ -n "$search" ]]; then
      coin_id=$(echo "$search" | jq -r '.coins[0].id // empty' 2>/dev/null)
      if [[ -n "$coin_id" ]]; then
        data=$(cg_get "/coins/${coin_id}?localization=false&tickers=false&market_data=false&community_data=true&developer_data=true&sparkline=false")
      fi
    fi
  fi

  if [[ -z "$data" ]] || echo "$data" | jq -e '.error' &>/dev/null 2>&1; then
    echo "  CoinGecko: data not available for $INPUT"
    return
  fi

  # Community data
  local tg_members reddit_subs reddit_active reddit_posts reddit_comments
  tg_members=$(echo "$data" | jq -r '.community_data.telegram_channel_user_count // empty' 2>/dev/null)
  reddit_subs=$(echo "$data" | jq -r '.community_data.reddit_subscribers // empty' 2>/dev/null)
  reddit_active=$(echo "$data" | jq -r '.community_data.reddit_accounts_active_48h // empty' 2>/dev/null)
  reddit_posts=$(echo "$data" | jq -r '.community_data.reddit_average_posts_48h // empty' 2>/dev/null)
  reddit_comments=$(echo "$data" | jq -r '.community_data.reddit_average_comments_48h // empty' 2>/dev/null)

  [[ -n "$tg_members" && "$tg_members" != "null" ]] && echo "  Telegram (CoinGecko): $tg_members members"
  [[ -n "$reddit_subs" && "$reddit_subs" != "null" ]] && echo "  Reddit Subscribers: $reddit_subs"
  [[ -n "$reddit_active" && "$reddit_active" != "null" && "$reddit_active" != "0" ]] && echo "  Reddit Active (48h): $reddit_active"
  [[ -n "$reddit_posts" && "$reddit_posts" != "null" ]] && echo "  Reddit Posts (avg 48h): $reddit_posts"
  [[ -n "$reddit_comments" && "$reddit_comments" != "null" ]] && echo "  Reddit Comments (avg 48h): $reddit_comments"

  # Developer data
  local stars forks total_issues closed_issues pr_merged pr_contrib commit_4w additions deletions
  stars=$(echo "$data" | jq -r '.developer_data.stars // empty' 2>/dev/null)
  forks=$(echo "$data" | jq -r '.developer_data.forks // empty' 2>/dev/null)
  total_issues=$(echo "$data" | jq -r '.developer_data.total_issues // empty' 2>/dev/null)
  closed_issues=$(echo "$data" | jq -r '.developer_data.closed_issues // empty' 2>/dev/null)
  pr_merged=$(echo "$data" | jq -r '.developer_data.pull_requests_merged // empty' 2>/dev/null)
  pr_contrib=$(echo "$data" | jq -r '.developer_data.pull_request_contributors // empty' 2>/dev/null)
  commit_4w=$(echo "$data" | jq -r '.developer_data.commit_count_4_weeks // empty' 2>/dev/null)
  additions=$(echo "$data" | jq -r '.developer_data.code_additions_deletions_4_weeks.additions // empty' 2>/dev/null)
  deletions=$(echo "$data" | jq -r '.developer_data.code_additions_deletions_4_weeks.deletions // empty' 2>/dev/null)

  if [[ -n "$stars" && "$stars" != "null" ]]; then
    echo "  GitHub: ⭐ $stars | 🍴 ${forks:-0} | Issues: ${closed_issues:-0}/${total_issues:-0} closed"
    [[ -n "$pr_merged" && "$pr_merged" != "null" ]] && echo "  PRs Merged: $pr_merged | Contributors: ${pr_contrib:-N/A}"
    [[ -n "$commit_4w" && "$commit_4w" != "null" ]] && echo "  Commits (4w): $commit_4w | Code: +${additions:-0} / ${deletions:-0}"
  fi
}

# ========================
# Step 3: Telegram Bot API (accurate member count)
# ========================
fetch_telegram() {
  echo ""
  echo "📱 Telegram"
  echo "---"

  local tg_handle=""
  if [[ -n "${TELEGRAM_URL:-}" ]]; then
    tg_handle=$(echo "$TELEGRAM_URL" | grep -oE '(t\.me|telegram\.me)/([a-zA-Z0-9_]+)' | sed 's|.*[/]||' || true)
  fi

  if [[ -z "$tg_handle" ]]; then
    echo "  No Telegram link found"
    return
  fi

  echo "  Handle: @$tg_handle"

  # Try Telegram Bot API first (most accurate)
  if [[ -n "$TG_BOT" ]]; then
    local bot_data
    bot_data=$(curl -s -L --max-time 10 \
      "https://api.telegram.org/bot${TG_BOT}/getChatMemberCount?chat_id=@${tg_handle}" 2>/dev/null || true)
    if [[ -n "$bot_data" ]]; then
      local ok
      ok=$(echo "$bot_data" | jq -r '.ok // false' 2>/dev/null)
      if [[ "$ok" == "true" ]]; then
        local count
        count=$(echo "$bot_data" | jq -r '.result // empty' 2>/dev/null)
        if [[ -n "$count" ]]; then
          echo "  Members (Bot API): $count"
          _tg_size "$count"
          return
        fi
      fi
    fi
  fi

  # Fallback: scrape t.me preview page
  local tg_page
  tg_page=$(curl -s -L --max-time 10 "https://t.me/${tg_handle}" 2>/dev/null || true)
  if [[ -z "$tg_page" ]]; then
    echo "  Could not fetch Telegram data"
    return
  fi

  local members=""
  members=$(echo "$tg_page" | grep -oE '[0-9 ]+members' | head -1 | grep -oE '[0-9 ]+' | tr -d ' ' || true)
  [[ -z "$members" ]] && members=$(echo "$tg_page" | grep -oE '[0-9 ]+subscribers' | head -1 | grep -oE '[0-9 ]+' | tr -d ' ' || true)
  [[ -z "$members" ]] && members=$(echo "$tg_page" | grep -oE '[0-9,]+ members' | head -1 | grep -oE '[0-9,]+' | tr -d ',' || true)
  [[ -z "$members" ]] && members=$(echo "$tg_page" | grep -oE '[0-9,]+ subscribers' | head -1 | grep -oE '[0-9,]+' | tr -d ',' || true)

  if [[ -n "$members" ]]; then
    echo "  Members (t.me): $members"
    _tg_size "$members"
  else
    echo "  Member count not available"
    echo "  Link: ${TELEGRAM_URL}"
  fi
}

_tg_size() {
  local c="$1"
  if [[ "$c" -ge 100000 ]] 2>/dev/null; then echo "  📊 LARGE (100K+)"
  elif [[ "$c" -ge 30000 ]] 2>/dev/null; then echo "  📊 Strong (30K+)"
  elif [[ "$c" -ge 10000 ]] 2>/dev/null; then echo "  📊 Medium (10K+)"
  elif [[ "$c" -ge 1000 ]] 2>/dev/null; then echo "  📊 Small (1K+)"
  else echo "  📊 Very small (<1K)"
  fi
}

# ========================
# Step 4: Discord (invite API, free)
# ========================
fetch_discord() {
  echo ""
  echo "💬 Discord"
  echo "---"

  if [[ -z "${DISCORD_URL:-}" ]]; then
    echo "  No Discord link found"
    return
  fi

  local invite_code=""
  invite_code=$(echo "$DISCORD_URL" | grep -oE '(discord\.gg|discord\.com/invite)/([a-zA-Z0-9_-]+)' | sed 's|.*[/]||' || true)

  if [[ -z "$invite_code" ]]; then
    echo "  Could not extract invite code"
    echo "  Link: $DISCORD_URL"
    return
  fi

  local discord_data
  discord_data=$(curl -s -L --max-time 10 \
    "https://discord.com/api/v10/invites/${invite_code}?with_counts=true" 2>/dev/null || true)

  if [[ -z "$discord_data" ]] || ! echo "$discord_data" | jq -e '.approximate_member_count' &>/dev/null 2>&1; then
    echo "  Invite may be expired or invalid"
    echo "  Link: $DISCORD_URL"
    return
  fi

  local members online guild_name
  members=$(echo "$discord_data" | jq -r '.approximate_member_count // "N/A"')
  online=$(echo "$discord_data" | jq -r '.approximate_presence_count // "N/A"')
  guild_name=$(echo "$discord_data" | jq -r '.guild.name // "N/A"')

  echo "  Server: $guild_name"
  echo "  Members: $members | Online: $online"

  if [[ "$members" != "N/A" && "$online" != "N/A" && "$members" -gt 0 ]]; then
    local ratio
    ratio=$(echo "scale=1; $online * 100 / $members" | bc 2>/dev/null || true)
    [[ -n "$ratio" ]] && echo "  Online Ratio: ${ratio}%"
  fi

  if [[ "$members" != "N/A" ]]; then
    if [[ "$members" -ge 100000 ]]; then echo "  📊 LARGE (100K+)"
    elif [[ "$members" -ge 30000 ]]; then echo "  📊 Strong (30K+)"
    elif [[ "$members" -ge 10000 ]]; then echo "  📊 Medium (10K+)"
    elif [[ "$members" -ge 1000 ]]; then echo "  📊 Small (1K+)"
    else echo "  📊 Very small (<1K)"
    fi
  fi
}

# ========================
# Step 5: Twitter / X (RootData PRO fields only)
# ========================
fetch_twitter() {
  echo ""
  echo "🐦 Twitter / X"
  echo "---"

  if [[ -z "${TWITTER_URL:-}" ]]; then
    echo "  No Twitter link found"
    return
  fi

  local handle=""
  handle=$(echo "$TWITTER_URL" | grep -oE '(twitter\.com|x\.com)/([a-zA-Z0-9_]+)' | sed 's|.*[/]||' || true)
  [[ -n "$handle" ]] && echo "  Handle: @$handle"

  if [[ -n "${RD_FOLLOWERS:-}" && "${RD_FOLLOWERS}" != "null" && "${RD_FOLLOWERS}" != "" ]]; then
    echo "  Followers (RootData): $RD_FOLLOWERS"
  fi
  if [[ -n "${RD_INFLUENCE:-}" && "${RD_INFLUENCE}" != "null" && "${RD_INFLUENCE}" != "" ]]; then
    echo "  Influence Score: $RD_INFLUENCE"
  fi
  if [[ -n "${RD_INFLUENCE_RANK:-}" && "${RD_INFLUENCE_RANK}" != "null" && "${RD_INFLUENCE_RANK}" != "" ]]; then
    echo "  Influence Rank: #$RD_INFLUENCE_RANK"
  fi

  # Note: X API Basic $200/mo, CoinGecko removed twitter_followers May 2025
  if [[ -z "${RD_FOLLOWERS:-}" || "${RD_FOLLOWERS}" == "null" || "${RD_FOLLOWERS}" == "" ]]; then
    echo "  Follower count: no free API available"
    echo "  Link: $TWITTER_URL"
  fi
}

# ========================
# Step 6: LunarCrush (optional)
# ========================
fetch_lunarcrush() {
  local LC_KEY="${LUNARCRUSH_API_KEY:-}"
  if [[ -z "$LC_KEY" ]]; then
    return
  fi

  echo ""
  echo "🌙 LunarCrush Social Sentiment"
  echo "---"

  local coin
  coin=$(echo "$INPUT" | tr '[:upper:]' '[:lower:]')
  local data
  data=$(curl -s -L --max-time 15 \
    -H "Authorization: Bearer $LC_KEY" \
    -H "Accept: application/json" \
    "https://lunarcrush.com/api4/public/coins/${coin}/v1" 2>/dev/null || true)

  if [[ -z "$data" ]] || echo "$data" | jq -e '.error' &>/dev/null 2>&1; then
    echo "  LunarCrush: data not available"
    return
  fi

  local galaxy altrank sentiment dominance
  galaxy=$(echo "$data" | jq -r '.data.galaxy_score // .galaxy_score // empty' 2>/dev/null)
  altrank=$(echo "$data" | jq -r '.data.alt_rank // .alt_rank // empty' 2>/dev/null)
  sentiment=$(echo "$data" | jq -r '.data.sentiment // .sentiment // empty' 2>/dev/null)
  dominance=$(echo "$data" | jq -r '.data.social_dominance // .social_dominance // empty' 2>/dev/null)

  [[ -n "$galaxy" && "$galaxy" != "null" ]] && echo "  Galaxy Score: $galaxy / 100"
  [[ -n "$altrank" && "$altrank" != "null" ]] && echo "  AltRank: #$altrank"
  [[ -n "$sentiment" && "$sentiment" != "null" ]] && echo "  Sentiment: ${sentiment}%"
  [[ -n "$dominance" && "$dominance" != "null" ]] && echo "  Social Dominance: ${dominance}%"
}

# ========================
# Summary
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
  echo "  • Rapid member growth + low engagement = bot farming risk"
}

# ========================
# Main — execute in priority order
# ========================

get_social_links || true

# 1. CoinGecko (primary: community + dev data)
fetch_coingecko

# 2. Telegram (Bot API or t.me scrape)
fetch_telegram

# 3. Discord (invite API)
fetch_discord

# 4. Twitter (RootData PRO only)
fetch_twitter

# 5. LunarCrush (optional)
fetch_lunarcrush

# Summary
print_summary

echo ""
echo "=========================================="
echo "✅ Community traction research complete."
echo "=========================================="
