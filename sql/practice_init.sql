-- =====================================================
-- practice_db 经典 SQL 练习库
-- 表: customers(客户) / products(商品) / orders(订单) / order_items(订单明细)
-- 适合练 JOIN / 子查询 / 聚合 / 分组统计
-- 执行方式(务必用 utf8mb4): mysql --default-character-set=utf8mb4 -u root -p < practice_init.sql
-- =====================================================
SET NAMES utf8mb4;
CREATE DATABASE IF NOT EXISTS `practice_db` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `practice_db`;

-- 客户
DROP TABLE IF EXISTS `customers`;
CREATE TABLE `customers` (
  `customer_id`   BIGINT      NOT NULL AUTO_INCREMENT,
  `customer_name` VARCHAR(50) NOT NULL COMMENT '客户姓名',
  `contact`       VARCHAR(50) DEFAULT NULL COMMENT '联系方式',
  `city`          VARCHAR(50) DEFAULT NULL COMMENT '城市',
  `created_at`    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`customer_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='客户';

-- 商品
DROP TABLE IF EXISTS `products`;
CREATE TABLE `products` (
  `product_id`   BIGINT         NOT NULL AUTO_INCREMENT,
  `product_name` VARCHAR(100)   NOT NULL COMMENT '商品名称',
  `category`     VARCHAR(50)    DEFAULT NULL COMMENT '分类',
  `unit_price`   DECIMAL(10,2)  NOT NULL DEFAULT 0 COMMENT '单价',
  `stock`        INT            NOT NULL DEFAULT 0 COMMENT '库存',
  PRIMARY KEY (`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商品';

-- 订单
DROP TABLE IF EXISTS `orders`;
CREATE TABLE `orders` (
  `order_id`    BIGINT      NOT NULL AUTO_INCREMENT,
  `customer_id` BIGINT      NOT NULL COMMENT '客户ID',
  `order_date`  DATE        NOT NULL COMMENT '下单日期',
  `status`      VARCHAR(20) NOT NULL DEFAULT '待付款' COMMENT '订单状态',
  PRIMARY KEY (`order_id`),
  KEY `idx_customer` (`customer_id`),
  KEY `idx_order_date` (`order_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单';

-- 订单明细
DROP TABLE IF EXISTS `order_items`;
CREATE TABLE `order_items` (
  `item_id`     BIGINT        NOT NULL AUTO_INCREMENT,
  `order_id`    BIGINT        NOT NULL COMMENT '订单ID',
  `product_id`  BIGINT        NOT NULL COMMENT '商品ID',
  `quantity`    INT           NOT NULL DEFAULT 1 COMMENT '数量',
  `unit_price`  DECIMAL(10,2) NOT NULL DEFAULT 0 COMMENT '成交单价',
  PRIMARY KEY (`item_id`),
  KEY `idx_order` (`order_id`),
  KEY `idx_product` (`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单明细';

-- ===== 示例数据 =====

INSERT INTO `customers` (`customer_name`, `contact`, `city`) VALUES
  ('张伟', '13800000001', '北京'),
  ('王芳', '13800000002', '上海'),
  ('李娜', '13800000003', '广州'),
  ('刘强', '13800000004', '深圳'),
  ('陈静', '13800000005', '杭州'),
  ('杨洋', '13800000006', '成都'),
  ('赵敏', '13800000007', '武汉'),
  ('孙磊', '13800000008', '西安'),
  ('周杰', '13800000009', '南京'),
  ('吴桐', '13800000010', '重庆');

INSERT INTO `products` (`product_name`, `category`, `unit_price`, `stock`) VALUES
  ('无线鼠标',    '数码',  89.00,  200),
  ('机械键盘',    '数码',  299.00, 150),
  ('27寸显示器',  '数码',  1299.00, 60),
  ('不锈钢保温杯','日用',  79.00,  500),
  ('蓝牙耳机',    '数码',  199.00, 300),
  ('便携充电宝',  '数码',  129.00, 400),
  ('实木办公桌',  '家具',  899.00,  40),
  ('人体工学椅',  '家具',  799.00,  80),
  ('台灯',        '日用',  129.00, 220),
  ('陶瓷马克杯',  '日用',  39.00,  800),
  ('移动硬盘 1TB','数码',  459.00, 90),
  ('书架',        '家具',  349.00, 50);

INSERT INTO `orders` (`customer_id`, `order_date`, `status`) VALUES
  (1,'2026-06-01','已完成'),
  (2,'2026-06-03','已完成'),
  (1,'2026-06-05','已完成'),
  (3,'2026-06-08','已发货'),
  (4,'2026-06-10','已完成'),
  (5,'2026-06-12','已发货'),
  (6,'2026-06-15','已完成'),
  (2,'2026-06-18','已发货'),
  (7,'2026-06-20','已完成'),
  (8,'2026-06-22','待付款'),
  (9,'2026-06-25','已完成'),
  (10,'2026-06-28','已发货'),
  (1,'2026-07-01','已完成'),
  (3,'2026-07-03','已完成'),
  (5,'2026-07-05','已完成'),
  (4,'2026-07-08','已取消'),
  (6,'2026-07-10','已完成'),
  (8,'2026-07-12','已发货'),
  (2,'2026-07-15','已完成'),
  (9,'2026-07-18','已发货'),
  (7,'2026-07-20','已完成'),
  (10,'2026-07-22','已完成'),
  (1,'2026-07-25','已完成'),
  (3,'2026-07-28','已完成'),
  (5,'2026-08-01','已完成');

INSERT INTO `order_items` (`order_id`, `product_id`, `quantity`, `unit_price`) VALUES
  (1,1,1,89.00),(1,2,1,299.00),(1,5,1,199.00),
  (2,4,2,79.00),(2,6,1,129.00),
  (3,3,1,1299.00),(3,7,1,899.00),
  (4,5,3,185.00),
  (5,8,2,799.00),(5,6,1,129.00),
  (6,1,2,89.00),(6,5,1,199.00),
  (7,2,1,299.00),(7,9,2,129.00),
  (8,4,4,79.00),
  (9,10,6,39.00),(9,12,1,349.00),
  (10,11,1,459.00),(10,3,1,1299.00),
  (11,5,1,199.00),(11,6,1,129.00),
  (12,1,1,89.00),(12,9,1,129.00),
  (13,3,1,1299.00),(13,8,1,799.00),
  (14,4,2,79.00),(14,10,4,39.00),
  (15,11,2,459.00),(15,2,1,299.00),
  (16,5,2,199.00),
  (17,6,3,129.00),(17,1,1,89.00),
  (18,12,1,349.00),(18,10,2,39.00),
  (19,3,1,1299.00),(19,8,1,799.00),
  (20,4,5,79.00),
  (21,11,1,459.00),(21,9,1,129.00),
  (22,7,1,899.00),(22,6,1,129.00),
  (23,5,2,199.00),(23,2,1,299.00),
  (24,1,3,89.00),(24,10,3,39.00),
  (25,8,1,799.00),(25,12,1,349.00);
