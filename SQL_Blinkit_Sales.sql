-- ============================================================
-- BLINKIT SALES ANALYSIS
-- Dataset: 8,523 records | Source: BlinkIT Grocery Data
-- Goal: Identify revenue drivers and outlet strategy signals
-- ============================================================


-- ============================================================
-- SETUP: Database creation and table schema
-- ============================================================

CREATE DATABASE blinkit_project;
USE blinkit_project;

SHOW VARIABLES LIKE "secure%";

-- Composite primary key on Item + Outlet combination because
-- the same product can appear across multiple outlets.
-- This prevents duplicate records at the item-outlet level.
CREATE TABLE blinkit_data (
    Item_Fat_Content         VARCHAR(20),
    Item_Identifier          VARCHAR(20),
    Item_Type                VARCHAR(50),
    Outlet_Establishment_Year INT,
    Outlet_Identifier        VARCHAR(20),
    Outlet_Location_Type     VARCHAR(20),
    Outlet_Size              VARCHAR(20),
    Outlet_Type              VARCHAR(30),
    Item_Visibility          DECIMAL(10,6),
    Item_Weight              DECIMAL(5,2),
    Total_Sales              DECIMAL(10,2),
    Rating                   DECIMAL(3,2),
    PRIMARY KEY (Item_Identifier, Outlet_Identifier)
);

-- Loading from secure upload path (MySQL secure_file_priv location)
-- NULLIF handles empty strings in CSV — converts them to proper NULLs
-- so aggregate functions like AVG() ignore them correctly
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/BlinkIT Grocery Data.csv'
INTO TABLE blinkit_data
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(Item_Fat_Content,
 Item_Identifier,
 Item_Type,
 Outlet_Establishment_Year,
 Outlet_Identifier,
 Outlet_Location_Type,
 Outlet_Size,
 Outlet_Type,
 @Item_Visibility,
 @Item_Weight,
 @Total_Sales,
 @Rating)
SET
Item_Visibility = NULLIF(@Item_Visibility, ''),
Item_Weight     = NULLIF(@Item_Weight, ''),
Total_Sales     = NULLIF(@Total_Sales, ''),
Rating          = NULLIF(@Rating, '');

-- Quick sanity check after load — expect 8,523 rows
SELECT * FROM blinkit_data;
SELECT COUNT(*) FROM blinkit_data;


-- ============================================================
-- SECTION 1: Data Cleaning
-- Standardizing fat content labels before any analysis.
-- Raw data has 'LF', 'low fat', 'reg' as inconsistent entries —
-- these must be unified or GROUP BY queries will produce
-- phantom duplicate rows and wrong totals.
-- ============================================================

-- Disabling safe update mode to allow UPDATE without a WHERE key
SET SQL_SAFE_UPDATES = 0;

UPDATE blinkit_data
SET Item_Fat_Content =
    CASE
        WHEN Item_Fat_Content IN ('LF', 'low fat') THEN 'Low Fat'
        WHEN Item_Fat_Content = 'reg'              THEN 'Regular'
        ELSE Item_Fat_Content
    END;

-- Verification step — should return exactly 2 distinct values:
-- 'Low Fat' and 'Regular'. If anything else appears, recheck source data.
SELECT DISTINCT Item_Fat_Content FROM blinkit_data;


-- ============================================================
-- SECTION 2: KPIs — Establish the baseline numbers
-- These four metrics form the executive summary. Every deeper
-- analysis below should be interpreted relative to these.
-- ============================================================

-- Total revenue in millions — dividing by 1M for readability
-- in dashboards and executive presentations
SELECT 
    CAST(SUM(total_sales)/1000000 AS DECIMAL(10,2)) AS total_sales_million
FROM blinkit_data;

-- Average transaction value — helps distinguish whether high total
-- sales are driven by volume or by high-value individual items
SELECT 
    CAST(AVG(total_sales) AS DECIMAL(10,0)) AS avg_sales_per_record
FROM blinkit_data;

-- Total record count — baseline for all percentage calculations below
SELECT COUNT(*) AS total_records FROM blinkit_data;

