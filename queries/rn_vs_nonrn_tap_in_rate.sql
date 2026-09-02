-- Tap-In Rate: Rewards Network (RN) vs. Non-RN Offers
-- Answers: of offers that were shown (impressed), what share get tapped into
-- to view offer details? Compared for PAYER = 'Rewards Network' vs everyone else.
--
-- Data Sources:
--   FETCH_SERVICES_PROD.WEBSOCKET_SERVICE.WS_OFFER_BRAND_IMPRESSIONS_STAGE
--     - Events: offer_impression / Offer Impression, offer_tapped / Offer Tapped
--       (both snake_case and legacy Title Case variants included; Title Case
--       volume is negligible today but included for completeness)
--   FETCH_SERVICES_PROD.OFFERS.OFFERS_ATTRIBUTES
--     - PAYER field to split Rewards Network vs everything else
--
-- Window: trailing 30 days. NOTE: this counts any offer with activity in the
-- window, not just offers that are live *right now* -- a live-now snapshot
-- will show a smaller offer count than this trailing-window query because
-- offers rotate (some included here have since expired).

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
  SUM(e.impressions) AS total_impressions,
  SUM(e.taps) AS total_taps,
  ROUND(100.0 * SUM(e.taps) / NULLIF(SUM(e.impressions), 0), 3) AS tap_in_rate_pct,
  COUNT(DISTINCT e.OFFER_ID) AS n_offers,
  ROUND(SUM(e.impressions) / COUNT(DISTINCT e.OFFER_ID)) AS avg_impressions_per_offer
FROM events e
JOIN FETCH_SERVICES_PROD.OFFERS.OFFERS_ATTRIBUTES a ON e.OFFER_ID = a.OFFER_ID
GROUP BY 1
ORDER BY 1;
