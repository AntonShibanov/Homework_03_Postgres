-- Создаем таблицы
CREATE TABLE customer (
    customer_id int PRIMARY KEY,
    first_name text,
    last_name text,
    gender text,
    DOB date,
    job_title text,
    job_industry_category text,
    wealth_segment text,
    deceased_indicator text,
    owns_car text,
    address text,
    postcode int,
    state text,
    country text,
    property_valuation int
);
CREATE TABLE product (
    product_id int PRIMARY KEY,
    brand text,
    product_line text,
    product_class text,
    product_size text,
    list_price float,
    standard_cost float
);
CREATE TABLE orders (
    order_id int PRIMARY KEY,
    customer_id int not NULL,
    order_date date,
    online_order text,
    order_status text
);
CREATE TABLE order_items (
    order_item_id int PRIMARY KEY,
    order_id int not NULL,
    product_id int not NULL,
    quantity int,
    item_list_price_at_sale float,
    item_standard_cost_at_sale float
);

---------------------------------------------------------------------------------------------------------------------------
-- 1. Вывести распределение (количество) клиентов по сферам деятельности, отсортировав результат по убыванию количества.
SELECT 
    job_industry_category,
    COUNT(*) as customer_count
FROM customer
GROUP BY job_industry_category
ORDER BY customer_count DESC;

-- 2. Найти общую сумму дохода (list_price*quantity) по всем подтвержденным заказам за каждый месяц по сферам деятельности клиентов. 
--    Отсортировать результат по году, месяцу и сфере деятельности.
SELECT 
    EXTRACT(YEAR FROM o.order_date) AS year,
    EXTRACT(MONTH FROM o.order_date) AS month,
    c.job_industry_category,
    SUM(oi.item_list_price_at_sale * oi.quantity) AS total_income
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN customer c ON o.customer_id = c.customer_id
WHERE o.order_status = 'Approved'
GROUP BY year, month, c.job_industry_category
ORDER BY year, month, c.job_industry_category;

-- 3. Вывести количество уникальных онлайн-заказов для всех брендов в рамках подтвержденных заказов клиентов из сферы IT. 
--    Включить бренды, у которых нет онлайн-заказов от IT-клиентов, — для них должно быть указано количество 0.
SELECT 
    p.brand,
    COUNT(DISTINCT CASE 
        WHEN o.online_order = 'True' AND c.job_industry_category = 'IT' AND o.order_status = 'Approved' 
        THEN o.order_id 
    END) AS online_orders_count
FROM product p
LEFT JOIN order_items oi ON p.product_id = oi.product_id
LEFT JOIN orders o ON oi.order_id = o.order_id
LEFT JOIN customer c ON o.customer_id = c.customer_id AND c.job_industry_category = 'IT'
GROUP BY p.brand
ORDER BY online_orders_count DESC;

-- 4. Найти по всем клиентам: сумму всех заказов (общего дохода), максимум, минимум и количество заказов, а также среднюю сумму заказа по каждому клиенту. 
-- Отсортировать результат по убыванию суммы всех заказов и количества заказов. Выполнить двумя способами: используя только GROUP BY и используя только оконные функции. 
-- Сравнить результат.

-- Через GROUP BY
SELECT 
    c.customer_id,
    c.first_name,
    c.last_name,
    SUM(oi.item_list_price_at_sale * oi.quantity) AS total_income,
    MAX(oi.item_list_price_at_sale * oi.quantity) AS max_order_value,
    MIN(oi.item_list_price_at_sale * oi.quantity) AS min_order_value,
    COUNT(o.order_id) AS orders_count,
    AVG(oi.item_list_price_at_sale * oi.quantity) AS avg_order_value
FROM customer c
LEFT JOIN orders o ON c.customer_id = o.customer_id
LEFT JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY total_income DESC NULLS LAST, orders_count DESC NULLS LAST;

-- Через оконные функции
SELECT DISTINCT
    c.customer_id,
    c.first_name,
    c.last_name,
    SUM(oi.item_list_price_at_sale * oi.quantity) OVER (PARTITION BY c.customer_id) AS total_income,
    MAX(oi.item_list_price_at_sale * oi.quantity) OVER (PARTITION BY c.customer_id) AS max_order_value,
    MIN(oi.item_list_price_at_sale * oi.quantity) OVER (PARTITION BY c.customer_id) AS min_order_value,
    COUNT(o.order_id) OVER (PARTITION BY c.customer_id) AS orders_count,
    AVG(oi.item_list_price_at_sale * oi.quantity) OVER (PARTITION BY c.customer_id) AS avg_order_value
