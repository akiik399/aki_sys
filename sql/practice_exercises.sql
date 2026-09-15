-- =====================================================
-- practice_db SQL 练习题(共 12 题,从易到难)
-- 在 DBeaver 里把连接切到 practice_db 后逐题练习
-- 参考答案见 practice_answers.sql,先自己写再看！
-- =====================================================
USE practice_db;

-- 【第 1 题】 查询所有客户(全部列)
-- 提示: SELECT * FROM customers;
-- 你的代码:

-- 【第 2 题】 查询商品名和单价,只显示"数码"类,按单价从高到低
-- 提示: WHERE category='数码' ORDER BY unit_price DESC
-- 你的代码:

-- 【第 3 题】 统计每个分类有多少种商品(分组计数)
-- 提示: GROUP BY category
-- 你的代码:

-- 【第 4 题】 查询单价在 100~500 之间的商品
-- 提示: BETWEEN
-- 你的代码:

-- 【第 5 题】 查询"已完成"订单的总数
-- 提示: SELECT COUNT(*) FROM orders WHERE status='已完成'
-- 你的代码:

-- 【第 6 题】 每个客户下了多少单(LEFT JOIN + GROUP BY,含没下过单的客户)
-- 你的代码:

-- 【第 7 题】 查询每张订单的客户姓名 + 下单日期 + 订单状态
-- 提示: JOIN customers ON orders.customer_id=customers.customer_id
-- 你的代码:

-- 【第 8 题】 查询每张订单的总金额(订单明细求和)
-- 提示: JOIN order_items, SUM(quantity*unit_price)
-- 你的代码:

-- 【第 9 题】 找出总消费金额最高的客户(含姓名)
-- 提示: 多表 JOIN + SUM + ORDER BY + LIMIT
-- 你的代码:

-- 【第 10 题】 查询从来"没下过单"的客户(子查询 NOT IN / NOT EXISTS)
-- 你的代码:

-- 【第 11 题】 统计每个客户的平均每单金额(Having 过滤平均金额>300 的)
-- 你的代码:

-- 【第 12 题】 使用窗口函数,给每个客户按消费总额排名(ROW_NUMBER)
-- 提示: MySQL 8 支持 OVER(...)
-- 你的代码:
