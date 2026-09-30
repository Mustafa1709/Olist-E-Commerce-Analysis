/* -------------------------------------------------------------------
   OLIST E-COMMERCE ANALYSIS  |  PostgreSQL
   Tables used: orders, payments, customers, order_items, products,
                sellers, reviews

   Sections
   0. Setup
   1. Data quality checks
   2. Basic exploration
   3. Revenue and order trends
   4. Customer analysis
   5. Product and seller analysis
   6. Delivery and reviews
   7. Window functions
   8. CTEs and subqueries

   Note: in Olist, customer_id changes with every order. The real person
   is customer_unique_id, so anything about "a customer" (repeat buying,
   spend, ranking) joins the customers table and uses customer_unique_id.
   --------------------------------------------------------------------- */



/* 
    SETUP  
    */

-- the timestamp came in as text, so I made a proper timestamp column
ALTER TABLE orders
ADD COLUMN purchase_timestamp TIMESTAMP;

UPDATE orders
SET purchase_timestamp = order_purchase_timestamp::timestamp;



/* 
   1. DATA QUALITY CHECKS
   Checking the data before analysing it
  */

-- 1.1 how many rows does each table have
select 'orders' as table_name, count(*) as total_rows from orders
union all select 'payments', count(*) from payments
union all select 'customers', count(*) from customers
union all select 'order_items', count(*) from order_items
union all select 'products', count(*) from products
union all select 'sellers', count(*) from sellers
union all select 'reviews', count(*) from reviews;


-- 1.2 is order_id really unique in the orders table
select count(*) as total_rows,
count(distinct order_id) as unique_orders,
count(*) - count(distinct order_id) as duplicate_rows
from orders;


-- 1.3 nulls in the important order columns
select
count(*) filter (where order_id is null) as null_order_id,
count(*) filter (where customer_id is null) as null_customer_id,
count(*) filter (where order_purchase_timestamp is null) as null_purchase_time,
count(*) filter (where order_delivered_customer_date is null) as null_delivered_date,
count(*) filter (where delivery_days is null) as null_delivery_days
from orders;


-- 1.4 orders with no delivery date, split by status
-- (cancelled / unavailable ones are fine, a "delivered" one with no date is not)
select order_status, count(*) as orders_without_delivery_date
from orders
where order_delivered_customer_date is null
group by order_status
order by orders_without_delivery_date desc;


-- 1.5 orders that have no payment row
select count(*) as orders_without_payment
from orders as a
left join payments as b
on a.order_id = b.order_id
where b.order_id is null;


-- 1.6 payments and order items that point to an order that doesn't exist
select count(*) as payments_without_order
from payments as a
left join orders as b
on a.order_id = b.order_id
where b.order_id is null;

select count(*) as items_without_order
from order_items as a
left join orders as b
on a.order_id = b.order_id
where b.order_id is null;


-- 1.7 duplicate review ids (one review_id can show up more than once)
select count(*) as total_rows,
count(distinct review_id) as unique_reviews,
count(*) - count(distinct review_id) as duplicate_review_rows
from reviews;


-- 1.8 review scores should only be 1 to 5
select review_score, count(*) as total_reviews
from reviews
group by review_score
order by review_score;


-- 1.9 weird values in money and delivery columns
select count(*) filter (where payment_value <= 0) as zero_or_negative_payments,
max(payment_value) as biggest_payment
from payments;

select count(*) filter (where price <= 0) as zero_or_negative_price,
count(*) filter (where freight_value < 0) as negative_freight
from order_items;

select count(*) filter (where delivery_days < 0) as negative_delivery_days,
max(delivery_days) as longest_delivery_days
from orders;


-- 1.10 customer_id vs customer_unique_id
-- customer_id is one per order, unique id is the real person
select count(distinct customer_id) as customer_ids,
count(distinct customer_unique_id) as unique_customers
from customers;



/* 
   2. BASIC EXPLORATION
    */

