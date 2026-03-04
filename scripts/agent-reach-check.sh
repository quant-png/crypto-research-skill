#!/bin/bash
# agent-reach-check.sh — Check Agent-Reach tool availability
# Sourced by other scripts, not run directly.
# Exports: HAS_XREACH, HAS_MCPORTER, HAS_YTDLP, HAS_GH, HAS_JINA
# Usage: source scripts/agent-reach-check.sh

_check_tool() {
  command -v "$1" &>/dev/null && echo "1" || echo "0"
}

HAS_XREACH=$(_check_tool xreach)
HAS_MCPORTER=$(_check_tool mcporter)
HAS_YTDLP=$(_check_tool yt-dlp)
HAS_GH=$(_check_tool gh)
HAS_JINA=1  # Jina Reader requires only curl (always available)