-- Average rating across all products — use as a benchmark
-- when comparing individual item or outlet ratings later
SELECT 
    CAST(AVG(rating) AS DECIMAL(10,1)) AS avg_rating
FROM blinkit_data;


-- ============================================================
-- SECTION 3: Fat Content Analysis
-- Business question: Is there a health-conscious buying trend?
-- If Low Fat consistently outsells Regular, this is a procurement
-- signal to shift inventory mix toward healthier variants.
-- ============================================================

-- Overall revenue split by fat content
SELECT 
    Item_Fat_Content,
    CAST(SUM(Total_Sales) AS DECIMAL(10,2)) AS Total_Sales
FROM blinkit_data
GROUP BY Item_Fat_Content;

-- Fat content breakdown by city tier (Tier 1 / 2 / 3)
-- If Tier 1 cities skew more Low Fat, that's a demographic signal
-- that health-conscious demand is urban and concentrated —
-- useful for targeted marketing and stocking decisions
SELECT 
    Outlet_Location_Type,
    SUM(CASE WHEN Item_Fat_Content = 'Low Fat'  THEN Total_Sales ELSE 0 END) AS Low_Fat_Sales,
    SUM(CASE WHEN Item_Fat_Content = 'Regular'  THEN Total_Sales ELSE 0 END) AS Regular_Sales
FROM blinkit_data
GROUP BY Outlet_Location_Type
ORDER BY Outlet_Location_Type;


-- ============================================================
-- SECTION 4: Product Performance
-- Business question: Which categories deserve priority shelf
-- space, procurement budget, and app placement?
-- ============================================================

-- Revenue by item type — sorted descending to immediately
-- surface the top-performing categories
SELECT 
    Item_Type,
    CAST(SUM(Total_Sales) AS DECIMAL(10,2)) AS Total_Sales
FROM blinkit_data
GROUP BY Item_Type
ORDER BY Total_Sales DESC;

-- Same query with RANK() added — makes it easy to slice
-- top 5 vs bottom 5 without rewriting, useful for presentations
-- Bottom-ranked categories are candidates for delisting or
-- reduced shelf allocation
SELECT 
    Item_Type,
    ROUND(SUM(Total_Sales), 2)                              AS Total_Sales,
    RANK() OVER (ORDER BY SUM(Total_Sales) DESC)            AS Sales_Rank
FROM blinkit_data
GROUP BY Item_Type;


-- ============================================================
-- SECTION 5: Outlet Analysis
-- Business question: Which outlet type and size should Blinkit
-- prioritize for future expansion investment?
-- ============================================================

-- Revenue share by outlet size
-- Medium outlets driving ~42% suggests an optimal format that
-- balances SKU variety with manageable operational overhead.
-- If confirmed, new store rollouts should default to medium format.
SELECT 
    Outlet_Size,
    ROUND(SUM(Total_Sales), 2)                                              AS Total_Sales,
    ROUND(
        SUM(Total_Sales) * 100.0 / (SELECT SUM(Total_Sales) FROM blinkit_data),
    2)                                                                      AS Sales_Pct
FROM blinkit_data
GROUP BY Outlet_Size
ORDER BY Total_Sales DESC;

-- Full outlet type breakdown with all metrics in one view.
-- Revenue contribution % uses SUM() OVER () (window function) —
-- cleaner than a subquery and runs in a single pass.
-- If Type1 exceeds 60% revenue share, flag as concentration risk.
SELECT 
    Outlet_Type,
    ROUND(AVG(Total_Sales), 0) AS Avg_Sales,
    COUNT(*) AS No_Of_Items,
    ROUND(AVG(Rating), 2) AS Avg_Rating,
    ROUND(AVG(Item_Visibility), 2) AS Avg_Item_Visibility,
    ROUND(SUM(Total_Sales), 2) AS Total_Sales,
    ROUND(
        SUM(Total_Sales) * 100.0 / SUM(SUM(Total_Sales)) OVER (),
    2) AS Revenue_Pct
FROM blinkit_data
GROUP BY Outlet_Type
ORDER BY Revenue_Pct DESC;