-- 2.1 quick look at the data
select * from orders limit 10;


-- 2.2 total orders
select count(order_id)
from orders;


-- 2.3 orders by status
select order_status,count(order_id) from orders
group by order_status;


-- 2.4 average delivery days by status
select order_status,avg(delivery_days) as Average_delivery_days from orders
group by order_status;


-- 2.5 orders by year
select purchased_year,count(order_id) from orders
group by purchased_year;



/* 
   3. REVENUE AND ORDER TRENDS
    */

-- 3.1 which months get the most orders (month name only, years combined)
select purchased_month,count(order_id) as Total_Orders
from orders
group by purchased_month
order by Total_Orders desc;


-- 3.2 orders per month in real time order (year + month)
-- the month name sorts alphabetically, so I truncate the date instead
select date_trunc('month', order_purchase_timestamp::timestamp) as order_month,
count(distinct order_id) as total_orders
from orders
group by 1
order by 1;


-- 3.3 revenue by year
select a.purchased_year,sum(b.payment_value)  from orders as a
inner join payments as b
on a.order_id = b.order_id
group  by a.purchased_year;


-- 3.4 revenue by weekday vs weekend
select day_type,sum(b.payment_value)as Total_revenue from orders as a
join payments as b
on a.order_id = b.order_id
group by day_type;


-- 3.5 revenue by day of the week
select purchased_weekday,sum(b.payment_value)as Total_revenue from orders as a
join payments as b
on a.order_id = b.order_id
group by purchased_weekday
order by Total_revenue desc;


-- 3.6 revenue by hour of the day
select purchased_hour,sum(b.payment_value)as Total_revenue from orders as a
join payments as b
on a.order_id = b.order_id
group by purchased_hour
order by Total_revenue desc;


-- 3.7 orders by status (total orders per status)
select order_status,count(order_id)as Total_orders from orders
group by order_status;


-- 3.8 revenue and share by payment type
select payment_type,
count(distinct order_id) as orders,
round(sum(payment_value)::numeric,2) as revenue,
round((sum(payment_value) * 100.0 / sum(sum(payment_value)) over ())::numeric,2) as revenue_pct
from payments
group by payment_type
order by revenue desc;


-- 3.9 how many installments people choose
select payment_installments,
count(distinct order_id) as orders,
round(sum(payment_value)::numeric,2) as revenue
from payments
group by payment_installments
order by payment_installments;


-- 3.10 average order value (total revenue / distinct orders)
select round((sum(b.payment_value) / count(distinct a.order_id))::numeric,2) as average_order_value
from orders as a
join payments as b
on a.order_id = b.order_id;



/* 
   4. CUSTOMER ANALYSIS
    */

-- 4.1 orders vs actual unique customers
select count(distinct a.order_id) as total_orders,
count(distinct b.customer_unique_id) as unique_customers
from orders as a
join customers as b
on a.customer_id = b.customer_id;


-- 4.2 repeat customer rate
with per_person as (
select b.customer_unique_id, count(distinct a.order_id) as total_orders
from orders as a
join customers as b
on a.customer_id = b.customer_id
group by b.customer_unique_id
)
select count(*) as customers,
count(*) filter (where total_orders > 1) as repeat_customers,
round(100.0 * count(*) filter (where total_orders > 1) / count(*),2) as repeat_rate_pct
from per_person;


-- 4.3 customers by city (unique people, not order ids)
select customers."Customer_City", count(distinct customer_unique_id) as Total_Customers from customers
group by customers."Customer_City"
order by Total_Customers desc;


-- 4.4 customers and orders by state
select b.customer_state,
count(distinct b.customer_unique_id) as customers,
count(distinct a.order_id) as orders
from orders as a
join customers as b
on a.customer_id = b.customer_id
group by b.customer_state
order by orders desc;


-- 4.5 how many orders does each customer place (1, 2, 3...)
with per_person as (
select b.customer_unique_id, count(distinct a.order_id) as total_orders
from orders as a
join customers as b
on a.customer_id = b.customer_id
group by b.customer_unique_id
)
select total_orders, count(*) as customers
from per_person
group by total_orders
order by total_orders;


-- 4.6 top 10 customers by total spend
select b.customer_unique_id, round(sum(c.payment_value)::numeric,2) as total_spent
from orders as a
join customers as b
on a.customer_id = b.customer_id
join payments as c
on a.order_id = c.order_id
group by b.customer_unique_id
order by total_spent desc
limit 10;



/* 
   5. PRODUCT AND SELLER ANALYSIS
    */

-- 5.1 top 10 categories by revenue (price + freight from order_items)
-- I use order_items here and not payments. Joining items to payments
-- repeats the payment rows for every item and inflates the revenue.
select a."Product_Category_Name",
round(sum(b.price + b.freight_value)::numeric,2) as total_revenue
from products as a
join order_items as b
on a.product_id = b.product_id
group by a."Product_Category_Name"
order by total_revenue desc
limit 10;


-- 5.2 percentage contribution of each category to total revenue
select a."Product_Category_Name",
round(sum(b.price + b.freight_value)::numeric,2) as total_revenue,
round((sum(b.price + b.freight_value) * 100.0 /
sum(sum(b.price + b.freight_value)) over ())::numeric,2) as revenue_percentage
from products as a
join order_items as b
on a.product_id = b.product_id
group by a."Product_Category_Name"
order by total_revenue desc;


-- 5.3 top 10 categories by number of items sold
select a."Product_Category_Name", count(b.order_item_id) as items_sold
from products as a
join order_items as b
on a.product_id = b.product_id
group by a."Product_Category_Name"
order by items_sold desc
limit 10;


-- 5.4 categories with the highest average freight (at least 100 items sold)
select a."Product_Category_Name",
round(avg(b.freight_value)::numeric,2) as avg_freight,
count(*) as items_sold
from products as a
join order_items as b
on a.product_id = b.product_id
group by a."Product_Category_Name"
having count(*) >= 100
order by avg_freight desc
limit 10;


-- 5.5 top 10 sellers by revenue
select seller_id,
count(distinct order_id) as orders,
round(sum(price)::numeric,2) as revenue
from order_items
group by seller_id
order by revenue desc
limit 10;


-- 5.6 orders by seller state
select a."Seller_State", count(distinct b.order_id) as orders
from sellers as a
join order_items as b
on a.seller_id = b.seller_id
group by a."Seller_State"
order by orders desc;



/* 
   6. DELIVERY AND REVIEWS
    */

-- 6.1 on time vs late deliveries
select
case when order_delivered_customer_date::timestamp <= order_estimated_delivery_date::timestamp
then 'On time' else 'Late' end as delivery_status,
count(*) as orders,
round(100.0 * count(*) / sum(count(*)) over (),2) as pct
from orders
where order_status = 'delivered'
group by 1;


-- 6.2 the 10 slowest states (states with at least 50 delivered orders)
select b.customer_state,
round(avg(a.delivery_days)::numeric,1) as avg_delivery_days,
count(distinct a.order_id) as orders
from orders as a
join customers as b
on a.customer_id = b.customer_id
where a.order_status = 'delivered'
group by b.customer_state
having count(distinct a.order_id) >= 50
order by avg_delivery_days desc
limit 10;


-- 6.3 review score split (5 star, positive, low)
select count(*) as total_reviews,
round(avg(review_score)::numeric,2) as avg_score,
round(100.0 * count(*) filter (where review_score = 5) / count(*),2) as five_star_pct,
round(100.0 * count(*) filter (where review_score >= 4) / count(*),2) as positive_pct,
round(100.0 * count(*) filter (where review_score <= 2) / count(*),2) as low_pct
from reviews;


