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

### Rewards Network (RN) vs. Non-RN Offer Performance
**Files**:
- [`queries/rn_vs_nonrn_tap_in_rate.sql`](queries/rn_vs_nonrn_tap_in_rate.sql)
- [`queries/rn_vs_nonrn_impressed_redemption_rate.sql`](queries/rn_vs_nonrn_impressed_redemption_rate.sql)
- [`queries/rn_vs_nonrn_offer_mechanics.sql`](queries/rn_vs_nonrn_offer_mechanics.sql)
- [`queries/rn_vs_nonrn_catalog_exploration_metrics.sql`](queries/rn_vs_nonrn_catalog_exploration_metrics.sql)
- [`queries/rn_vs_nonrn_revenue_split.sql`](queries/rn_vs_nonrn_revenue_split.sql)

Compares offers where `OFFERS_ATTRIBUTES.PAYER = 'Rewards Network'` (RN) against everything else, across tap-in rate, redemption rate, offer mechanics, and catalog-level exploration metrics. `PAYER = 'Rewards Network'` is 100% Restaurants category, and is ~99% of currently-live Restaurant offers (16,479 of 16,601) — so this is effectively "Restaurants (via RN) vs. everything else."

**Tap-in rate & impressed redemption rate** (trailing 30 days, `WS_OFFER_BRAND_IMPRESSIONS_STAGE` joined to `OFFERS_ATTRIBUTES.PAYER`; redemptions from `OFFER_USAGES`):

| Payer group | Impressions | Taps | Tap-in rate | Redemptions | Impressed redemption rate | # offers |
|---|---|---|---|---|---|---|
| Rewards Network | 63.97M | 637K | 0.996% | 706,708 | 1.1025% | 18,642 / 18,548 |
| Not Rewards Network | 2.26B | 25.09M | 1.108% | 25.38M | 1.1181% | 5,348 / 3,471 |

RN taps in ~10% relatively lower than non-RN, but redemption rate is nearly identical (~1.4% relative gap, effectively noise). So the RN gap is a discovery/tap-in problem, not a value/conversion problem.

**Caveat on offer counts**: the `n_offers` figures above (18,642 / 5,348) count any offer with impression, tap, or detail-view activity in the trailing 30 days — not offers live *right now*. That trailing-window count will always run ahead of a live-now snapshot (16,479 RN / 16,601 total Restaurants) because offers rotate; some counted here have since expired. Don't directly compare these counts to the AU31 eligibility section above without accounting for that.

**Offer mechanics** (currently-live offers, `OFFERS_ATTRIBUTES`):

| Payer group | % store-targeted | Median $ required | Median points earned | Avg description length |
|---|---|---|---|---|
| Rewards Network | 0.0% | 1 (looks like an "any purchase" flag) | 500 | 9 chars |
| Not Rewards Network | 55.7% | 1,200 (unit ambiguous, likely cents) | 1,800 | 12 chars |

RN offers have a near-zero purchase threshold, no named-store targeting (broader eligibility, not narrower), a lower point payout, and much shorter on-card description text than non-RN offers. Working hypothesis: the low tap-in rate is driven by weak on-card differentiation (generic/unfamiliar branding, no food/lifestyle imagery, minimal copy) rather than by purchase conditions or geo-targeting friction — RN isn't the more geo-restricted group, so that's not the driver. Imagery specifically is a hypothesis, not confirmed: this table has no creative/asset data to test it directly.

**Catalog-level exploration metrics** (trailing 30 days): whether RN's offer-count share drags down an "exploration" metric depends entirely on how it's weighted.

| Payer group | # offers w/ impressions | % offers ever tapped | Unweighted avg per-offer tap rate |
|---|---|---|---|
| Rewards Network | 18,548 | 91.8% | 0.843% |
| Not Rewards Network | 3,473 | 73.6% | 2.114% |

