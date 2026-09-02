-- Offer Mechanics Comparison: Rewards Network (RN) vs. Non-RN Offers
-- Answers: do RN and non-RN offers differ structurally in how they're
-- targeted and what they require/pay out? Used to ground hypotheses about
-- why tap-in rate differs (see rn_vs_nonrn_tap_in_rate.sql) -- e.g. whether
-- store-level geo-targeting or purchase conditions play a role.
--
-- Data Source: FETCH_SERVICES_PROD.OFFERS.OFFERS_ATTRIBUTES
-- Scope: currently live offers only (OFFER_STATUS = 'PUBLISHED', current
-- timestamp between START_DATE_UTC and LATEST_END_DATE_UTC).
--
-- NOTE: DOLLARS_REQUIRED's unit is ambiguous in this table (values suggest
-- cents for some rows), so treat it as directional/relative, not a precise
-- dollar figure. Medians are reported alongside averages since this field
-- has outliers that skew the mean.

SELECT
  CASE WHEN PAYER = 'Rewards Network' THEN 'Rewards Network' ELSE 'Not Rewards Network' END AS payer_group,
  COUNT(*) AS n_offers,
  ROUND(100.0 * COUNT_IF(ARRAY_SIZE(STORE_NAMES) > 0) / COUNT(*), 1) AS pct_store_targeted,
  MEDIAN(TRY_TO_NUMBER(DOLLARS_REQUIRED)) AS median_dollars_required,
  ROUND(AVG(TRY_TO_NUMBER(DOLLARS_REQUIRED)), 2) AS avg_dollars_required,
  MEDIAN(POINTS_EARNED) AS median_points_earned,
  ROUND(AVG(POINTS_EARNED), 0) AS avg_points_earned,
  ROUND(AVG(LENGTH(DESCRIPTION)), 0) AS avg_description_len
FROM FETCH_SERVICES_PROD.OFFERS.OFFERS_ATTRIBUTES
WHERE OFFER_STATUS = 'PUBLISHED'
  AND CURRENT_TIMESTAMP() BETWEEN START_DATE_UTC AND LATEST_END_DATE_UTC
GROUP BY 1;