-- Top performing outlet type within each city tier using PARTITION BY.
-- Answers: "In each location type, which outlet format wins?"
-- Output feeds directly into city-specific expansion playbooks.
SELECT *
FROM (
    SELECT 
        Outlet_Location_Type,
        Outlet_Type,
        ROUND(SUM(Total_Sales), 2)                          AS Total_Sales,
        RANK() OVER (
            PARTITION BY Outlet_Location_Type 
            ORDER BY SUM(Total_Sales) DESC
        )                                                   AS Location_Rank
    FROM blinkit_data
    GROUP BY Outlet_Location_Type, Outlet_Type
) ranked_outlets
WHERE Location_Rank = 1;


-- ============================================================
-- SECTION 6: Strategic Signal Queries
-- These queries test three assumptions that could change
-- how Blinkit allocates resources and plans operations.
-- Each one has a stated hypothesis so results are actionable.
-- ============================================================

-- SIGNAL 1: Does outlet age predict revenue?
-- Hypothesis: older outlets should earn more due to an
-- established customer base and brand familiarity.
-- If the trend is flat or inconsistent, outlet age is not
-- a useful planning variable — focus on format and location instead.
SELECT 
    Outlet_Establishment_Year,
    COUNT(DISTINCT Outlet_Identifier)                                       AS No_Of_Outlets,
    ROUND(SUM(Total_Sales), 2)                                              AS Total_Sales,
    ROUND(AVG(Total_Sales), 0)                                              AS Avg_Sales_Per_Record,
    ROUND(SUM(Total_Sales) / COUNT(DISTINCT Outlet_Identifier), 2)          AS Sales_Per_Outlet
FROM blinkit_data
GROUP BY Outlet_Establishment_Year
ORDER BY Outlet_Establishment_Year;

-- SIGNAL 2: Does product rating drive revenue?
-- Hypothesis: higher-rated products should outsell lower-rated ones
-- if customers are using ratings as a purchase signal.
-- If Medium Rated outsells High Rated, customers are buying on
-- habit or availability — ratings UX may need redesign.
SELECT 
    CASE 
        WHEN Rating >= 4              THEN 'High Rated (4+)'
        WHEN Rating BETWEEN 3 AND 3.99 THEN 'Medium Rated (3–3.99)'
        ELSE                               'Low Rated (<3)'
    END AS Rating_Category,
    ROUND(SUM(Total_Sales), 2) AS Total_Sales
FROM blinkit_data
GROUP BY Rating_Category;

-- SIGNAL 3: Does product visibility drive revenue?
-- Hypothesis: prominently placed products (high visibility score)
-- should generate more sales.
-- If low-visibility products still perform well, then product type
-- and price point matter more than shelf placement —
-- reallocating visibility spend may have little ROI.
SELECT 
    CASE 
        WHEN Item_Visibility < 0.05                  THEN 'Low (<0.05)'
        WHEN Item_Visibility BETWEEN 0.05 AND 0.15   THEN 'Medium (0.05–0.15)'
        ELSE                                              'High (>0.15)'
    END AS Visibility_Bucket,
    ROUND(SUM(Total_Sales), 2)  AS Total_Sales,
    ROUND(AVG(Total_Sales), 2)  AS Avg_Sales
FROM blinkit_data
GROUP BY Visibility_Bucket
ORDER BY Total_Sales DESC;

-- ============================================================
-- ANALYSIS: Most Profitable Product–Outlet Combinations
-- ============================================================
-- Business question: Which specific product category performs
-- best in which outlet type, and is that pattern consistent
-- or driven by a single outlier record?
--
-- Why this matters: Blinkit can use this to make targeted
-- stocking decisions — e.g. if Seafood performs exceptionally
-- in Supermarket Type1 but poorly in Grocery Stores, the
-- procurement team should stock it selectively, not universally.
-- ============================================================


-- ============================================================
-- STEP 1: Simple version — total sales per combination
-- Good starting point but doesn't tell us if high revenue
-- is coming from many items or just a few expensive ones.
-- ============================================================

SELECT
    Item_Type,
    Outlet_Type,
    ROUND(SUM(Total_Sales), 2)   AS Total_Sales,
    COUNT(*)                     AS Item_Count,
    ROUND(AVG(Total_Sales), 2)   AS Avg_Sales_Per_Item