-- 6.4 does slow delivery lower the review score?
select case when o.delivery_days < 5 then '1. Under 5 days'
when o.delivery_days <= 7 then '2. 5-7 days'
when o.delivery_days <= 9 then '3. 8-9 days'
when o.delivery_days <= 11 then '4. 10-11 days'
else '5. 12+ days' end as delivery_bucket,
count(distinct o.order_id) as orders,
round(avg(r.review_score)::numeric,2) as avg_review
from orders as o
join reviews as r
on r.order_id = o.order_id
where o.order_status = 'delivered'
group by 1
order by 1;


-- 6.5 average review for on time vs late orders
select
case when o.order_delivered_customer_date::timestamp <= o.order_estimated_delivery_date::timestamp
then 'On time' else 'Late' end as delivery_status,
count(distinct o.order_id) as orders,
round(avg(r.review_score)::numeric,2) as avg_review
from orders as o
join reviews as r
on r.order_id = o.order_id
where o.order_status = 'delivered'
group by 1;



/* 
   7. WINDOW FUNCTIONS
    */

-- 7.1 ROW_NUMBER: purchase number of each order for a customer
-- partitioned by customer_unique_id, if I use customer_id every order
-- is number 1 because customer_id is different for each order
select b.customer_unique_id,
a.order_id,
a.order_purchase_timestamp,
row_number() over (
partition by b.customer_unique_id
order by a.order_purchase_timestamp::timestamp
) as purchase_number
from orders as a
join customers as b
on a.customer_id = b.customer_id;


-- 7.2 RANK: customers ranked by total amount spent
select b.customer_unique_id,sum(c.payment_value) as Total_Amount,
rank()over(
order by sum(c.payment_value) Desc
) as Customer_Rank
from orders as a
join customers as b
on a.customer_id = b.customer_id
join payments as c
on a.order_id = c.order_id
group by b.customer_unique_id
order by Total_Amount desc;


-- 7.3 RANK with PARTITION BY: sellers ranked by products sold in each year
with hipen as(
select a.seller_id,b.shipping_year,count(b.product_id) as Total_products_sold,
RANK() OVER (
    PARTITION BY shipping_year
    ORDER BY count(b.product_id) DESC
) As Seller_Rank_by_total_products_sold
from sellers as a
join order_items as b
on a.seller_id  = b.seller_id
group by a.seller_id,b.shipping_year
order by Total_products_sold desc,b.shipping_year asc
)
select * from hipen
where shipping_year = 2018;


-- 7.4 running total of revenue by month
-- month is a real date here so the running total follows time order
with monthly as (
select date_trunc('month', a.order_purchase_timestamp::timestamp) as order_month,
sum(b.payment_value) as monthly_revenue
from orders as a
join payments as b
on a.order_id = b.order_id
group by 1
)
select order_month,
monthly_revenue,
sum(monthly_revenue) over (order by order_month) as running_revenue
from monthly
order by order_month;


-- 7.5 running total of orders by month
with monthly as (
select date_trunc('month', order_purchase_timestamp::timestamp) as order_month,
count(order_id) as monthly_orders_count
from orders
group by 1
)
select order_month,
monthly_orders_count,
sum(monthly_orders_count) over (order by order_month) as total_count
from monthly
order by order_month;


-- 7.6 month over month growth in orders (LAG)
with monthly as (
select date_trunc('month', order_purchase_timestamp::timestamp) as order_month,
count(distinct order_id) as orders
from orders
group by 1
)
select order_month,
orders,
lag(orders) over (order by order_month) as previous_month,
round(100.0 * (orders - lag(orders) over (order by order_month))
/ nullif(lag(orders) over (order by order_month),0),1) as growth_pct
from monthly
order by order_month;


-- 7.7 LAG: how much each order differs from the customer's previous order
select b.customer_unique_id,c.payment_value,
lag(c.payment_value) over (partition by b.customer_unique_id
order by a.order_purchase_timestamp::timestamp asc ) as Previous_Order_Value,
 c.payment_value -
    LAG(c.payment_value) OVER (
        PARTITION BY b.customer_unique_id
        ORDER BY a.order_purchase_timestamp::timestamp
    ) AS change_from_previous
