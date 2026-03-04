create database blinkit_project;
use blinkit_project;

show variables like "secure%";

# composite primary key
CREATE TABLE blinkit_data (
    Item_Fat_Content VARCHAR(20),
    Item_Identifier VARCHAR(20),
    Item_Type VARCHAR(50),
    Outlet_Establishment_Year INT,
    Outlet_Identifier VARCHAR(20),
    Outlet_Location_Type VARCHAR(20),
    Outlet_Size VARCHAR(20),
    Outlet_Type VARCHAR(30),
    Item_Visibility DECIMAL(10,6),
    Item_Weight DECIMAL(5,2),
    Total_Sales DECIMAL(10,2),
    Rating DECIMAL(3,2),
    PRIMARY KEY (Item_Identifier, Outlet_Identifier)
);

# null values are replaced with NULL
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
Item_Weight = NULLIF(@Item_Weight, ''),
Total_Sales = NULLIF(@Total_Sales, ''),
Rating = NULLIF(@Rating, '');

select * from blinkit_data;

select count(*) from blinkit_data; #8523 rows

# data cleaning

#Error Code: 1175. You are using safe update mode...
SET SQL_SAFE_UPDATES = 0;

# standardizing  column
update blinkit_data set Item_Fat_Content=
case
when Item_Fat_Content in ('LF','low fat') then 'Low Fat'
when Item_Fat_Content ='reg' then 'Regular'
else Item_Fat_Content end;

# to check 
SELECT DISTINCT Item_Fat_Content FROM blinkit_data;

# A. KPI
# 1. Total Sales
select cast(sum(total_sales)/1000000 as decimal(10,2)) as "Total Sales in million" from blinkit_data;

# 2. Average Sales
select cast(avg(total_sales) as decimal(10,0)) as "Average Sales" from blinkit_data;

# 3. NO OF ITEMS
select count(*) as "No of Orders" from blinkit_data;

# 4. AVG RATING
select cast(avg(Rating) as decimal(10,1)) as Avg_Rating from blinkit_data;

# B. Business questions
# 1. Total Sales by Fat Content:
select Item_Fat_Content, cast(sum(Total_Sales) as decimal(10,2)) as Total_Sales
from blinkit_data group by Item_Fat_Content;

# 2. Total Sales by Item Type
select Item_Type, cast(sum(Total_Sales) as decimal(10,2)) as Total_Sales
from blinkit_data group by Item_Type order by Total_Sales desc;

# 3. Fat Content by Outlet for Total Sales
SELECT 
    Outlet_Location_Type,
    SUM(CASE WHEN Item_Fat_Content = 'Low Fat' THEN Total_Sales ELSE 0 END) AS Low_Fat,
    SUM(CASE WHEN Item_Fat_Content = 'Regular' THEN Total_Sales ELSE 0 END) AS Regular
FROM blinkit_data
GROUP BY Outlet_Location_Type
ORDER BY Outlet_Location_Type;

# 4. Percentage of Sales by Outlet Size
select 
    Outlet_Size,
    round(sum(Total_Sales), 2) as Total_Sales,
    round(
        sum(Total_Sales) * 100 / 
        (select sum(Total_Sales) from blinkit_data),2) as Sales_Percentage
from blinkit_data
group by Outlet_Size
order by Total_Sales desc;

# 5. Top & Bottom Performing Products
SELECT 
    Item_Type,
    ROUND(SUM(Total_Sales),2) AS Total_Sales,
    RANK() OVER (ORDER BY SUM(Total_Sales) DESC) AS Sales_Rank
FROM blinkit_data
GROUP BY Item_Type;

# 6. Outlet Performance Growth Analysis
# Then answer:Are newer outlets better?Do older outlets generate more revenue?That’s strategy thinking.
# Outlet Establishment Performance & Growth Analysis
SELECT 
    Outlet_Establishment_Year,
    COUNT(DISTINCT Outlet_Identifier) AS No_Of_Outlets,
    ROUND(SUM(Total_Sales), 2) AS Total_Sales,
    ROUND(AVG(Total_Sales), 0) AS Avg_Sales_Per_Record,
    ROUND(SUM(Total_Sales) / COUNT(DISTINCT Outlet_Identifier), 2) 
        AS Sales_Per_Outlet
FROM blinkit_data
GROUP BY Outlet_Establishment_Year
ORDER BY Outlet_Establishment_Year;

# 7. Rating vs Sales Correlation
SELECT 
    CASE 
        WHEN Rating >= 4 THEN 'High Rated'
        WHEN Rating BETWEEN 3 AND 3.99 THEN 'Medium Rated'
        ELSE 'Low Rated'
    END AS Rating_Category,
    ROUND(SUM(Total_Sales),2) AS Total_Sales
FROM blinkit_data
GROUP BY Rating_Category;

# 8. Outlet Sales Contribution % with All Metrics by Outlet Type:
SELECT 
    Outlet_Type,
    ROUND(AVG(Total_Sales), 0) AS Avg_Sales,
    COUNT(*) AS No_Of_Items,
    ROUND(AVG(Rating), 2) AS Avg_Rating,
    ROUND(AVG(Item_Visibility), 2) AS Avg_Item_Visibility,
    ROUND(SUM(Total_Sales), 2) AS Total_Sales,
    ROUND(
        SUM(Total_Sales) * 100.0 / SUM(SUM(Total_Sales)) OVER (),
    2) AS Revenue_Contribution_Percentage
FROM blinkit_data
GROUP BY Outlet_Type
ORDER BY Revenue_Contribution_Percentage DESC;

# 9. Top Performing Outlet Within Each Location (Partition Ranking)
SELECT *
FROM (
    SELECT 
        Outlet_Location_Type,
        Outlet_Type,
        ROUND(SUM(Total_Sales),2) AS Total_Sales,
        RANK() OVER (
            PARTITION BY Outlet_Location_Type 
            ORDER BY SUM(Total_Sales) DESC
        ) AS Location_Rank
    FROM blinkit_data
    GROUP BY Outlet_Location_Type, Outlet_Type
) ranked_outlets
WHERE Location_Rank = 1;

# 10. Visibility Impact on Sales (Bucket Analysis)
SELECT 
    CASE 
        WHEN Item_Visibility < 0.05 THEN 'Low Visibility'
        WHEN Item_Visibility BETWEEN 0.05 AND 0.15 THEN 'Medium Visibility'
        ELSE 'High Visibility'
    END AS Visibility_Category,
    ROUND(SUM(Total_Sales),2) AS Total_Sales,
    ROUND(AVG(Total_Sales),2) AS Avg_Sales
FROM blinkit_data
GROUP BY Visibility_Category
ORDER BY Total_Sales DESC;