FROM blinkit_data
GROUP BY Item_Type, Outlet_Type
ORDER BY Total_Sales DESC
LIMIT 10;


-- ============================================================
-- STEP 2: Full portfolio query using CTE
-- Adds rankings, performance vs category average, and flags
-- which combinations are genuinely strong vs just high-volume.
-- This is the version worth showing in interviews.
-- ============================================================

WITH combination_stats AS (
    -- Base aggregation: one row per product-outlet combination
    -- Avg_Sales_Per_Item matters more than Total_Sales here —
    -- a combination with 10 items averaging $500 is more
    -- interesting than one with 500 items averaging $10
    SELECT
        Item_Type,
        Outlet_Type,
        Outlet_Size,
        Outlet_Location_Type,
        COUNT(*)                            AS Item_Count,
        ROUND(SUM(Total_Sales), 2)          AS Total_Sales,
        ROUND(AVG(Total_Sales), 2)          AS Avg_Sales_Per_Item,
        ROUND(AVG(Rating), 2)               AS Avg_Rating,
        ROUND(AVG(Item_Visibility), 4)      AS Avg_Visibility
    FROM blinkit_data
    GROUP BY Item_Type, Outlet_Type, Outlet_Size, Outlet_Location_Type
),

category_benchmarks AS (
    -- Average sales per item for each product category overall.
    -- Used below to flag whether a combination is outperforming
    -- its own category average — a much fairer comparison than
    -- comparing Seafood sales to Fruits & Vegetables sales.
    SELECT
        Item_Type,
        ROUND(AVG(Total_Sales), 2) AS Category_Avg_Sales
    FROM blinkit_data
    GROUP BY Item_Type
),

ranked_combinations AS (
    -- Join the two CTEs and add:
    -- 1. Overall rank by avg sales per item
    -- 2. Rank within each product category (so we find the best
    --    outlet for each product type, not just globally)
    -- 3. Performance vs category average as a percentage
    SELECT
        cs.Item_Type,
        cs.Outlet_Type,
        cs.Outlet_Size,
        cs.Outlet_Location_Type,
        cs.Item_Count,
        cs.Total_Sales,
        cs.Avg_Sales_Per_Item,
        cs.Avg_Rating,
        cs.Avg_Visibility,
        cb.Category_Avg_Sales,

        -- How much better/worse is this combo vs its category average?
        -- Positive = outperforming, negative = underperforming
        ROUND(
            ((cs.Avg_Sales_Per_Item - cb.Category_Avg_Sales)
            / cb.Category_Avg_Sales) * 100
        , 1)                                                        AS Pct_Vs_Category_Avg,

        -- Global rank across all combinations
        RANK() OVER (
            ORDER BY cs.Avg_Sales_Per_Item DESC
        )                                                           AS Overall_Rank,

        -- Rank within each product category — answers "what is the
        -- best outlet type specifically for Dairy?" etc.
        RANK() OVER (
            PARTITION BY cs.Item_Type
            ORDER BY cs.Avg_Sales_Per_Item DESC
        )                                                           AS Rank_Within_Category

    FROM combination_stats cs
    JOIN category_benchmarks cb
        ON cs.Item_Type = cb.Item_Type
)

-- ============================================================
-- FINAL OUTPUT: Top combinations that are genuinely strong
-- Filters applied:
-- 1. Overall_Rank <= 20 keeps output scannable
-- 2. Item_Count >= 5 removes combinations with too few records
--    to be statistically meaningful (single-item outliers)
-- Remove or adjust these filters based on your findings
-- ============================================================

SELECT
    Overall_Rank,
    Item_Type,
    Outlet_Type,
    Outlet_Size,
    Outlet_Location_Type,
    Item_Count,
    Total_Sales,
    Avg_Sales_Per_Item,
    Avg_Rating,
    Category_Avg_Sales,
    Pct_Vs_Category_Avg,
    Rank_Within_Category,
    -- Plain English label for presentations and dashboards
    CASE
        WHEN Pct_Vs_Category_Avg >= 20  THEN 'Strong outperformer'
        WHEN Pct_Vs_Category_Avg >= 5   THEN 'Slight outperformer'
        WHEN Pct_Vs_Category_Avg >= -5  THEN 'In line with category'
        WHEN Pct_Vs_Category_Avg >= -20 THEN 'Slight underperformer'
        ELSE                                 'Weak — review or delist'
    END                                                         AS Performance_Label

