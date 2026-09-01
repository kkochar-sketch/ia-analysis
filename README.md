# IA Analysis - Core Surfaces

Information architecture analysis queries and reports for Core Surfaces product work.

## Queries

### Leaderboard Tap by Retention Cohort
**File**: [`queries/leaderboard_tap_by_retention_cohort.sql`](queries/leaderboard_tap_by_retention_cohort.sql)

Analyzes leaderboard tab access (under Play tab) by user retention cohort over the last 3 months.

**Data Source**: `FETCH_SERVICES_PROD.DISCOV.NAV_TAP_TRACKING`
- Event: `leaderboards_tab_viewed` → `'Play | Leaderboard'`

**Retention Cohorts** (mutually exclusive):
- Active (0-7 days ago)
- Active (8-30 days ago)
- At Risk (31-90 days ago)
- Churned (90+ days ago)

**Metrics**:
- Total users per cohort
- Users who accessed leaderboard
- % accessing leaderboard
- Avg days active on leaderboard
- Avg days since last leaderboard access

### Scan Tap Entry Point
**File**: [`queries/scan_tap_entry_point.sql`](queries/scan_tap_entry_point.sql)

Breaks down `Scan Started` taps by originating surface over the last 90 days.

**Data Source**: `FETCH_SERVICES_PROD.WEBSOCKET_SERVICE.WS_SCAN_STAGE`
- Event: `Scan Started` → `ENTRY_POINT`

**Caveat**: `ENTRY_POINT` values are `Discover`, `Other`, `Me`, `DeepLink`, `Rewards`. There is no explicit `Home` value — untracked surfaces (possibly including Home) are folded into `Other`, and the raw event payload has no secondary field to disambiguate them. So this does not currently give a clean Home-vs-other-tabs split; it distinguishes Discover/Me/Rewards/DeepLink from everything else.

### AU31 Restaurant Offer Eligibility Distribution
**File**: [`queries/au31_restaurant_offer_eligibility.sql`](queries/au31_restaurant_offer_eligibility.sql)

Of AU31 users (active in the trailing 31 days), how many live Restaurant-category offers is each one eligible for?

**Data Sources**:
- `ANALYTICS_PROD.FETCHDW.P_USER` — AU31 cohort: `deleted_ts IS NULL AND last_rewards_login >= DATEADD(day, -31, CURRENT_DATE())`
- `FETCH_SERVICES_PROD.OFFERS.OFFERS_ATTRIBUTES` — live Restaurant offers: `OFFER_STATUS = 'PUBLISHED'`, `CATEGORY = 'RESTAURANTS'`, current timestamp between `START_DATE_UTC` and `LATEST_END_DATE_UTC`
- `FETCH_SERVICES_PROD.OFFERS.OFFERS_AUDIENCE_CURRENT_SNAPSHOT` — per-user eligibility: `IN_AUDIENCE = TRUE AND NOT INELIGIBLE`

**Snapshot as of 2026-09-01**: AU31 population = 14,035,245. Live Restaurant offers = 16,601.

| # of restaurant offers eligible for | # of AU31 users | % of AU31 |
|---|---|---|
| 0 | 10,518 | 0.08% |
| 1–9 | 560,117 | 3.99% |
| 10–49 | 4,182,217 | 29.80% |
| 50–99 | 2,345,268 | 16.71% |
| 100–249 | 4,327,307 | 30.83% |
| 250–499 | 1,837,506 | 13.09% |
| 500–999 | 708,456 | 5.05% |
| 1,000+ | 63,856 | 0.46% |

Average ~154 offers/user. Max observed: 4,791 (≈29% of the live catalog) — nobody is eligible for the majority of live Restaurant offers, and almost nobody (0.08%) is eligible for none. Eligibility is wide but shallow: most users qualify for *some* restaurant offers, but only a small slice of the total catalog, consistent with offers being chain/location-specific rather than broadly targeted.

**Caveat**: ~94 of the 16,601 live Restaurant offers have no rows at all in `OFFERS_AUDIENCE_CURRENT_SNAPSHOT` (likely brand-new or open-audience offers not yet processed into the snapshot). Those are excluded from everyone's eligible count — a small, uniform undercount, not something that changes the shape of the distribution. Also note this table is ~69B rows / ~2.3TB, so the query takes 5-8 minutes on a standard warehouse.
