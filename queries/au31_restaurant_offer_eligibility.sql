-- AU31 Restaurant Offer Eligibility Distribution
-- Answers: of users active in the trailing 31 days (AU31), how many live
-- Restaurant-category offers is each one eligible for?
--
-- Data Sources:
--   ANALYTICS_PROD.FETCHDW.P_USER
--     - AU31 cohort: deleted_ts IS NULL AND last_rewards_login >= DATEADD(day, -31, CURRENT_DATE())
--   FETCH_SERVICES_PROD.OFFERS.OFFERS_ATTRIBUTES
--     - Live Restaurant offers: OFFER_STATUS = 'PUBLISHED', CATEGORY = 'RESTAURANTS',
--       CURRENT_TIMESTAMP() BETWEEN START_DATE_UTC AND LATEST_END_DATE_UTC
--   FETCH_SERVICES_PROD.OFFERS.OFFERS_AUDIENCE_CURRENT_SNAPSHOT
--     - Per-user eligibility: IN_AUDIENCE = TRUE AND (INELIGIBLE IS NULL OR INELIGIBLE = FALSE)
--
-- CAVEAT: ~94 of the 16,601 live Restaurant offers (as of 2026-09-01) have no
-- rows at all in OFFERS_AUDIENCE_CURRENT_SNAPSHOT (likely brand-new or
-- open-audience offers not yet processed into the snapshot). Those offers are
-- excluded from every user's eligible count -- a small, uniform undercount
-- across the whole population, not something that changes the shape of the
-- distribution.
--
-- NOTE: This table is enormous (~69B rows, ~2.3TB). Expect this query to run
-- 5-8 minutes on a standard warehouse.

WITH au31_users AS (
  SELECT id AS user_id
  FROM ANALYTICS_PROD.FETCHDW.P_USER
  WHERE deleted_ts IS NULL
    AND last_rewards_login >= DATEADD(day, -31, CURRENT_DATE())
),
restaurant_offers AS (
  SELECT OFFER_ID
  FROM FETCH_SERVICES_PROD.OFFERS.OFFERS_ATTRIBUTES
  WHERE OFFER_STATUS = 'PUBLISHED'
    AND UPPER(CATEGORY) = 'RESTAURANTS'
    AND CURRENT_TIMESTAMP() BETWEEN START_DATE_UTC AND LATEST_END_DATE_UTC
),
eligible_counts AS (
  SELECT
    s.USER_ID AS user_id,
    COUNT(DISTINCT s.OFFER_ID) AS n_eligible_offers
  FROM FETCH_SERVICES_PROD.OFFERS.OFFERS_AUDIENCE_CURRENT_SNAPSHOT s
  JOIN restaurant_offers r ON s.OFFER_ID = r.OFFER_ID
  WHERE s.IN_AUDIENCE = TRUE
    AND (s.INELIGIBLE IS NULL OR s.INELIGIBLE = FALSE)
    AND s.USER_ID IN (SELECT user_id FROM au31_users)
  GROUP BY s.USER_ID
),
joined AS (
  SELECT
    u.user_id,
    COALESCE(ec.n_eligible_offers, 0) AS n_eligible_offers
  FROM au31_users u
  LEFT JOIN eligible_counts ec ON u.user_id = ec.user_id
)
SELECT
  CASE
    WHEN n_eligible_offers = 0 THEN '0 offers'
    WHEN n_eligible_offers BETWEEN 1 AND 9 THEN '1-9'
    WHEN n_eligible_offers BETWEEN 10 AND 49 THEN '10-49'
    WHEN n_eligible_offers BETWEEN 50 AND 99 THEN '50-99'
    WHEN n_eligible_offers BETWEEN 100 AND 249 THEN '100-249'
    WHEN n_eligible_offers BETWEEN 250 AND 499 THEN '250-499'
    WHEN n_eligible_offers BETWEEN 500 AND 999 THEN '500-999'
    ELSE '1000+'
  END AS offer_count_bucket,
  COUNT(*) AS n_users,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 3) AS pct_of_au31
FROM joined
GROUP BY 1
ORDER BY MIN(n_eligible_offers);
