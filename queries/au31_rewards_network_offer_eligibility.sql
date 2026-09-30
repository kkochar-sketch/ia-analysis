-- AU31 Rewards Network Offer Eligibility Distribution
-- Answers: of users active in the trailing 31 days (AU31), how many live
-- Rewards Network offers is each one eligible for?
--
-- Rewards-Network-specific sibling of au31_restaurant_offer_eligibility.sql.
-- RN = businessId '672cf2953228c23b4dc0cab2'.
--
-- Data Sources:
--   ANALYTICS_PROD.FETCHDW.P_USER
--     - AU31 cohort: deleted_ts IS NULL AND last_rewards_login >= DATEADD(day, -31, CURRENT_DATE())
--   FETCH_SERVICES_PROD.STAGING.OFFER_CAMPAIGNS_ATTRIBUTES_STAGE
--     - BUSINESS_ID = '672cf2953228c23b4dc0cab2' -> the RN offer campaigns
--   FETCH_SERVICES_PROD.OFFERS.OFFERS_ATTRIBUTES
--     - Live offers: OFFER_STATUS = 'PUBLISHED',
--       CURRENT_TIMESTAMP() BETWEEN START_DATE_UTC AND LATEST_END_DATE_UTC
--     - Joined to the RN campaigns on OFFER_CAMPAIGN_ID
--   FETCH_SERVICES_PROD.OFFERS.OFFERS_AUDIENCE_CURRENT_SNAPSHOT
--     - Per-user eligibility: IN_AUDIENCE = TRUE AND (INELIGIBLE IS NULL OR INELIGIBLE = FALSE)
--
-- WHY THE CAMPAIGN JOIN: businessId is an attribute of the offer *campaign*,
-- not the offer -- OFFERS_ATTRIBUTES has no business_id column -- so the RN
-- filter has to come in through OFFER_CAMPAIGN_ID.
-- OFFER_CAMPAIGNS_ATTRIBUTES_STAGE is incremental on offer_campaign_id
-- (delete+insert), so it holds one current-state row per campaign; no dedupe
-- needed.
--
-- CAVEAT (freshness): that stage table ran ~8h behind when checked on
-- 2026-09-02, so offers from campaigns created since its last load drop out
-- silently (4 of them that day). Immaterial across ~16.4K offers; if you need
-- same-day completeness, source the campaign list from
-- FETCH_SERVICES_PROD.OFFERS.OFFER_CAMPAIGNS_CHANGES instead.
--
-- NOTE: No CATEGORY filter -- all 16,424 live RN offers are already
-- CATEGORY = 'RESTAURANTS' (vs. 16,564 live Restaurants overall), so this is a
-- strict subset of the restaurant population and the filter would be a no-op.
--
-- CAVEAT: as in the restaurant query, a small number of live offers have no
-- rows at all in OFFERS_AUDIENCE_CURRENT_SNAPSHOT (likely brand-new or
-- open-audience offers not yet processed into the snapshot). Those offers are
-- excluded from every user's eligible count -- a small, uniform undercount
-- across the whole population, not something that changes the shape of the
-- distribution.
--
-- NOTE: OFFERS_AUDIENCE_CURRENT_SNAPSHOT is enormous (~69B rows, ~2.3TB).
-- Expect this query to run 5-8 minutes on a standard warehouse.

WITH au31_users AS (
  SELECT id AS user_id
  FROM ANALYTICS_PROD.FETCHDW.P_USER
  WHERE deleted_ts IS NULL
    AND last_rewards_login >= DATEADD(day, -31, CURRENT_DATE())
),
rn_campaigns AS (
  SELECT OFFER_CAMPAIGN_ID
  FROM FETCH_SERVICES_PROD.STAGING.OFFER_CAMPAIGNS_ATTRIBUTES_STAGE
  WHERE BUSINESS_ID = '672cf2953228c23b4dc0cab2'
),
rn_offers AS (
  SELECT a.OFFER_ID
  FROM FETCH_SERVICES_PROD.OFFERS.OFFERS_ATTRIBUTES a
  JOIN rn_campaigns c ON a.OFFER_CAMPAIGN_ID = c.OFFER_CAMPAIGN_ID
  WHERE a.OFFER_STATUS = 'PUBLISHED'
    AND CURRENT_TIMESTAMP() BETWEEN a.START_DATE_UTC AND a.LATEST_END_DATE_UTC
),
eligible_counts AS (
  SELECT
    s.USER_ID AS user_id,
    COUNT(DISTINCT s.OFFER_ID) AS n_eligible_offers
  FROM FETCH_SERVICES_PROD.OFFERS.OFFERS_AUDIENCE_CURRENT_SNAPSHOT s
  JOIN rn_offers r ON s.OFFER_ID = r.OFFER_ID
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
