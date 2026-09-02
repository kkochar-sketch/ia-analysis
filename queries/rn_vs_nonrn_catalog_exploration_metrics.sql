-- Catalog-Level Exploration Metrics: Rewards Network (RN) vs. Non-RN Offers
-- Answers: does RN's share of the offer catalog structurally drag down an
-- "exploration" metric, and does that depend on how the metric is weighted?
--
-- Two framings that behave differently:
--   1. Impression-weighted (see rn_vs_nonrn_tap_in_rate.sql totals): RN is a
--      small share of total impression volume today (~2.7%), so its lower
--      tap-in rate barely moves the impression-weighted blended rate.
--   2. Offer-weighted / catalog-level (this query): RN is the large majority
--      of offers with any impressions (~84% in the trailing window), so a
--      simple average across offers (not weighted by impression volume)
--      drifts toward RN's lower per-offer rate as RN's catalog share grows.
--
-- Data Sources: same as rn_vs_nonrn_tap_in_rate.sql
-- Window: trailing 30 days.

WITH events AS (
  SELECT OFFER_ID,
    COUNT_IF(LOWER(EVENT_NAME) = 'offer_impression' OR EVENT_NAME = 'Offer Impression') AS impressions,
    COUNT_IF(LOWER(EVENT_NAME) = 'offer_tapped' OR EVENT_NAME = 'Offer Tapped') AS taps
  FROM FETCH_SERVICES_PROD.WEBSOCKET_SERVICE.WS_OFFER_BRAND_IMPRESSIONS_STAGE
  WHERE EVENT_DATE >= DATEADD(day, -30, CURRENT_DATE())
    AND UPPER(EVENT_NAME) IN ('OFFER_IMPRESSION', 'OFFER TAPPED', 'OFFER_TAPPED')
  GROUP BY OFFER_ID
)
SELECT
  CASE WHEN a.PAYER = 'Rewards Network' THEN 'Rewards Network' ELSE 'Not Rewards Network' END AS payer_group,
  COUNT(*) AS n_offers_with_impressions,
  ROUND(100.0 * COUNT_IF(e.taps > 0) / COUNT(*), 1) AS pct_offers_ever_tapped,
  ROUND(100.0 * COUNT_IF(e.taps = 0) / COUNT(*), 1) AS pct_offers_never_tapped,
  ROUND(AVG(100.0 * e.taps / NULLIF(e.impressions, 0)), 3) AS unweighted_avg_offer_tap_rate_pct
FROM events e
JOIN FETCH_SERVICES_PROD.OFFERS.OFFERS_ATTRIBUTES a ON e.OFFER_ID = a.OFFER_ID
GROUP BY 1;
