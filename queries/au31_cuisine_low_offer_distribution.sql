-- AU31 Dine Cuisine Shelf Eligibility: users with only 1-2 eligible offers in a cuisine
-- Answers: for the Restaurants/Dine pill, how many cuisines does each AU31 user have
-- where they are eligible for only 1-2 offers (below the 3-offer shelf threshold)?
--
-- Data Sources:
--   ANALYTICS_PROD.FETCHDW.P_USER                     AU31 cohort (same definition as au31_restaurant_offer_eligibility.sql)
--   FETCH_SERVICES_PROD.DINING_METADATA_SERVICE.DINING_METADATA_UPDATED_METADATA_CURRENT_STATE_FSD
--                                                     primary_cuisine per location_id (OBJ:metadata)
--   ANALYTICS_PROD.REWARDS_NETWORK.RN_DAILY_USER_OFFER  user x offer x location eligibility windows
--
-- Method: count distinct live offers per user per primary cuisine (user-offer and offer
-- windows both current). 3+ offers = cuisine shelf shows. 1-2 = offers exist but no shelf.
--
-- Snapshot 2026-11-06: AU31 = 14,133,513. 94.89% of AU31 have 1+ cuisine with 1-2 offers
-- (avg 7.10); avg 13.92 cuisines with a shelf; 81.38% have 3+ shelves; 4.91% of
-- cuisine-tagged user-offer pairs sit in a 1-2 offer cuisine; 3.69% have no
-- cuisine-tagged offer at all.
--
-- CAVEATS: 3+ per-cuisine counts roughly match the AU31 Reach sheet (American 88.7% vs
-- 86.2%) but Coffee is off (38% vs 58%), cause not yet found. Excludes daypart shelves.
-- Runtime ~4 minutes. Uses session-only temp tables (needs a schema with CREATE TABLE).

USE SCHEMA ANALYTICS_PROD.PUBLIC;
CREATE OR REPLACE TEMPORARY TABLE au31 AS
SELECT id AS user_id
FROM ANALYTICS_PROD.FETCHDW.P_USER
WHERE deleted_ts IS NULL
  AND last_rewards_login >= DATEADD(day, -31, CURRENT_DATE());

CREATE OR REPLACE TEMPORARY TABLE loc_cuisine AS
SELECT OBJ:metadata:location_id::string AS location_id,
       REPLACE(OBJ:metadata:primary_cuisine::string, 'CUISINE_TYPE_', '') AS cuisine
FROM FETCH_SERVICES_PROD.DINING_METADATA_SERVICE.DINING_METADATA_UPDATED_METADATA_CURRENT_STATE_FSD
WHERE DELETED_TS IS NULL
  AND OBJ:metadata:primary_cuisine::string IS NOT NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY OBJ:metadata:location_id::string ORDER BY UPDATE_TS DESC) = 1;

CREATE OR REPLACE TEMPORARY TABLE user_cuisine AS
SELECT d.USER_ID AS user_id, c.cuisine, COUNT(DISTINCT d.OFFER_ID) AS n_offers
FROM ANALYTICS_PROD.REWARDS_NETWORK.RN_DAILY_USER_OFFER d
JOIN loc_cuisine c ON d.LOCATION_ID = c.location_id
WHERE d.START_TIME <= CURRENT_TIMESTAMP()
  AND d.END_TIME > CURRENT_TIMESTAMP()
  AND d.OFFER_START_TIME <= CURRENT_TIMESTAMP()
  AND d.OFFER_END_TIME > CURRENT_TIMESTAMP()
  AND d.USER_ID IN (SELECT user_id FROM au31)
GROUP BY 1, 2;

SELECT 'TOTAL_AU31' k, COUNT(*) v FROM au31
UNION ALL SELECT 'AU31_WITH_ANY_CUISINE_OFFER', COUNT(DISTINCT user_id) FROM user_cuisine;

-- per cuisine validation vs sheet
SELECT cuisine,
       COUNT_IF(n_offers BETWEEN 1 AND 2) AS users_1to2,
       COUNT_IF(n_offers >= 3) AS users_3plus
FROM user_cuisine GROUP BY 1 ORDER BY users_3plus DESC;

-- distribution: # of cuisines per user with 1-2 offers (no shelf, but has offers)
WITH per_user AS (
  SELECT a.user_id,
         COALESCE(SUM(IFF(uc.n_offers BETWEEN 1 AND 2, 1, 0)), 0) AS n_lowc,
         COALESCE(SUM(IFF(uc.n_offers >= 3, 1, 0)), 0) AS n_shelf,
         COALESCE(SUM(IFF(uc.n_offers BETWEEN 1 AND 2, uc.n_offers, 0)), 0) AS offers_orphaned,
         COALESCE(SUM(uc.n_offers), 0) AS offers_total
  FROM au31 a LEFT JOIN user_cuisine uc ON a.user_id = uc.user_id
  GROUP BY 1
)
SELECT CASE WHEN n_lowc BETWEEN 0 AND 5 THEN LPAD(n_lowc::string,2,'0')
            WHEN n_lowc BETWEEN 6 AND 7 THEN '06-07'
            WHEN n_lowc BETWEEN 8 AND 10 THEN '08-10'
            WHEN n_lowc BETWEEN 11 AND 15 THEN '11-15'
            ELSE '16+' END AS cuisines_with_1to2_offers,
       COUNT(*) AS n_users,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (),2) AS pct_au31
FROM per_user GROUP BY 1 ORDER BY 1;

WITH per_user AS (
  SELECT a.user_id,
         COALESCE(SUM(IFF(uc.n_offers BETWEEN 1 AND 2, 1, 0)), 0) AS n_lowc,
         COALESCE(SUM(IFF(uc.n_offers >= 3, 1, 0)), 0) AS n_shelf,
         COALESCE(SUM(IFF(uc.n_offers BETWEEN 1 AND 2, uc.n_offers, 0)), 0) AS offers_orphaned,
         COALESCE(SUM(uc.n_offers), 0) AS offers_total
  FROM au31 a LEFT JOIN user_cuisine uc ON a.user_id = uc.user_id
  GROUP BY 1
)
SELECT COUNT(*) users,
       ROUND(100.0*COUNT_IF(n_lowc>=1)/COUNT(*),2) pct_1plus_lowc,
       ROUND(AVG(n_lowc),2) avg_lowc,
       ROUND(AVG(n_shelf),2) avg_shelves,
       ROUND(100.0*COUNT_IF(n_shelf>=3)/COUNT(*),2) pct_3plus_shelves,
       ROUND(100.0*SUM(offers_orphaned)/NULLIF(SUM(offers_total),0),2) pct_offers_orphaned,
       ROUND(100.0*COUNT_IF(offers_total=0)/COUNT(*),2) pct_no_cuisine_offers
FROM per_user;
