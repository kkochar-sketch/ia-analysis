-- Impressed Redemption Rate: Rewards Network (RN) vs. Non-RN Offers
-- Answers: of offers that were shown (impressed), what share end in an
-- actual redemption? Same payer split and window as
-- rn_vs_nonrn_tap_in_rate.sql, for direct comparison.
--
-- Data Sources:
--   FETCH_SERVICES_PROD.WEBSOCKET_SERVICE.WS_OFFER_BRAND_IMPRESSIONS_STAGE
--     - Event: offer_impression / Offer Impression
--   FETCH_SERVICES_PROD.OFFERS.OFFER_USAGES
--     - Redemptions: SUM(USES), CREATED in the trailing window
--   FETCH_SERVICES_PROD.OFFERS.OFFERS_ATTRIBUTES
--     - PAYER field to split Rewards Network vs everything else
--
-- Window: trailing 30 days.

WITH impressions AS (
  SELECT OFFER_ID,
    COUNT_IF(LOWER(EVENT_NAME) = 'offer_impression' OR EVENT_NAME = 'Offer Impression') AS impressions
  FROM FETCH_SERVICES_PROD.WEBSOCKET_SERVICE.WS_OFFER_BRAND_IMPRESSIONS_STAGE
  WHERE EVENT_DATE >= DATEADD(day, -30, CURRENT_DATE())
    AND UPPER(EVENT_NAME) IN ('OFFER_IMPRESSION', 'OFFER IMPRESSION')
  GROUP BY OFFER_ID
),
redemptions AS (
  SELECT OFFER_ID,
    COUNT(*) AS redemption_records,
    SUM(COALESCE(USES, 1)) AS redemptions
  FROM FETCH_SERVICES_PROD.OFFERS.OFFER_USAGES
  WHERE CREATED >= DATEADD(day, -30, CURRENT_DATE())
  GROUP BY OFFER_ID
)
SELECT
  CASE WHEN a.PAYER = 'Rewards Network' THEN 'Rewards Network' ELSE 'Not Rewards Network' END AS payer_group,
  SUM(i.impressions) AS total_impressions,
  SUM(COALESCE(r.redemptions, 0)) AS total_redemptions,
  ROUND(100.0 * SUM(COALESCE(r.redemptions, 0)) / NULLIF(SUM(i.impressions), 0), 4) AS impressed_redemption_rate_pct,
  COUNT(DISTINCT i.OFFER_ID) AS n_offers
FROM impressions i
JOIN FETCH_SERVICES_PROD.OFFERS.OFFERS_ATTRIBUTES a ON i.OFFER_ID = a.OFFER_ID
LEFT JOIN redemptions r ON i.OFFER_ID = r.OFFER_ID
GROUP BY 1
ORDER BY 1;
