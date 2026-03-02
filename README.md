# crypto-research v2.3.0

Claude Code skill for crypto due diligence — project overview, team, funding, investors, market data, TVL, mindshare, on-chain dashboards, and cross-sector fundraising. Read-only, no trading.

## Data Sources

| Source | Purpose | Auth |
|--------|---------|------|
| [RootData](https://www.rootdata.com/Api) | Project info, team, investors, funding rounds | API key (free tier) |
| [CoinMarketCap](https://pro.coinmarketcap.com) | Price, volume, supply, rankings, Fear & Greed | API key (free, 10K credits/mo) |
| [DefiLlama](https://defillama.com) | TVL, fees, revenue, DEX volume, raises | No key needed |
| [Kaito](https://www.kaito.ai) | Mindshare, sentiment, narrative tracking | No free API (portal links) |
| [Dune Analytics](https://dune.com) | On-chain dashboards, custom queries | Optional (free 2.5K credits/mo) |
| [Crunchbase](https://www.crunchbase.com) | Cross-sector fundraising (AI, biotech, fintech, etc.) | API key (Pro/Enterprise) |
| [Brave Search](https://brave.com/search/api/) | Fallback for Crunchbase via search snippets | API key (free, 2K queries/mo) |

## Setup

```bash
# Required
export ROOTDATA_API_KEY="your_key_here"
export CMC_PRO_API_KEY="your_key_here"

# Optional
export DUNE_API_KEY="your_key_here"
export CRUNCHBASE_API_KEY="your_key_here"
export BRAVE_API_KEY="your_key_here"      # fallback for Crunchbase
```

Degrades gracefully — DefiLlama (TVL, fees, raises), Kaito portal links, and Dune search URLs always work with no keys.

**Crunchbase fallback:** `CRUNCHBASE_API_KEY` (best) > `BRAVE_API_KEY` (snippets) > exit with instructions.

## Scripts

| Script | Description | Example |
|--------|-------------|---------|
| `rootdata-research.sh` | Project + team + investors + funding | `bash scripts/rootdata-research.sh Ethereum` |
| `quick-research.sh` | CMC market data + risk flags | `bash scripts/quick-research.sh ETH` |
| `cmc-research.sh` | CMC deep dive (info/quote/global/fear) | `bash scripts/cmc-research.sh ETH quote` |
| `defillama-research.sh` | TVL, fees, revenue, DEX volume | `bash scripts/defillama-research.sh aave` |
| `kaito-mindshare.sh` | Mindshare, sentiment, narrative links | `bash scripts/kaito-mindshare.sh ETH` |
| `dune-search.sh` | Related Dune dashboards | `bash scripts/dune-search.sh uniswap` |
| `fundraising-daily.sh` | Crypto fundraising (RootData + DefiLlama) | `bash scripts/fundraising-daily.sh today` |
| `crunchbase-fundraising.sh` | Cross-sector fundraising (CB or Brave) | `bash scripts/crunchbase-fundraising.sh org openai` |
| `trending.sh` | Market overview + top tokens + categories | `bash scripts/trending.sh` |
| `compare.sh` | Side-by-side token comparison | `bash scripts/compare.sh ETH SOL` |

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
| `dune X` | Related Dune dashboards |
| `compare X vs Y` | Side-by-side token comparison |
| `trending` | Market overview + Fear & Greed |
| `fear greed` | Fear & Greed index + global metrics |
| `cmc X` | CMC project metadata |
| `fundraising` | Today's crypto fundraising rounds |
| `fundraising week` | This week's rounds |
| `fundraising search AI` | Search by keyword |
| `crunchbase today` | Today's fundraising (all sectors) |
| `crunchbase org <name>` | Org lookup with funding history |
| `crunchbase category AI` | Sector-filtered fundraising |
| `crunchbase top` | Largest raises (last 30 days) |

Chinese commands supported: `调研`, `团队`, `融资`, `行情`, `对比`, `热门`, `CB融资`, `注意力`, `收入`, `恐贪指数`.

## Requirements

- `curl`
- `jq`
