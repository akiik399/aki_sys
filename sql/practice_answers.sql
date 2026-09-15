-- =====================================================
-- practice_db 练习题参考答案
-- 先自己做,做完再对照！
-- =====================================================
USE practice_db;

-- 1. 查询所有客户
SELECT * FROM customers;

-- 2. 数码类商品,按单价降序
SELECT product_name, unit_price
FROM products
WHERE category = '数码'
ORDER BY unit_price DESC;

-- 3. 每个分类的商品数
SELECT category, COUNT(*) AS cnt
FROM products
GROUP BY category;

-- 4. 单价 100~500 的商品
SELECT product_name, unit_price
FROM products
WHERE unit_price BETWEEN 100 AND 500;

-- 5. 已完成订单数
SELECT COUNT(*) AS cnt
FROM orders
WHERE status = '已完成';

-- 6. 每个客户的订单数(含 0 单客户)
SELECT c.customer_name, COUNT(o.order_id) AS order_cnt
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.customer_name
ORDER BY order_cnt DESC;

-- 7. 每张订单的客户/日期/状态
SELECT o.order_id, c.customer_name, o.order_date, o.status
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
ORDER BY o.order_id;

-- 8. 每张订单总金额
SELECT o.order_id,
       SUM(oi.quantity * oi.unit_price) AS total_amount
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY o.order_id
ORDER BY o.order_id;

-- 9. 消费总额最高的客户
SELECT c.customer_name,
       SUM(oi.quantity * oi.unit_price) AS grand_total
FROM customers c
JOIN orders o        ON o.customer_id  = c.customer_id
JOIN order_items oi  ON oi.order_id    = o.order_id
GROUP BY c.customer_id, c.customer_name
ORDER BY grand_total DESC
LIMIT 1;

-- 10. 从未下过单的客户(NOT EXISTS 写法)
SELECT c.customer_name
FROM customers c
WHERE NOT EXISTS (
    SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id
);

-- 10b. 等价写法: 左连接取 NULL
SELECT c.customer_name
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
WHERE o.order_id IS NULL;

-- 11. 平均每单金额 > 300 的客户
SELECT c.customer_name,
       SUM(oi.quantity * oi.unit_price) / COUNT(DISTINCT o.order_id) AS avg_per_order
FROM customers c
JOIN orders o        ON o.customer_id  = c.customer_id
JOIN order_items oi  ON oi.order_id    = o.order_id
GROUP BY c.customer_id, c.customer_name
HAVING avg_per_order > 300
ORDER BY avg_per_order DESC;

-- 12. 客户按消费总额排名(窗口函数)
SELECT customer_name,
       grand_total,
       ROW_NUMBER() OVER (ORDER BY grand_total DESC) AS rn
FROM (
    SELECT c.customer_name,
           SUM(oi.quantity * oi.unit_price) AS grand_total
    FROM customers c
    JOIN orders o       ON o.customer_id = c.customer_id
    JOIN order_items oi ON oi.order_id   = o.order_id
    GROUP BY c.customer_id, c.customer_name
) t
ORDER BY rn;