FROM ranked_combinations
WHERE Overall_Rank <= 20
  AND Item_Count >= 5
ORDER BY Overall_Rank;

-- ============================================================
-- VIEW 1: Outlet Performance Summary
-- ============================================================
-- Why a view and not just a query?
-- This summary gets referenced repeatedly across the analysis —
-- by the fat content breakdown, the visibility analysis, and
-- the product-outlet combination query. Rather than repeating
-- the same aggregation logic, we define it once here.
-- Any query that needs outlet-level metrics just selects from
-- this view instead of recomputing from the raw table.
-- ============================================================

CREATE VIEW vw_outlet_performance AS
SELECT
    Outlet_Identifier,
    Outlet_Type,
    Outlet_Size,
    Outlet_Location_Type,
    Outlet_Establishment_Year,
    COUNT(*)                                                        AS Total_Items,
    ROUND(SUM(Total_Sales), 2)                                      AS Total_Sales,
    ROUND(AVG(Total_Sales), 2)                                      AS Avg_Sales_Per_Item,
    ROUND(AVG(Rating), 2)                                           AS Avg_Rating,
    ROUND(AVG(Item_Visibility), 4)                                  AS Avg_Visibility,
    ROUND(
        SUM(Total_Sales) * 100.0 / SUM(SUM(Total_Sales)) OVER (),
    2)                                                              AS Revenue_Pct
FROM blinkit_data
GROUP BY
    Outlet_Identifier,
    Outlet_Type,
    Outlet_Size,
    Outlet_Location_Type,
    Outlet_Establishment_Year;

-- Now any downstream query is clean and readable:
SELECT * FROM vw_outlet_performance ORDER BY Total_Sales DESC;
SELECT * FROM vw_outlet_performance WHERE Outlet_Type = 'Supermarket Type1';
SELECT * FROM vw_outlet_performance WHERE Revenue_Pct > 10;


-- ============================================================
-- VIEW 2: Product Category Benchmarks
-- ============================================================
-- Stores the category-level averages we calculated in the
-- product-outlet CTE query. Having this as a view means
-- any future analysis can benchmark against category averages
-- without rebuilding the calculation from scratch each time.
-- ============================================================

CREATE VIEW vw_category_benchmarks AS
SELECT
    Item_Type,
    COUNT(*)                            AS Total_Records,
    ROUND(SUM(Total_Sales), 2)          AS Category_Total_Sales,
    ROUND(AVG(Total_Sales), 2)          AS Category_Avg_Sales,
    ROUND(MIN(Total_Sales), 2)          AS Min_Sales,
    ROUND(MAX(Total_Sales), 2)          AS Max_Sales,
    ROUND(AVG(Rating), 2)               AS Category_Avg_Rating,
    ROUND(AVG(Item_Visibility), 4)      AS Category_Avg_Visibility
FROM blinkit_data
GROUP BY Item_Type;

-- Usage examples:
SELECT * FROM vw_category_benchmarks ORDER BY Category_Avg_Sales DESC;

-- Find categories where avg sales beat the overall average —
-- clean and readable because the heavy lifting is in the view
SELECT
    Item_Type,
    Category_Avg_Sales
FROM vw_category_benchmarks
WHERE Category_Avg_Sales > (SELECT AVG(Total_Sales) FROM blinkit_data)
ORDER BY Category_Avg_Sales DESC;


-- ============================================================
-- VIEW 3: Underperforming High-Rated Products
-- ============================================================
-- Identifies products with strong ratings but weak sales —
-- a genuine business insight, not just a technical exercise.
-- Built as a view because this is exactly the kind of report
-- a category manager would want to refresh weekly.
-- ============================================================