- **Impression-weighted** (total taps ÷ total impressions, the tap-in rate table above): RN is only ~2.7% of total impression volume, so its lower rate barely moves the blended number (~1.104% actual vs. ~1.107% counterfactual if RN matched non-RN — a ~0.3% relative drag).
- **Offer-weighted / catalog-level** (simple average across offers, unweighted by impression volume): RN is ~84% of all offers with impressions, so a catalog-level average tap rate (~1.04%) sits much closer to RN's own rate (0.843%) than to non-RN's (2.114%), purely because RN outnumbers everything else 5-to-1. As RN's share of the catalog grows, this kind of metric mechanically drifts toward RN's lower rate regardless of whether non-RN behavior changes at all.
- Note the "% offers ever tapped" (catalog coverage) metric actually favors RN (91.8% vs. 73.6%) — RN's broad eligibility means almost every RN offer gets touched at least once, even though each gets a much lower share of its impressions converted. Don't treat every exploration-style metric as moving in the same direction; check which one is actually being tracked before drawing conclusions.

**Revenue split** (calendar month August 2026, `OFFERS_ATTRIBUTES.CATEGORY = 'RESTAURANTS'` joined to `FINANCE.REVENUE_AND_EXPENSE_MODEL.REVENUE`):

| Payer group | Total revenue | # offers w/ revenue | Avg revenue per offer |
|---|---|---|---|
| Rewards Network | $1,473,355 | 16,634 | $88.58 |
| Not Rewards Network | $703,894 | 93 | $7,569.83 |

RN is ~99.4% of restaurant offers by count but only ~67.7% of restaurant category revenue. The 93 non-RN offers (brand-funded deals — Taco Bell, KFC, Chipotle, Costco, Pepsico, DoorDash, Albertsons, Baskin-Robbins, etc.) are 0.6% of offer count but 32.3% of revenue, averaging ~85x more revenue per offer than a typical RN offer.

**Caveat**: cross-checking against a different category source (`fetch_services_prod.lighthouse.offer_level_metrics` instead of `OFFERS_ATTRIBUTES`, same August window) gives only 35 non-RN offers and a 75.3% / 24.7% split instead of 93 offers and 67.7% / 32.3%. The two source tables disagree on which offers count as non-RN Restaurant offers. The direction (RN dominates count, non-RN dominates revenue-per-offer by roughly two orders of magnitude) holds either way; the decimal split does not.

**Caveat**: `FETCH_SERVICES_PROD.FINANCE.REVENUE_AND_EXPENSE` (no `_MODEL` suffix) is currently a broken view — querying it throws a column-count mismatch error. Use `REVENUE_AND_EXPENSE_MODEL`, which works.

**Caveat**: the RN revenue figure here ($1.473M) differs from `ANALYTICS_PROD.REWARDS_NETWORK.RN_DAILY_REVENUE` for the same month ($1.513M) by about 2.6%. Two different revenue systems, not reconciled — confirm with whoever owns RN finance reporting before citing either number externally.

### AU31 Dine Cuisine Shelf Eligibility (1-2 offer cuisines)
**File**: [`queries/au31_cuisine_low_offer_distribution.sql`](queries/au31_cuisine_low_offer_distribution.sql)

For the Dine pill cuisine shelves (shown only with 3+ eligible offers), how many cuisines does each AU31 user have where they are eligible for only 1-2 offers?

**Data Sources**:
- `ANALYTICS_PROD.FETCHDW.P_USER` for the AU31 cohort
- `FETCH_SERVICES_PROD.DINING_METADATA_SERVICE.DINING_METADATA_UPDATED_METADATA_CURRENT_STATE_FSD` for primary cuisine per location
- `ANALYTICS_PROD.REWARDS_NETWORK.RN_DAILY_USER_OFFER` for live user-offer-location eligibility

**Snapshot as of 2026-11-06**: AU31 population = 14,133,513. 32 primary cuisines.

| # of cuisines with only 1-2 offers | % of AU31 |
|---|---|
| 0 | 5.1% |
| 1 | 5.3% |
| 2 | 6.6% |
| 3 | 6.7% |
| 4 | 7.1% |
| 5 | 7.0% |
| 6-7 | 14.8% |
| 8-10 | 24.2% |
| 11-15 | 21.6% |
| 16+ | 1.7% |

- 94.9% of AU31 have 1+ cuisine with only 1-2 offers (avg 7.1 per user).
- Avg 13.9 cuisines per user do get a shelf. 81.4% have 3+ shelves.
- 4.9% of cuisine-tagged user-offer pairs sit in a 1-2 offer cuisine.
- 3.7% of AU31 have no cuisine-tagged offer at all.

**Caveats**: Per-cuisine 3+ counts roughly match the AU31 Reach sheet, but Coffee is off (38% vs 58%) and the cause is not yet found. Excludes daypart shelves.
