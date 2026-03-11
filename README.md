# crypto-research v2.7.0

Claude Code skill for crypto due diligence — project overview, team, funding, investors, market data, TVL, mindshare, on-chain dashboards, cross-sector fundraising, Twitter/X social sentiment, web reading, semantic search, Reddit discussions, YouTube research, and GitHub development activity. Read-only, no trading.

## Data Sources

| Source | Purpose | Auth |
|--------|---------|------|
| [RootData](https://www.rootdata.com/Api) | Project info, team, investors, funding, trending | Auto-init (no registration) or API key |
| [CoinMarketCap](https://pro.coinmarketcap.com) | Price, volume, supply, rankings, Fear & Greed | API key (free, 10K credits/mo) |
| [DefiLlama](https://defillama.com) | TVL, fees, revenue, DEX volume, raises | No key needed |
| [Kaito](https://www.kaito.ai) | Mindshare, sentiment, narrative tracking | No free API (portal links) |
| [Dune Analytics](https://dune.com) | On-chain dashboards, custom queries | Optional (free 2.5K credits/mo) |
| [Crunchbase](https://www.crunchbase.com) | Cross-sector fundraising (AI, biotech, fintech, etc.) | API key (Pro/Enterprise) |
| [Brave Search](https://brave.com/search/api/) | Fallback for Crunchbase via search snippets | API key (free, 2K queries/mo) |
| Twitter/X ([xreach](https://github.com/user/xreach)) | Real-time social sentiment, KOL tracking | xreach CLI (Agent-Reach) |
| [Jina Reader](https://jina.ai/reader/) | Read web pages (docs, blogs, whitepapers) | No key needed |
| [Exa Search](https://exa.ai) | Semantic web search for research & analysis | mcporter CLI (Agent-Reach) |
| [Reddit](https://www.reddit.com) | Community discussions, sentiment | No key needed |
| YouTube ([yt-dlp](https://github.com/yt-dlp/yt-dlp)) | Video research: AMAs, interviews, talks | yt-dlp CLI |
| [GitHub](https://github.com) | Development activity, repo health | gh CLI (optional) |
| [CoinGecko](https://www.coingecko.com) | Community data (TG, Reddit) + developer stats | Optional API key (free 30 req/min) |
| [LunarCrush](https://lunarcrush.com) | Galaxy Score, AltRank, social sentiment | API key ($24/mo or free Discover) |
| Telegram Bot API | Accurate channel/group member counts | Bot token (free via @BotFather) |

## Setup

```bash
# Required
export CMC_PRO_API_KEY="your_key_here"

# RootData (pick one — Skill API recommended, auto-inits if neither set)
export ROOTDATA_SKILL_KEY="your_key_here"  # auto-init via /open/skill/init, 200 req/min
# OR
export ROOTDATA_API_KEY="your_key_here"    # manual registration, credit-based

# Optional
export DUNE_API_KEY="your_key_here"
export CRUNCHBASE_API_KEY="your_key_here"
export BRAVE_API_KEY="your_key_here"      # fallback for Crunchbase
export COINGECKO_API_KEY="your_key_here"  # optional (free Demo: 30 req/min)
export LUNARCRUSH_API_KEY="your_key_here" # optional ($24/mo or free Discover)
export TELEGRAM_BOT_TOKEN="your_token"    # optional (free via @BotFather)
```

### Optional: Agent-Reach Tools

Additional research capabilities via [Agent-Reach](https://github.com/Panniantong/Agent-Reach):

```bash
# Install Agent-Reach (all-in-one)
pip install https://github.com/Panniantong/agent-reach/archive/main.zip
agent-reach install --env=auto

# Or install tools individually
npm install -g xreach-cli          # Twitter/X
npm install -g mcporter            # Exa semantic search
pip install yt-dlp                 # YouTube
brew install gh && gh auth login   # GitHub CLI

# Check status
agent-reach doctor
```

Degrades gracefully — DefiLlama (TVL, fees, raises), Kaito portal links, Dune search URLs, Jina Reader (web), Reddit, and CoinGecko (free tier) always work with no keys or tools.

**Crunchbase fallback:** `CRUNCHBASE_API_KEY` (best) > `BRAVE_API_KEY` (snippets) > exit with instructions.

## Scripts

| Script | Description | Example |
|--------|-------------|---------|
| `rootdata-research.sh` | Project + team + investors + funding + trending | `bash scripts/rootdata-research.sh Ethereum` |
| `quick-research.sh` | CMC market data + risk flags | `bash scripts/quick-research.sh ETH` |
| `cmc-research.sh` | CMC deep dive (info/quote/global/fear) | `bash scripts/cmc-research.sh ETH quote` |
| `defillama-research.sh` | TVL, fees, revenue, DEX volume | `bash scripts/defillama-research.sh aave` |
| `kaito-mindshare.sh` | Mindshare, sentiment, narrative links | `bash scripts/kaito-mindshare.sh ETH` |
| `community-traction.sh` | Community metrics (CoinGecko + TG + Discord + LunarCrush) | `bash scripts/community-traction.sh Ethereum` |
| `coingecko-community.sh` | CoinGecko community + developer data | `bash scripts/coingecko-community.sh ethereum` |
| `lunarcrush.sh` | LunarCrush social sentiment & Galaxy Score | `bash scripts/lunarcrush.sh ETH` |
| `dune-search.sh` | Related Dune dashboards | `bash scripts/dune-search.sh uniswap` |
| `fundraising-daily.sh` | Crypto fundraising (RootData + DefiLlama) | `bash scripts/fundraising-daily.sh today` |
| `crunchbase-fundraising.sh` | Cross-sector fundraising (CB or Brave) | `bash scripts/crunchbase-fundraising.sh org openai` |
| `trending.sh` | Market overview + top tokens + categories | `bash scripts/trending.sh` |
| `compare.sh` | Side-by-side token comparison | `bash scripts/compare.sh ETH SOL` |
| `social-sentiment.sh` | Twitter/X social intelligence | `bash scripts/social-sentiment.sh Ethereum` |
| `web-reader.sh` | Read web page as markdown | `bash scripts/web-reader.sh https://example.com` |
| `exa-search.sh` | Semantic web search via Exa | `bash scripts/exa-search.sh "query"` |
| `reddit-sentiment.sh` | Reddit crypto discussions | `bash scripts/reddit-sentiment.sh Ethereum` |
| `youtube-research.sh` | YouTube video search & metadata | `bash scripts/youtube-research.sh "query"` |
| `github-activity.sh` | GitHub repo stats & dev activity | `bash scripts/github-activity.sh ethereum/go-ethereum` |

## Commands

| Command | Action |
|---------|--------|
| `research X` | Full report: team + funding + market + TVL + mindshare |
| `team X` | Team members and background |
| `funding X` / `investors X` | Investors and funding rounds |
| `price X` | Quick market data |
| `tvl X` | DefiLlama TVL + chain breakdown |
| `fees X` / `revenue X` | DefiLlama fees & revenue |
| `mindshare X` / `kaito X` | Kaito mindshare links + analysis |
| `community X` / `traction X` | Community metrics (CoinGecko + TG + Discord + LunarCrush) |
| `coingecko X` | CoinGecko community + developer data |
| `sentiment X` / `lunarcrush X` | LunarCrush social sentiment & Galaxy Score |
| `dune X` | Related Dune dashboards |
| `compare X vs Y` | Side-by-side token comparison |
| `trending` | Market overview + Fear & Greed + RootData trending |
| `rootdata trending` | RootData trending projects (today/week) |
| `fear greed` | Fear & Greed index + global metrics |
| `cmc X` | CMC project metadata |
| `fundraising` | Today's crypto fundraising rounds |
| `fundraising week` | This week's rounds |
| `fundraising search AI` | Search by keyword |
| `crunchbase today` | Today's fundraising (all sectors) |
| `crunchbase org <name>` | Org lookup with funding history |
| `crunchbase category AI` | Sector-filtered fundraising |
| `crunchbase top` | Largest raises (last 30 days) |
| `twitter X` / `tweets X` | Twitter/X social sentiment search |
| `tweets @handle` | Recent tweets from account |
| `read URL` | Read web page via Jina Reader |
| `search X` | Semantic web search via Exa |
| `reddit X` | Reddit discussions (r/cryptocurrency) |
| `youtube X` | YouTube video search |
| `github owner/repo` | GitHub repo overview |
| `github search X` | Search GitHub repositories |
| `github activity owner/repo` | Dev activity analysis |

Chinese commands supported: `调研`, `团队`, `融资`, `行情`, `对比`, `热门`, `CB融资`, `注意力`, `社区`, `收入`, `恐贪指数`, `推特`, `阅读`, `搜索`, `视频`, `代码`, `情绪`.

## Requirements

**Required:** `curl`, `jq`

**Optional (Agent-Reach):** `xreach` (Twitter/X), `mcporter` (Exa search), `yt-dlp` (YouTube), `gh` (GitHub)