CREATE VIEW vw_high_rated_underperformers AS
SELECT
    b.Item_Type,
    b.Outlet_Type,
    b.Outlet_Location_Type,
    ROUND(AVG(b.Rating), 2)                                         AS Avg_Rating,
    ROUND(AVG(b.Total_Sales), 2)                                    AS Avg_Sales,
    cb.Category_Avg_Sales,
    ROUND(
        ((AVG(b.Total_Sales) - cb.Category_Avg_Sales)
        / cb.Category_Avg_Sales) * 100
    , 1)                                                            AS Pct_Vs_Category_Avg,
    COUNT(*)                                                        AS Item_Count
FROM blinkit_data b
JOIN vw_category_benchmarks cb
    ON b.Item_Type = cb.Item_Type
GROUP BY
    b.Item_Type,
    b.Outlet_Type,
    b.Outlet_Location_Type,
    cb.Category_Avg_Sales
HAVING
    AVG(b.Rating) >= 4              -- well rated
    AND AVG(b.Total_Sales) < cb.Category_Avg_Sales  -- but underperforming
    AND COUNT(*) >= 5               -- enough records to be meaningful
ORDER BY Pct_Vs_Category_Avg ASC;

-- Usage: surface the worst offenders immediately
SELECT * FROM vw_high_rated_underperformers
WHERE Pct_Vs_Category_Avg < -15
ORDER BY Pct_Vs_Category_Avg ASC;

-- ============================================================
-- PROCEDURE 1: Outlet Type Performance by Location
-- ============================================================
-- Business use case: a regional manager wants to see how
-- outlet types perform specifically in their city tier.
-- Instead of rewriting the query each time, they call this
-- procedure with their location type as the parameter.
--
-- Usage:
--   CALL sp_outlet_performance_by_location('Tier 1');
--   CALL sp_outlet_performance_by_location('Tier 2');
--   CALL sp_outlet_performance_by_location('Tier 3');
-- ============================================================

DELIMITER $$

CREATE PROCEDURE sp_outlet_performance_by_location(
    IN p_location_type VARCHAR(20)
)
BEGIN
    -- Validate input — avoids silent empty results that look
    -- like a data problem rather than a bad parameter
    IF p_location_type NOT IN ('Tier 1', 'Tier 2', 'Tier 3') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid location type. Use: Tier 1, Tier 2, or Tier 3';
    END IF;

    SELECT
        Outlet_Type,
        Outlet_Size,
        COUNT(*)                            AS Item_Count,
        ROUND(SUM(Total_Sales), 2)          AS Total_Sales,
        ROUND(AVG(Total_Sales), 2)          AS Avg_Sales_Per_Item,
        ROUND(AVG(Rating), 2)               AS Avg_Rating,
        ROUND(
            SUM(Total_Sales) * 100.0 /
            SUM(SUM(Total_Sales)) OVER (),
        2)                                  AS Revenue_Pct_Within_Location
    FROM blinkit_data
    WHERE Outlet_Location_Type = p_location_type
    GROUP BY Outlet_Type, Outlet_Size
    ORDER BY Total_Sales DESC;
END$$

DELIMITER ;


-- ============================================================
-- PROCEDURE 2: Product Performance Report by Category
-- ============================================================
-- Business use case: a category manager wants a full health
-- check on their specific product category — sales, ratings,
-- visibility, and how each outlet type performs for that category.
--
-- Usage:
--   CALL sp_category_report('Fruits and Vegetables');
--   CALL sp_category_report('Snack Foods');
--   CALL sp_category_report('Dairy');
-- ============================================================

DELIMITER $$

