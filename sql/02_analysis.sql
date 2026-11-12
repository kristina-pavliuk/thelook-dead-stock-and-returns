-- Project: Where does TheLook lose money?
-- Data: TheLook eCommerce snapshot
-- Snapshot date: 2026-11-14
-- Author: Kristina Pavliuk


-- 1. Check: inventory age for sold and unsold units

SELECT
  is_sold,
  COUNT(*) AS units,
  MIN(age_days) AS min_age_days,
  ROUND(AVG(age_days), 1) AS avg_age_days,
  APPROX_QUANTILES(age_days, 100)[OFFSET(50)] AS median_age_days,
  MAX(age_days) AS max_age_days
FROM `thelook-portfolio-514213.analysis.base_inventory` 
GROUP BY is_sold;

-- Result: 181,049 sold units, 308,120 unsold units.
-- Sold units: median age 30 days, max 60 days.
-- Unsold units: median age 1,256 days.
-- Insight: no unit sells after 60 days. This looks like a rule of the synthetic data.


-- 2. Check: unsold units aged 60 days or less

SELECT COUNT(*) AS live_units
FROM `thelook-portfolio-514213.analysis.base_inventory` 
WHERE 
  age_days <= 60
  AND
  is_sold = FALSE;

-- Result: 7,178 unsold units are 60 days old or younger
-- Insight: these units can still sell within the 60-day window.


-- 3. Check: share of dead stock in current stock

SELECT 
  ROUND(COUNTIF(age_days > 60) /  COUNT(*) * 100, 1) AS dead_stock_share_pct
FROM `thelook-portfolio-514213.analysis.base_inventory` 
WHERE is_sold = FALSE;

-- Result: 97.7% of current stock is dead stock.
-- Insight: almost all current stock will likely never sell.


-- 4. Check: How much money is frozen in dead stock?

SELECT 
  ROUND(SUM(IF(age_days > 60, cost, 0))) AS dead_stock_cost,
  ROUND(SUM(cost)) AS unsold_stock_cost,
  ROUND(SUM(IF(age_days > 60, cost,0)) / SUM(cost) * 100, 1) AS dead_stock_cost_share_pct
FROM `thelook-portfolio-514213.analysis.base_inventory` 
WHERE is_sold = FALSE;

-- Result: $8.6M of $8.8M (97.7%) is frozen in dead stock.
-- Insight: almost all money in current stock does not work for the business.


-- 5. Check: average and median cost of dead and live units

SELECT   
  age_days > 60 AS is_dead_stock,
  COUNT(*) AS units,
  ROUND(AVG(cost), 1) AS average_cost,
  ROUND(APPROX_QUANTILES(cost, 100)[OFFSET(50)], 1) AS median_cost
FROM `thelook-portfolio-514213.analysis.base_inventory` 
WHERE is_sold = FALSE
GROUP BY is_dead_stock;

-- Result: dead stock: average cost 28.6, median 19.9.
-- Live stock: average cost 28.4, median 19.6.
-- Insight: dead stock is not cheaper than live stock.
-- Cost is right-skewed: many cheap units and a few expensive ones.


-- 6. Check: how much money of dead stock  are in every category?

SELECT
  product_category,
  ROUND(SUM(cost)) AS sum_cost,
  ROUND(SUM(cost) / SUM(SUM(cost)) OVER() * 100) AS share_cost
FROM `thelook-portfolio-514213.analysis.base_inventory` 
WHERE age_days > 60 AND is_sold = false
GROUP BY product_category
ORDER BY share_cost DESC;

-- Result: the largest amount of dead stock value lies in Jeans, Outerwear & Coats, and Sweaters


-- 7. Check: return rate by category

SELECT
  product_category,
  ROUND(COUNT(product_category)) AS count_units,
  ROUND(COUNTIF(status ='Returned') / (COUNT(product_category)) * 100, 1) AS return_rate_pct
FROM `thelook-portfolio-514213.analysis.raw_order_items` oi 
LEFT JOIN `thelook-portfolio-514213.analysis.base_inventory`  bi
ON bi.id=oi.inventory_item_id
GROUP BY product_category
ORDER BY return_rate_pct DESC;

-- Result: most categories have a return rate of about 10%.
-- Lowest: Suits (8.1%, 1,078 items sold), Socks (10.6%, 217 items sold).
-- Insight: return rates are almost the same in all categories. The lowest values come from small categories, so they may be random.
-- This looks like another rule of the synthetic data.


-- 8. Check: dead stock cost by distribution center

SELECT 
  distribution_center,
  ROUND(SUM(cost)) AS dead_stock_cost,
  ROUND(SUM(cost) / SUM(SUM(cost)) OVER() * 100, 1) AS dead_stock_share_pct
FROM `thelook-portfolio-514213.analysis.base_inventory` 
WHERE 
  is_sold = FALSE
  AND
  age_days > 60
GROUP BY distribution_center
ORDER BY dead_stock_share_pct DESC;

-- Result: top 3 centers: Houston TX ($1.24M, 14.4%), Memphis TN (13.0%), Chicago IL (12.2%).
-- Together they hold about 40% of dead stock cost.
-- Insight: dead stock is concentrated in a few centers.
-- A clearance or write-off review could start with these 3 centers.


-- 9. Check: how much money is lost to returns
-- Cancelled items are excluded, because customers did not pay for them.

SELECT 
  ROUND(SUM(sale_price)) AS gross_revenue,
  ROUND(SUM(IF(status = "Returned", sale_price, 0)) / SUM(sale_price) * 100, 1) AS lost_revenue_share_pct,
  ROUND(SUM(IF(status = "Returned", sale_price, 0))) AS lost_revenue,
  ROUND(SUM(IF(status = "Returned", sale_price - cost, 0))) AS lost_margin
FROM `thelook-portfolio-514213.analysis.base_order_items`
WHERE status != "Cancelled";

-- Result: gross revenue $9.11M. Returns: $1.07M (11.7% of gross revenue).
-- Lost margin from returns: $0.55M.
-- Insight: returns cost the shop about $1M in revenue.
-- This is much smaller than the $8.6M frozen in dead stock.

