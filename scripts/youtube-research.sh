#!/bin/bash
# youtube-research.sh — YouTube crypto research via yt-dlp
# Usage: ./youtube-research.sh <query_or_url> [mode: search|video]
# Examples:
#   ./youtube-research.sh "Vitalik Buterin Ethereum roadmap"
#   ./youtube-research.sh "https://youtube.com/watch?v=xxx" video
#
# Requires: yt-dlp

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/agent-reach-check.sh"

INPUT="${1:?Usage: $0 <query_or_url> [mode: search|video]}"
MODE="${2:-search}"

# Auto-detect: if input looks like a URL, switch to video mode
if [[ "$INPUT" == http* ]]; then
  MODE="video"
fi

require_ytdlp() {
  if [[ "$HAS_YTDLP" != "1" ]]; then
    echo "⚠️ yt-dlp not installed."
    echo "Install via: pip install yt-dlp  OR  brew install yt-dlp"
    echo ""
    local encoded
    encoded=$(echo "$INPUT" | sed 's/ /+/g')
    echo "Manual search: https://www.youtube.com/results?search_query=${encoded}"
    exit 1
  fi
}

do_search() {
  require_ytdlp
  echo "=========================================="
  echo "🎬 YouTube Search: $INPUT"
  echo "=========================================="
  echo ""

  # yt-dlp search: ytsearchN:query (flat-playlist for speed)
  local data
  data=$(yt-dlp --dump-json --flat-playlist "ytsearch5:${INPUT}" 2>/dev/null || true)

  if [[ -z "$data" ]]; then
    echo "No results or yt-dlp search failed"
    local encoded
    encoded=$(echo "$INPUT" | sed 's/ /+/g')
    echo "Try: https://www.youtube.com/results?search_query=${encoded}"
    return
  fi

  echo "$data" | jq -r '
    "🎥 \(.title // "N/A")",
    "   Channel: \(.channel // .uploader // "N/A") | Duration: \(.duration_string // "N/A") | Views: \(.view_count // "N/A")",
    "   URL: https://www.youtube.com/watch?v=\(.id // "")",
    ""
  ' 2>/dev/null || echo "$data" | head -30
}

do_video() {
  require_ytdlp
  echo "=========================================="
  echo "🎬 YouTube Video: $INPUT"
  echo "=========================================="
  echo ""

  local data
  data=$(yt-dlp --dump-json "$INPUT" 2>/dev/null || true)

  if [[ -z "$data" ]]; then
    echo "⚠️ Failed to fetch video metadata"
    echo "Check URL: $INPUT"
    return
  fi

  echo "$data" | jq -r '
    "Title: \(.title // "N/A")",
    "Channel: \(.channel // .uploader // "N/A")",
    "Published: \(.upload_date // "N/A")",
    "Duration: \(.duration_string // "N/A")",
    "Views: \(.view_count // "N/A") | Likes: \(.like_count // "N/A")",
    "",
    "Description:",
    "\(.description // "" | .[0:500])"
  ' 2>/dev/null || echo "$data" | head -30
}

case "$MODE" in
  search) do_search ;;
  video)  do_video ;;
  *)      echo "Unknown mode: $MODE. Use: search, video"; exit 1 ;;
esac

echo ""
echo "=========================================="
echo "✅ YouTube research complete."
echo "=========================================="