FROM customer c
LEFT JOIN orders o ON c.customer_id = o.customer_id
LEFT JOIN order_items oi ON o.order_id = oi.order_id
ORDER BY total_income DESC NULLS LAST, orders_count DESC NULLS LAST;

-- 5. Найти имена и фамилии клиентов с топ-3 минимальной и топ-3 максимальной суммой транзакций за весь период (учесть клиентов, у которых нет заказов, приняв их сумму транзакций за 0).
WITH customer_totals AS (
    SELECT 
        c.customer_id,
        c.first_name,
        c.last_name,
        COALESCE(SUM(oi.item_list_price_at_sale * oi.quantity), 0) AS total_transaction
    FROM customer c
    LEFT JOIN orders o ON c.customer_id = o.customer_id
    LEFT JOIN order_items oi ON o.order_id = oi.order_id
    GROUP BY c.customer_id, c.first_name, c.last_name
),
max_ranks AS (
    SELECT 
        first_name,
        last_name,
        total_transaction,
        RANK() OVER (ORDER BY total_transaction DESC) as rank_max
    FROM customer_totals
),
min_ranks AS (
    SELECT 
        first_name,
        last_name,
        total_transaction,
        RANK() OVER (ORDER BY total_transaction ASC) as rank_min
    FROM customer_totals
)
SELECT first_name, last_name, total_transaction, 'max' as type
FROM max_ranks
WHERE rank_max <= 3
UNION ALL
SELECT first_name, last_name, total_transaction, 'min' as type
FROM min_ranks
WHERE rank_min <= 3
ORDER BY type, total_transaction DESC;

-- 6. Вывести только вторые транзакции клиентов (если они есть) с помощью оконных функций. Если у клиента меньше двух транзакций, он не должен попасть в результат.
WITH ordered_orders AS (
    SELECT 
        o.customer_id,
        o.order_id,
        o.order_date,
        ROW_NUMBER() OVER (PARTITION BY o.customer_id ORDER BY o.order_date, o.order_id) as order_rank
    FROM orders o
)
SELECT 
    oo.customer_id,
    c.first_name,
    c.last_name,
    oo.order_id,
    oo.order_date
FROM ordered_orders oo
JOIN customer c ON oo.customer_id = c.customer_id
WHERE oo.order_rank = 2;

-- 7. Вывести имена, фамилии и профессии клиентов, а также длительность максимального интервала (в днях) между двумя последовательными заказами. 
--    Исключить клиентов, у которых только один или меньше заказов.
WITH order_intervals AS (
    SELECT 
        o.customer_id,
        o.order_date,
        LAG(o.order_date) OVER (PARTITION BY o.customer_id ORDER BY o.order_date) as prev_order_date,
        o.order_date - LAG(o.order_date) OVER (PARTITION BY o.customer_id ORDER BY o.order_date) as interval_days
    FROM orders o
),
max_intervals AS (
    SELECT 
        customer_id,
        MAX(interval_days) as max_interval_days
    FROM order_intervals
    WHERE interval_days IS NOT NULL
    GROUP BY customer_id
    HAVING COUNT(*) >= 1
)
SELECT 
    c.first_name,
    c.last_name,
    c.job_title,
    mi.max_interval_days
FROM max_intervals mi
JOIN customer c ON mi.customer_id = c.customer_id
ORDER BY mi.max_interval_days DESC;

-- 8. Найти топ-5 клиентов (по общему доходу) в каждом сегменте благосостояния (wealth_segment). Вывести имя, фамилию, сегмент и общий доход. 
--    Если в сегменте менее 5 клиентов, вывести всех.
WITH customer_segment_income AS (
    SELECT 
        c.customer_id,
        c.first_name,
        c.last_name,
        c.wealth_segment,
        COALESCE(SUM(oi.item_list_price_at_sale * oi.quantity), 0) AS total_income
    FROM customer c
    LEFT JOIN orders o ON c.customer_id = o.customer_id
    LEFT JOIN order_items oi ON o.order_id = oi.order_id
    GROUP BY c.customer_id, c.first_name, c.last_name, c.wealth_segment
),
ranked_customers AS (
    SELECT 
        *,
        DENSE_RANK() OVER (PARTITION BY wealth_segment ORDER BY total_income DESC) as income_rank
    FROM customer_segment_income
)
SELECT 
    first_name,
    last_name,
    wealth_segment,
    total_income,
    income_rank
FROM ranked_customers
WHERE income_rank <= 5
ORDER BY wealth_segment, income_rank;