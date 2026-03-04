#!/bin/bash
# github-activity.sh — GitHub project development activity
# Usage: ./github-activity.sh <owner/repo_or_query> [mode: repo|search|activity]
# Examples:
#   ./github-activity.sh ethereum/go-ethereum
#   ./github-activity.sh uniswap search
#   ./github-activity.sh aave/aave-v3-core activity
#
# Prefers gh CLI (authenticated), falls back to curl + GitHub API (60 req/hr).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/agent-reach-check.sh"

INPUT="${1:?Usage: $0 <owner/repo_or_query> [mode: repo|search|activity]}"
MODE="${2:-}"

# Auto-detect mode: if input has / → repo, else → search
if [[ -z "$MODE" ]]; then
  if [[ "$INPUT" == *"/"* ]]; then
    MODE="repo"
  else
    MODE="search"
  fi
fi

# ========================
# Helper: gh CLI or curl fallback
# ========================
gh_api() {
  local endpoint="$1"
  if [[ "$HAS_GH" == "1" ]]; then
    gh api "$endpoint" 2>/dev/null || true
  else
    curl -s -L --max-time 15 \
      "https://api.github.com${endpoint}" \
      -H "Accept: application/vnd.github+json" \
      -H "User-Agent: crypto-research-skill/2.5" 2>/dev/null || true
  fi
}

# ========================
# Mode: repo — repository overview
# ========================
do_repo() {
  local repo="$INPUT"
  echo "=========================================="
  echo "🐙 GitHub Repo: $repo"
  echo "=========================================="

  local data
  data=$(gh_api "/repos/$repo")

  if [[ -z "$data" ]] || echo "$data" | jq -e '.message' &>/dev/null 2>&1; then
    local msg
    msg=$(echo "$data" | jq -r '.message // "Unknown error"' 2>/dev/null || echo "Request failed")
    echo "⚠️ $msg: $repo"
    echo "Check: https://github.com/$repo"
    return
  fi

  echo ""
  echo "$data" | jq -r '
    "Name: \(.full_name // "N/A")",
    "Description: \(.description // "N/A")",
    "⭐ \(.stargazers_count // 0) | 🍴 \(.forks_count // 0) | 👀 \(.subscribers_count // 0)",
    "Language: \(.language // "N/A") | License: \(.license.spdx_id // "None")",
    "Open Issues: \(.open_issues_count // 0)",
    "Created: \(.created_at // "N/A" | .[0:10]) | Last Push: \(.pushed_at // "N/A" | .[0:10])",
    "Archived: \(.archived // false)"
  ' 2>/dev/null || echo "Parse error"

  # Recent commits
  echo ""
  echo "📝 Recent Commits"
  echo "---"
  local commits
  commits=$(gh_api "/repos/$repo/commits?per_page=5")
  if [[ -n "$commits" ]]; then
    echo "$commits" | jq -r '.[:5][] |
      "\(.commit.author.date // "" | .[0:10]) \(.commit.author.name // "N/A")",
      "  \(.commit.message // "N/A" | split("\n")[0] | .[0:100])",
      ""
    ' 2>/dev/null || echo "  Could not parse commits"
  fi

  # Top contributors
  echo "👥 Top Contributors"
  echo "---"
  local contribs
  contribs=$(gh_api "/repos/$repo/contributors?per_page=5")
  if [[ -n "$contribs" ]]; then
    echo "$contribs" | jq -r '.[:5][] |
      "  \(.login // "N/A"): \(.contributions // 0) commits"
    ' 2>/dev/null || echo "  Could not parse contributors"
  fi
}

