# API Reference

## Rate Limits

| API | Free Tier Limit | Notes |
|-----|----------------|-------|
| RootData (Skill API) | 200 req/min | Auto-init, no registration needed |
| RootData (Standard API) | Credit-based (varies by plan) | Search is free & unlimited |
| CoinMarketCap | 10,000 credits/mo, ~30 req/min | Free key at pro.coinmarketcap.com |
| DefiLlama | Unlimited (fair use) | No key needed |
| Kaito | No free API | Enterprise only; portal links free |
| Dune Analytics | 2,500 credits/mo | Free key at dune.com/settings/api |
| Brave Search | 2,000 queries/mo | Free key at brave.com/search/api/ |

---

## RootData API

**Two access modes** (scripts auto-detect based on env vars):

| Mode | Env Var | Auth Header | Base Path | Rate Limit |
|------|---------|-------------|-----------|------------|
| **Skill API** (recommended) | `ROOTDATA_SKILL_KEY` | `Authorization: Bearer {key}` | `/open/skill/*` | 200 req/min |
| **Standard API** | `ROOTDATA_API_KEY` | `apikey: {key}` + `language: en` | `/open/*` | Credit-based |

**Auto-init (Skill API)** — no registration needed:
```
POST /open/skill/init
Body: {}
→ Returns: {"data": {"api_key": "..."}}
```
The key is anonymous, low-privilege, public data only. Save as `ROOTDATA_SKILL_KEY`.

**Manual registration (Standard API)**: https://www.rootdata.com/Api

### 1. Search
```
POST /skill/ser_inv  (Skill API)
POST /ser_inv        (Standard API)
Body: {"query": "keyword", "precise_x_search": false}
```
Returns array: `id`, `type` (1=Project, 2=VC, 3=People), `name`, `one_liner`, `introduce`, `rootdataurl`

### 2. Get Project
```
POST /skill/get_item  (Skill API)
POST /get_item        (Standard API)
Body: {"project_id": 12, "include_investors": true}
```
Also supports: `"contract_address": "0x..."` instead of project_id.

**Returns**:
- Basic: `project_name`, `token_symbol`, `one_liner`, `description`, `tags`, `ecosystem`, `establishment_date`, `total_funding`, `social_media`, `investors[]`, `team_members[]`, `similar_project[]`, `contracts[]`, `rootdataurl`, `active`
- PRO: `price`, `market_cap`, `fully_diluted_market_cap`, `support_exchanges[]`, `event[]`, `reports[]`, `heat`, `heat_rank`, `influence`, `influence_rank`, `followers`, `token_launch_time`

**team_members[] fields**: `name`, `position`, `linkedin`, `twitter`, `website`, `discord`, `medium`
**investors[] fields**: `name`, `logo`
**social_media fields**: `website`, `twitter`, `discord`, `medium`, `linkedin`, `telegram`

### 3. Get VC
```
POST /skill/get_org  (Skill API)
POST /get_org        (Standard API)
Body: {"org_id": 219, "include_team": true, "include_investments": true}
```
Returns: `org_name`, `description`, `category[]`, `establishment_date`, `social_media`, `team_members[]` (name, position), `investments[]` (name, logo), `rootdataurl`, `active`

### 4. Get People (Standard API only, Pro)
```
POST /get_people
Body: {"people_id": 12972}
```
Returns: `people_name`, `introduce`, `head_img`, `one_liner`, `X`, `linkedin`

### 5. Get Fundraising Rounds
```
POST /skill/get_fac  (Skill API)
POST /get_fac        (Standard API)
Body: {"page": 1, "page_size": 20, "project_id": 12, "start_time": "2024-01", "end_time": "2025-12", "min_amount": 1000000, "max_amount": 100000000}
```
All filter fields optional. Data available from 2018 onwards.
Returns: `total`, `items[]` with `name`, `amount`, `valuation`, `published_time`, `rounds`, `source_url`, `invests[]` (name, lead_investor, type, rootdataurl)

### 6. Trending Projects (Skill API)
```
POST /skill/hot_index
Body: {"days": 1}
```
`days`: 1 = today, 7 = this week
Returns: `rank`, `project_id`, `project_name`, `token_symbol`, `one_liner`, `tags`, `X`, `rootdataurl`

### 7. Get All IDs by Type (Skill API)
```
POST /skill/id_map
Body: {"type": 1}
```
`type`: 1=Project, 2=Institution, 3=Person
Returns: `id`, `name`

### 8. Check Credits (Standard API, free)
```
POST /quotacredits
Body: {}
```
Returns: `credits`, `total_credits`, `level`, `start`, `end`

---

## CoinMarketCap API

