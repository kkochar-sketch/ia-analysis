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