# ========================
# Mode: search — find repositories
# ========================
do_search() {
  echo "=========================================="
  echo "🔍 GitHub Search: $INPUT"
  echo "=========================================="
  echo ""

  if [[ "$HAS_GH" == "1" ]]; then
    local data
    data=$(gh search repos "$INPUT" --json fullName,description,stargazersCount,language,updatedAt --limit 10 2>/dev/null || true)
    if [[ -n "$data" && "$data" != "[]" ]]; then
      echo "$data" | jq -r '.[] |
        "📦 \(.fullName // "N/A") (\(.language // "N/A")) — ⭐ \(.stargazersCount // 0)",
        "   \(.description // "" | .[0:120])",
        "   Updated: \(.updatedAt // "N/A" | .[0:10])",
        ""
      ' 2>/dev/null || echo "Parse error"
    else
      echo "No results found"
    fi
  else
    local encoded
    encoded=$(echo "$INPUT" | sed 's/ /+/g')
    local data
    data=$(gh_api "/search/repositories?q=${encoded}&sort=stars&per_page=10")
    if [[ -n "$data" ]]; then
      echo "$data" | jq -r '.items[:10][] |
        "📦 \(.full_name // "N/A") (\(.language // "N/A")) — ⭐ \(.stargazers_count // 0)",
        "   \(.description // "" | .[0:120])",
        "   Updated: \(.updated_at // "N/A" | .[0:10])",
        ""
      ' 2>/dev/null || echo "No results"
    fi
  fi
}

# ========================
# Mode: activity — development activity analysis
# ========================
do_activity() {
  local repo="$INPUT"
  echo "=========================================="
  echo "📈 GitHub Activity: $repo"
  echo "=========================================="
  echo ""

  # Commit activity (weekly participation)
  local activity
  activity=$(gh_api "/repos/$repo/stats/participation")
  if [[ -n "$activity" ]] && echo "$activity" | jq -e '.all' &>/dev/null 2>&1; then
    local total_year recent_4w
    total_year=$(echo "$activity" | jq '[.all[-52:][] ] | add // 0' 2>/dev/null || echo "N/A")
    recent_4w=$(echo "$activity" | jq '[.all[-4:][] ] | add // 0' 2>/dev/null || echo "N/A")
    echo "Commits (52 weeks): $total_year | Last 4 weeks: $recent_4w"

    # Activity assessment
    if [[ "$recent_4w" != "N/A" ]]; then
      if [[ "$recent_4w" -ge 50 ]]; then
        echo "📊 Very active development (50+ commits/4w)"
      elif [[ "$recent_4w" -ge 20 ]]; then
        echo "📊 Active development (20+ commits/4w)"
      elif [[ "$recent_4w" -ge 5 ]]; then
        echo "📊 Moderate development (5+ commits/4w)"
      elif [[ "$recent_4w" -gt 0 ]]; then
        echo "📊 Low activity (< 5 commits/4w)"
      else
        echo "⚠️ No commits in last 4 weeks"
      fi
    fi
  else
    echo "  Commit stats not yet available (GitHub may still be computing)"
  fi

  # Open issues and PRs
  echo ""
  echo "📋 Recent Open Issues/PRs"
  echo "---"
  local issues
  issues=$(gh_api "/repos/$repo/issues?state=open&per_page=5&sort=updated")
  if [[ -n "$issues" ]]; then
    echo "$issues" | jq -r '.[:5][] |
      "[\(if .pull_request then "PR" else "Issue" end) #\(.number // 0)] \(.title // "N/A" | .[0:100])",
      "  @\(.user.login // "N/A") · \(.created_at // "" | .[0:10])",
      ""
    ' 2>/dev/null || echo "  Could not parse issues"
  fi

  # Latest release
  echo "🏷️ Latest Release"
  echo "---"
  local releases
  releases=$(gh_api "/repos/$repo/releases?per_page=1")
  if [[ -n "$releases" ]] && echo "$releases" | jq -e '.[0]' &>/dev/null 2>&1; then
    echo "$releases" | jq -r '.[0] |
      "Tag: \(.tag_name // "N/A") | Name: \(.name // "N/A")",
      "Published: \(.published_at // "N/A" | .[0:10])",
      "\(.body // "" | .[0:200])"
    ' 2>/dev/null || echo "  No releases found"
  else
    echo "  No releases found"
  fi
}

case "$MODE" in
  repo)     do_repo ;;
  search)   do_search ;;
  activity) do_activity ;;
  *)        echo "Unknown mode: $MODE. Use: repo, search, activity"; exit 1 ;;
esac

echo ""
echo "=========================================="
echo "✅ GitHub research complete."
echo "=========================================="