**Base URL**: `https://pro-api.coinmarketcap.com`
**Auth**: Header `X-CMC_PRO_API_KEY: {key}`
**Free key**: https://pro.coinmarketcap.com (10,000 credits/month)

### Map
```
GET /v1/cryptocurrency/map?symbol={SYMBOL}
GET /v1/cryptocurrency/map?slug={slug}
```

### Info (project metadata)
```
GET /v2/cryptocurrency/info?id={cmc_id}
```
Returns: `description`, `logo`, `category`, `tags`, `urls` (website, explorer, source_code, twitter, reddit, chat), `platform`, `date_added`, `infinite_supply`

### Quotes (real-time market data)
```
GET /v2/cryptocurrency/quotes/latest?id={cmc_id}&convert=USD
```
Returns: `cmc_rank`, `price`, `volume_24h`, `market_cap`, `fully_diluted_market_cap`, `percent_change_1h/24h/7d/30d/90d`, `circulating_supply`, `total_supply`, `max_supply`, `num_market_pairs`

### Listings (top tokens)
```
GET /v1/cryptocurrency/listings/latest?limit=20&convert=USD
```

### Global Metrics
```
GET /v1/global-metrics/quotes/latest?convert=USD
```

### Fear & Greed
```
GET /v3/fear-and-greed/latest
```

### Categories
```
GET /v1/cryptocurrency/categories?limit=20
```

### Credit Costs
| Endpoint | Credits |
|----------|---------|
| /map | 1 per 100 |
| /info | 1 per coin |
| /quotes/latest | 1 per coin |
| /listings/latest | 1 per 100 |
| /global-metrics | 1 |
| /categories | 1 per 100 |
| /fear-and-greed | 1 |

---

## DefiLlama API (no key required)

**Base URL**: `https://api.llama.fi`

### Protocols
```
GET /protocols
```
Returns all protocols sorted by TVL.

### Protocol Detail
```
GET /protocol/{slug}
```
Returns: TVL history, chain breakdown, token info, description, social links, raises.

### Chains
```
GET /v2/chains
```

### Fees (daily)
```
GET /summary/fees/{slug}?dataType=dailyFees
```
Returns: `name`, `total24h`, `total48hto24h`, `totalDataChart` (time series), `totalDataChartBreakdown` (by chain).

### Revenue (daily)
```
GET /summary/fees/{slug}?dataType=dailyRevenue
```
Returns: Same structure as fees. Revenue = what the protocol retains.

### Holders Revenue
```
GET /summary/fees/{slug}?dataType=dailyHoldersRevenue
```
Returns: Revenue distributed to token holders.

### Fees Overview (all protocols)
```
GET /overview/fees
```
Returns: Aggregated fees data for all tracked protocols.

### DEX Volume
```
GET /summary/dexs/{slug}
```
Returns: `total24h`, `change_1d`, daily volume time series.

### DEX Volume Overview
```
GET /overview/dexs
```

### Stablecoins
```
GET /stablecoins
```

### Raises (Fundraising Rounds)
```
GET /raises
```
Returns all fundraising raises. Each entry includes: `name`, `amount`, `round` (Seed/Series A/etc.), `date` (unix timestamp), `chains[]`, `category`, `leadInvestors[]`, `otherInvestors[]`, `source`, `valuation`.
Free, no key needed. Returns full historical dataset — filter by date client-side.

### Yields
```
GET /pools
```
Returns yield pools across all protocols.

### Fees & Revenue
```
GET /overview/fees
```

---

## Kaito (no free public API)

Kaito provides mindshare, sentiment, and narrative analytics for crypto. **No free API** — enterprise only.

### Available via public URLs (no auth):
- Portal search: `https://portal.kaito.ai/search?q={token}`
- Token page: `https://portal.kaito.ai/token/{SYMBOL}`
- Mindshare arena: `https://www.kaito.ai/portal`

### Data available on Kaito Pro:
- Mindshare % (share of crypto attention)
- Sentiment score (bullish/bearish/neutral)
- Narrative tracking
- Smart followers analysis
- Historical mindshare trends
- Credibility scores

---

## Dune Analytics (optional key)

**Base URL**: `https://api.dune.com/api/v1`
**Auth**: Header `X-DUNE-API-KEY: {key}`
**Free key**: https://dune.com/settings/api (2,500 credits/month)

### Execute Query
```
POST /query/{queryId}/execute
```
Body: `{"query_parameters": {}, "performance": "medium"}`

### Get Execution Status
```
GET /execution/{executionId}/status
```

### Get Query Results (latest cached)
```
GET /query/{queryId}/results
```
No re-execution; returns last cached result. Cheapest option.

### List Queries
```
GET /query?limit=10&name={search}
```

### Dashboard Search (no key needed)
```
https://dune.com/browse/dashboards?q={project_name}
```

