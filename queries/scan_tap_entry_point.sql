-- Scan Button Tap Entry Point Breakdown
-- Answers: which surface/tab did a user tap "Scan" from?
--
-- Data Source: FETCH_SERVICES_PROD.WEBSOCKET_SERVICE.WS_SCAN_STAGE
-- Event: 'Scan Started' -> ENTRY_POINT property
--
-- CAVEAT: Entry Point values observed are Discover, Other, Me, DeepLink, Rewards.
-- There is no explicit "Home" bucket. Any tab not explicitly instrumented is
-- folded into "Other". Confirmed via raw JSON payload inspection: rows tagged
-- "Other" carry no secondary field (screen name, tab name, etc.) that reveals
-- the specific originating surface, so "Other" cannot be treated as a clean
-- proxy for "Home" today.
--
-- Related: FETCH_SERVICES_PROD.DISCOV.NAV_TAP_TRACKING tracks bottom-nav tab
-- usage windows (Discover, Me, Scan Tab, Shop, Snap, Social/Play, eReceipt).
-- Note there is no tab literally named "Home" in that nav model either --
-- worth confirming with eng whether "Home" maps to Discover or is untracked.

SELECT
  ENTRY_POINT,
  COUNT(*) AS tap_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM FETCH_SERVICES_PROD.WEBSOCKET_SERVICE.WS_SCAN_STAGE
WHERE EVENT_NAME = 'Scan Started'
  AND EVENT_DATE >= DATEADD(day, -90, CURRENT_DATE())
GROUP BY ENTRY_POINT
ORDER BY tap_count DESC;
