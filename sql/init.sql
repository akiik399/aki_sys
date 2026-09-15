-- =====================================================
-- aki_sys 后台管理系统 数据库初始化脚本
-- 适用: MySQL 8.x
-- 用法: mysql --default-character-set=utf8mb4 -u root -p < init.sql
--       若客户端字符集不是 utf8mb4(Windows 控制台默认 GBK),脚本里的中文注释与
--       默认值会被写成乱码;下面的 SET NAMES 负责把本次会话固定为 utf8mb4。
-- =====================================================
SET NAMES utf8mb4;

CREATE DATABASE IF NOT EXISTS `aki_sys` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE `aki_sys`;

-- 角色表
DROP TABLE IF EXISTS `sys_role`;
CREATE TABLE `sys_role` (
    `id`         BIGINT       NOT NULL AUTO_INCREMENT COMMENT '角色ID',
    `name`       VARCHAR(50)  NOT NULL COMMENT '角色名称',
    `code`       VARCHAR(50)  NOT NULL COMMENT '角色编码',
    `remark`     VARCHAR(200) DEFAULT NULL COMMENT '备注',
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_role_code` (`code`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT ='角色表';

-- 用户表
DROP TABLE IF EXISTS `sys_user`;
CREATE TABLE `sys_user` (
    `id`         BIGINT       NOT NULL AUTO_INCREMENT COMMENT '用户ID',
    `username`   VARCHAR(50)  NOT NULL COMMENT '用户名',
    `password`   VARCHAR(100) NOT NULL COMMENT '密码(BCrypt)',
    `nickname`   VARCHAR(50)  DEFAULT NULL COMMENT '昵称',
    `role_id`    BIGINT       DEFAULT NULL COMMENT '角色ID',
    `status`     TINYINT      NOT NULL DEFAULT 1 COMMENT '状态 1正常 0禁用',
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_username` (`username`),
    KEY `idx_role_id` (`role_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT ='用户表';