### Credit Costs
| Action | Credits |
|--------|---------|
| Execute query (medium) | Variable, based on compute |
| Get cached results | 10 per call |
| List queries | Free |

## Brave Search API (Crunchbase fallback)

**Base URL**: `https://api.search.brave.com/res/v1/web/search`
**Auth**: Header `X-Subscription-Token: {key}`
**Free key**: https://brave.com/search/api/ (2,000 queries/month)

Used as fallback when `CRUNCHBASE_API_KEY` is not set. Searches `site:crunchbase.com` for funding data.

### Web Search
```
GET /res/v1/web/search?q={query}&count={count}&text_decorations=false&search_lang=en
```
Returns: `web.results[]` with `title`, `url`, `description`, `extra_snippets[]`

### Typical Queries
| Goal | Query Pattern |
|------|---------------|
| Org lookup | `site:crunchbase.com/organization/{name}` |
| Funding rounds | `site:crunchbase.com/funding_round {keyword} {timeframe}` |
| Category search | `{category} startup funding round site:crunchbase.com OR site:techcrunch.com` |
| Top raises | `largest funding round raised {year} site:crunchbase.com` |

### Limitations vs Crunchbase API
- Returns search snippets, not structured JSON
- Cannot filter by date range, amount, or category precisely
- Best for: org lookup, broad funding news, keyword searches
- Not suitable for: precise daily round tracking, aggregated statistics

---

## Crunchbase API (requires API key)

**Base URL**: `https://api.crunchbase.com/api/v4`
**Auth**: Header `X-cb-user-key: {key}` or URL param `?user_key={key}`
**Rate limit**: 200 calls/min
**Docs**: https://data.crunchbase.com/docs/using-the-api

### Autocomplete (find org permalink)
```
GET /autocompletes?query={name}&collection_ids=organizations&limit=10
```
Returns: `entities[].identifier.permalink`, `.value`, `.short_description`
Works on Basic plan.

### Entity Lookup: Organization
```
GET /entities/organizations/{permalink}?card_ids=raised_funding_rounds,founders&field_ids=short_description,categories,founded_on,funding_total,last_funding_type,num_funding_rounds,num_employees_enum,website,linkedin,revenue_range
```
Returns: org properties + cards (funding rounds, founders).
Works on Basic plan (limited fields).

### Search: Funding Rounds (Full API only)
```
POST /searches/funding_rounds
```
Body:
```json
{
  "field_ids": ["identifier","announced_on","funded_organization_identifier","money_raised","investment_type","lead_investor_identifiers","investor_identifiers","pre_money_valuation","num_investors","funded_organization_categories"],
  "order": [{"field_id":"announced_on","sort":"desc"}],
  "query": [
    {"type":"predicate","field_id":"announced_on","operator_id":"gte","values":["2025-01-01"]},
    {"type":"predicate","field_id":"money_raised","operator_id":"gte","values":[{"value":10000000,"currency":"usd"}]}
  ],
  "limit": 25
}
```
Filter by category UUID: add `{"type":"predicate","field_id":"funded_organization_categories","operator_id":"includes","values":["UUID"]}`

### Search: Organizations (Full API only)
```
POST /searches/organizations
```
Similar to funding_rounds search but for company data.

### Common Category UUIDs
| Category | UUID |
|----------|------|
| AI | c4d8caf3-5fe7-359b-1638-55db9c8c0612 |
| ML | 5ea0cdb7-d7df-0e74-34a5-5e8e1363884b |
| Biotech | 58842728-36d6-a921-4e61-a5e0f56cfe46 |
| Fintech | 267e4616-e1cb-3ad1-cbb4-2e813d88df41 |
| Healthcare | 80f3b2f8-74ff-7eb7-5e01-b0ad9abc7003 |
| SaaS | 5c4e69df-b90d-2e0e-b4d3-90c6448dcb47 |
| Blockchain | 42de2a85-cc37-4fb6-9e97-d3a8fd1ed0e4 |
| Cybersecurity | 6cb685e1-7930-d4e7-207d-2d0edb924ac6 |
| CleanTech | 06ef7097-116e-7084-da58-98e734e3c4ee |
| Robotics | 27de8b02-fbaa-ec3d-a034-5e6e63258990 |
| Semiconductor | 7ed4a37c-10fc-f22d-fe56-7f1dd0c0deb0 |
| Gaming | d042e4a5-ed6f-82f6-e7a5-7ef8d083e4b3 |

### API Plans
| Plan | Endpoints | Notes |
|------|-----------|-------|
| Basic (with Pro account) | Autocomplete, Entity Lookup (limited fields) | Good for individual company lookup |
| Full API (Enterprise) | All searches incl. funding_rounds, full fields | Required for daily fundraising scanning |
