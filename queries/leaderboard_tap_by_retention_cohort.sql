-- Leaderboard Tab Access by User Retention Cohort
-- Last 3 Months Analysis
-- Using last_rewards_login for accurate retention cohorts

WITH user_retention_cohorts AS (
  SELECT
    id AS user_id,
    CASE
      WHEN last_rewards_login >= DATEADD(day, -7, CURRENT_DATE()) THEN 'Active (0-7 days ago)'
      WHEN last_rewards_login >= DATEADD(day, -30, CURRENT_DATE()) THEN 'Active (8-30 days ago)'
      WHEN last_rewards_login >= DATEADD(day, -90, CURRENT_DATE()) THEN 'At Risk (31-90 days ago)'
      WHEN last_rewards_login < DATEADD(day, -90, CURRENT_DATE()) OR last_rewards_login IS NULL THEN 'Churned (90+ days ago)'
      ELSE 'Unknown'
    END AS retention_cohort,
    last_rewards_login
  FROM ANALYTICS_PROD.FETCHDW.P_USER
  WHERE deleted_ts IS NULL
),

date_spine AS (
  SELECT DATEADD(day, seq4(), DATEADD(month, -3, CURRENT_DATE())) AS report_date
  FROM TABLE(GENERATOR(ROWCOUNT => 92))
  WHERE report_date < CURRENT_DATE()
),

leaderboard_windows AS (
  SELECT
    user_id,
    platform,
    start_dt,
    end_dt
  FROM FETCH_SERVICES_PROD.DISCOV.NAV_TAP_TRACKING
  WHERE REGEXP_REPLACE(description, '\\d+$', '') = 'Play | Leaderboard'
    AND REGEXP_SUBSTR(description, '\\d+$') = '1'
    AND end_dt >= DATEADD(month, -3, CURRENT_DATE())
),

leaderboard_daily AS (
  SELECT DISTINCT
    d.report_date,
    lw.user_id
  FROM leaderboard_windows lw
  JOIN date_spine d ON d.report_date BETWEEN lw.start_dt AND lw.end_dt
),

leaderboard_metrics AS (
  SELECT
    user_id,
    COUNT(DISTINCT report_date) AS days_with_leaderboard_access,
    MAX(report_date) AS last_leaderboard_date,
    MIN(report_date) AS first_leaderboard_date
  FROM leaderboard_daily
  GROUP BY user_id
)

-- Final breakdown by retention cohort
SELECT
  u.retention_cohort,
  COUNT(DISTINCT u.user_id) AS total_users,
  COUNT(DISTINCT l.user_id) AS users_accessed_leaderboard,
  ROUND(100.0 * COUNT(DISTINCT l.user_id) / NULLIF(COUNT(DISTINCT u.user_id), 0), 2) AS pct_accessed_leaderboard,
  -- For users who accessed leaderboard
  ROUND(AVG(CASE WHEN l.user_id IS NOT NULL THEN l.days_with_leaderboard_access END), 1) AS avg_days_active,
  ROUND(AVG(CASE WHEN l.user_id IS NOT NULL THEN DATEDIFF(day, l.last_leaderboard_date, CURRENT_DATE()) END), 0) AS avg_days_since_last_access
FROM user_retention_cohorts u
LEFT JOIN leaderboard_metrics l ON u.user_id = l.user_id
GROUP BY u.retention_cohort
ORDER BY
  CASE u.retention_cohort
    WHEN 'Active (0-7 days ago)' THEN 1
    WHEN 'Active (8-30 days ago)' THEN 2
    WHEN 'At Risk (31-90 days ago)' THEN 3
    WHEN 'Churned (90+ days ago)' THEN 4
    ELSE 5
  END;