CREATE PROCEDURE sp_category_report(
    IN p_item_type VARCHAR(50)
)
BEGIN

    -- Block 1: Category-level KPI summary
    -- Gives the headline numbers before drilling into detail
    SELECT
        Item_Type,
        COUNT(*)                            AS Total_Records,
        ROUND(SUM(Total_Sales), 2)          AS Total_Sales,
        ROUND(AVG(Total_Sales), 2)          AS Avg_Sales,
        ROUND(MIN(Total_Sales), 2)          AS Min_Sales,
        ROUND(MAX(Total_Sales), 2)          AS Max_Sales,
        ROUND(AVG(Rating), 2)               AS Avg_Rating,
        ROUND(AVG(Item_Visibility), 4)      AS Avg_Visibility
    FROM blinkit_data
    WHERE Item_Type = p_item_type
    GROUP BY Item_Type;

    -- Block 2: Performance breakdown by outlet type
    -- Shows which outlet format works best for this category
    SELECT
        Outlet_Type,
        Outlet_Location_Type,
        COUNT(*)                            AS Item_Count,
        ROUND(SUM(Total_Sales), 2)          AS Total_Sales,
        ROUND(AVG(Total_Sales), 2)          AS Avg_Sales,
        ROUND(AVG(Rating), 2)               AS Avg_Rating,
        ROUND(
            SUM(Total_Sales) * 100.0 /
            SUM(SUM(Total_Sales)) OVER (),
        2)                                  AS Revenue_Pct
    FROM blinkit_data
    WHERE Item_Type = p_item_type
    GROUP BY Outlet_Type, Outlet_Location_Type
    ORDER BY Total_Sales DESC;

    -- Block 3: Fat content split for this category
    -- Relevant for categories like Dairy and Snack Foods where
    -- Low Fat vs Regular is an active product strategy decision
    SELECT
        Item_Fat_Content,
        COUNT(*)                            AS Item_Count,
        ROUND(SUM(Total_Sales), 2)          AS Total_Sales,
        ROUND(AVG(Total_Sales), 2)          AS Avg_Sales,
        ROUND(AVG(Rating), 2)               AS Avg_Rating
    FROM blinkit_data
    WHERE Item_Type = p_item_type
    GROUP BY Item_Fat_Content;

END$$

DELIMITER ;


-- ============================================================
-- PROCEDURE 3: Sales Threshold Alert
-- ============================================================
-- Business use case: identify product-outlet combinations
-- falling below a minimum sales threshold — useful for
-- weekly restocking and delisting decisions.
-- The threshold is a parameter so it can be adjusted without
-- touching the query logic.
--
-- Usage:
--   CALL sp_below_sales_threshold(100.00);
--   CALL sp_below_sales_threshold(50.00);
-- ============================================================

DELIMITER $$

CREATE PROCEDURE sp_below_sales_threshold(
    IN p_min_sales DECIMAL(10,2)
)
BEGIN
    SELECT
        Item_Type,
        Outlet_Type,
        Outlet_Location_Type,
        COUNT(*)                            AS Item_Count,
        ROUND(AVG(Total_Sales), 2)          AS Avg_Sales,
        ROUND(AVG(Rating), 2)               AS Avg_Rating,
        -- Flag whether low sales correlates with low rating
        -- or is happening despite a good rating (bigger concern)
        CASE
            WHEN AVG(Rating) >= 4 THEN 'High rated — investigate availability'
            WHEN AVG(Rating) >= 3 THEN 'Average rated — may need promotion'
            ELSE                       'Low rated — review product quality'
        END                                 AS Diagnosis
    FROM blinkit_data
    GROUP BY Item_Type, Outlet_Type, Outlet_Location_Type
    HAVING AVG(Total_Sales) < p_min_sales
       AND COUNT(*) >= 3
    ORDER BY Avg_Sales ASC;
END$$

DELIMITER ;


-- ============================================================
-- QUICK REFERENCE: How to manage views and procedures
-- ============================================================

-- Check existing views
SHOW FULL TABLES IN blinkit_project WHERE TABLE_TYPE = 'VIEW';

-- Check existing procedures
SHOW PROCEDURE STATUS WHERE Db = 'blinkit_project';

-- See the definition of a view or procedure
SHOW CREATE VIEW vw_outlet_performance;
SHOW CREATE PROCEDURE sp_category_report;

-- Drop and recreate if you need to modify them
DROP VIEW IF EXISTS vw_outlet_performance;
DROP PROCEDURE IF EXISTS sp_category_report;

-- Export-ready flat table — everything Tableau needs in one place.
-- MySQL Workbench: run this, then click the export icon in the results grid
-- and save as blinkit_dashboard_data.csv

SELECT
    Item_Type,
    Item_Fat_Content,
    Outlet_Identifier,
    Outlet_Type,
    Outlet_Size,
    Outlet_Location_Type,
    Outlet_Establishment_Year,
    Item_Visibility,
    Item_Weight,
    Total_Sales,
    Rating
FROM blinkit_data;
