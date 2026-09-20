-- =====================================================
-- aki_sys 站点访客账号表(阶段 2a)
-- 适用: MySQL 8.x
-- 用法: mysql --default-character-set=utf8mb4 -u root -p < site_user_init.sql
--
-- 说明:
--   1. 本脚本只新增站点访客表,**不动** sys_user / sys_role(后台账号)。
--      站点访客与后台账号是两条互不相通的认证域,详见
--      docs/用户注册与验证码登录方案.md 第一节。
--   2. 全部 CREATE TABLE IF NOT EXISTS,可重复执行,不会清空已有数据。
--   3. 导入必须带 --default-character-set=utf8mb4,否则中文会被双重编码成乱码。
-- =====================================================
SET NAMES utf8mb4;

USE `aki_sys`;

CREATE TABLE IF NOT EXISTS `site_user` (
    `id`             BIGINT       NOT NULL AUTO_INCREMENT COMMENT '访客ID',
    `email`          VARCHAR(120) NOT NULL COMMENT '邮箱(登录名)',
    `password`       VARCHAR(100) DEFAULT NULL COMMENT '密码(BCrypt);纯验证码用户可为空',
    `nickname`       VARCHAR(50)  NOT NULL COMMENT '昵称(对外展示)',
    `avatar`         VARCHAR(500) DEFAULT NULL COMMENT '头像地址',
    `status`         TINYINT      NOT NULL DEFAULT 1 COMMENT '状态 1正常 0禁用',
    `email_verified` TINYINT      NOT NULL DEFAULT 0 COMMENT '邮箱是否已验证 1是 0否',
    `last_login_at`  DATETIME     DEFAULT NULL COMMENT '最近登录时间',
    `login_count`    INT          NOT NULL DEFAULT 0 COMMENT '累计登录次数',
    `created_at`     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '注册时间',
    `updated_at`     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_site_user_email` (`email`),
    KEY `idx_site_user_status` (`status`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT ='站点访客账号';

-- 注意:本表【刻意没有 role_id 字段】。
-- 访客不需要任何角色,没有这个字段就不可能出现"给访客配了后台角色"这种误操作。
-- 后台权限一律只认 sys_user,两条域在数据层面就是分开的。

SELECT '站点访客表初始化完成' AS msg;