from orders as a
join customers as b
on a.customer_id = b.customer_id
join payments as c
on a.order_id = c.order_id;


-- 7.8 LAG: days between two purchases of the same customer
select
    b.customer_unique_id,
    a.order_id,
    a.order_purchase_timestamp,

    LAG(a.order_purchase_timestamp::timestamp) OVER (
        PARTITION BY b.customer_unique_id
        ORDER BY a.order_purchase_timestamp::timestamp
    ) AS previous_purchase_date,

    EXTRACT(
        DAY FROM
        a.order_purchase_timestamp::timestamp
        - LAG(a.order_purchase_timestamp::timestamp) OVER (
            PARTITION BY b.customer_unique_id
            ORDER BY a.order_purchase_timestamp::timestamp
        )
    ) AS days_between_purchases

from orders as a
join customers as b
on a.customer_id = b.customer_id
order by b.customer_unique_id, a.order_purchase_timestamp::timestamp;


-- 7.9 NTILE: split customers into 4 groups by spend
-- shows how much of the revenue comes from the top group
with spend as (
select b.customer_unique_id, sum(c.payment_value) as total_spent
from orders as a
join customers as b
on a.customer_id = b.customer_id
join payments as c
on a.order_id = c.order_id
group by b.customer_unique_id
),
grouped as (
select customer_unique_id, total_spent,
ntile(4) over (order by total_spent desc) as spend_quartile
from spend
)
select spend_quartile,
count(*) as customers,
round(sum(total_spent)::numeric,2) as revenue,
round(avg(total_spent)::numeric,2) as avg_spend
from grouped
group by spend_quartile
order by spend_quartile;


-- 7.10 top 3 categories by revenue in every customer state
with category_state as (
select c.customer_state,
p."Product_Category_Name" as category,
sum(oi.price) as revenue
from order_items as oi
join orders as o
on o.order_id = oi.order_id
join customers as c
on c.customer_id = o.customer_id
join products as p
on p.product_id = oi.product_id
group by c.customer_state, p."Product_Category_Name"
),
ranked as (
select *,
row_number() over (partition by customer_state order by revenue desc) as rn
from category_state
)
select customer_state, category, round(revenue::numeric,2) as revenue, rn
from ranked
where rn <= 3
order by customer_state, rn;



/*
   8. CTEs AND SUBQUERIES
   */

-- 8.1 DENSE_RANK: customers with the most reviews
with customer_reviews as (
select a.customer_unique_id,Count(c.review_id)as Total_Reviews ,
dense_rank()over(order by count(c.review_id)Desc) as Rank_by_review_count
from customers as a
join orders  as b
on a.customer_id = b.customer_id
join reviews as c
on b.order_id=c.order_id
group by a.customer_unique_id
order by Total_Reviews desc
)
select * from
customer_reviews
where rank_by_review_count = 1;


-- 8.2 cities that earn more than the average city (CTE + subquery)
with Customer_City_Revenue as(
select a."Customer_City",sum(c.payment_value) as Total_Revenue from customers as a
join orders as b
on a.customer_id = b.customer_id
join payments as c
on b.order_id = c.order_id
group by a."Customer_City"
order by Total_Revenue  desc
)
select "Customer_City" , Total_Revenue from Customer_City_Revenue
where Total_Revenue > (select avg(Total_Revenue) from Customer_City_Revenue)
order by Total_Revenue Desc;


-- 8.3 sellers whose revenue is above the average seller
with seller_revenue as (
select seller_id, sum(price) as revenue
from order_items
group by seller_id
)
select seller_id, round(revenue::numeric,2) as revenue
from seller_revenue
where revenue > (select avg(revenue) from seller_revenue)
order by revenue desc;