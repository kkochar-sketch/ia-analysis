-- Revenue Split: Rewards Network (RN) vs. Non-RN Restaurant Offers
-- Answers: of Restaurant-category offer revenue, what share comes from RN
-- vs. everything else (brand-funded deals like Taco Bell, KFC, Chipotle,
-- Costco, Pepsico, DoorDash, Albertsons, Baskin-Robbins, etc.)?
--
-- Data Sources:
--   FETCH_SERVICES_PROD.OFFERS.OFFERS_ATTRIBUTES
--     - CATEGORY = 'RESTAURANTS' to scope to the category
--     - PAYER to split Rewards Network vs everything else
--   FETCH_SERVICES_PROD.FINANCE.REVENUE_AND_EXPENSE_MODEL
--     - OFFER_ID, REVENUE, CREATED_DATE (offer/receipt-level revenue)
--
-- Window: calendar month August 2026, the most recent full month at time
-- of writing.
--
-- CAVEAT: FETCH_SERVICES_PROD.FINANCE.REVENUE_AND_EXPENSE (the non-"_MODEL"
-- sibling view) is currently broken -- querying it throws "View definition
-- ... declared 32 column(s), but view query produces 34 column(s)." Use
-- REVENUE_AND_EXPENSE_MODEL instead; this is a real data-quality issue on
-- that view, not a typo in this query.
--
-- CAVEAT: cross-checking the non-RN offer count against a different
-- category source (fetch_services_prod.lighthouse.offer_level_metrics,
-- same August window) gives only 35 non-RN offers and a 75.3% / 24.7%
-- RN / non-RN revenue split, vs. 93 offers and 67.7% / 32.3% here. The two
-- category source tables disagree on which offers count as "Restaurants"
-- for non-RN brand deals. Treat the *direction* of this finding as solid
-- (RN dominates offer count, non-RN dominates revenue-per-offer by roughly
-- two orders of magnitude) but not the decimal precision.
--
-- CAVEAT: the RN revenue total here ($1.473M) differs from
-- ANALYTICS_PROD.REWARDS_NETWORK.RN_DAILY_REVENUE for the same month
-- ($1.513M, aggregation_level = 'qualification_date') by about 2.6%.
-- Different revenue systems, not reconciled -- worth confirming with
-- whoever owns RN finance reporting before citing either number externally.

WITH restaurant_offers AS (
  SELECT OFFER_ID, PAYER
  FROM FETCH_SERVICES_PROD.OFFERS.OFFERS_ATTRIBUTES
  WHERE CATEGORY = 'RESTAURANTS'
)
SELECT
  CASE WHEN ro.PAYER = 'Rewards Network' THEN 'Rewards Network' ELSE 'Not Rewards Network' END AS payer_group,
  SUM(rem.REVENUE) AS total_revenue,
  COUNT(DISTINCT rem.OFFER_ID) AS n_offers_with_revenue,
  COUNT(*) AS transaction_rows,
  ROUND(SUM(rem.REVENUE) / COUNT(DISTINCT rem.OFFER_ID), 2) AS avg_revenue_per_offer
FROM FETCH_SERVICES_PROD.FINANCE.REVENUE_AND_EXPENSE_MODEL rem
JOIN restaurant_offers ro ON rem.OFFER_ID = ro.OFFER_ID
WHERE rem.CREATED_DATE >= '2026-08-01' AND rem.CREATED_DATE < '2026-09-01'
GROUP BY 1
ORDER BY 1;
