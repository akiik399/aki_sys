-- =====================================================
-- aki_sys 个人主页 内容表初始化脚本(阶段 0)
-- 适用: MySQL 8.x
-- 用法: mysql --default-character-set=utf8mb4 -u root -p < homepage_init.sql
--
-- 说明:
--   1. 本脚本只新增主页内容表,**不动** `sys_user` / `sys_role`(RBAC 保持原样)。
--   2. 全部使用 CREATE TABLE IF NOT EXISTS,可重复执行,不会清空已有数据。
--   3. 导入必须带 --default-character-set=utf8mb4。Windows 控制台默认 GBK,
--      用 GBK 客户端导入 UTF-8 脚本会把中文按 GBK 解读后存进 utf8mb4 列(双重编码),
--      页面上会出现 `杩愯惀浜哄憳` 这类乱码。下面的 SET NAMES 兜底。
-- =====================================================
SET NAMES utf8mb4;

USE `aki_sys`;

-- -----------------------------------------------------
-- 1. 个人资料(单行表,固定 id = 1)
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `site_profile` (
    `id`          BIGINT       NOT NULL DEFAULT 1 COMMENT '固定为1,单行表',
    `nickname`    VARCHAR(50)  NOT NULL COMMENT '昵称/姓名',
    `avatar`      VARCHAR(500) DEFAULT NULL COMMENT '头像地址',
    `slogan`      VARCHAR(200) DEFAULT NULL COMMENT '一句话标语',
    `bio_md`      TEXT         DEFAULT NULL COMMENT '个人简介(Markdown)',
    `location`    VARCHAR(100) DEFAULT NULL COMMENT '所在地',
    `email`       VARCHAR(100) DEFAULT NULL COMMENT '联系邮箱',
    `social_json` JSON         DEFAULT NULL COMMENT '社交链接 [{"name":"GitHub","url":"..."}]',
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `updated_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT ='个人资料';

-- -----------------------------------------------------
-- 2. 技能
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `site_skill` (
    `id`         BIGINT       NOT NULL AUTO_INCREMENT COMMENT '技能ID',
    `name`       VARCHAR(50)  NOT NULL COMMENT '技能名称',
    `category`   VARCHAR(50)  DEFAULT NULL COMMENT '分类:后端/前端/数据库/工具',
    `level`      TINYINT      NOT NULL DEFAULT 60 COMMENT '熟练度 0-100,用于技能条',
    `icon`       VARCHAR(200) DEFAULT NULL COMMENT '图标(emoji 或图片地址)',
    `sort`       INT          NOT NULL DEFAULT 0 COMMENT '排序,越小越前',
    `status`     TINYINT      NOT NULL DEFAULT 1 COMMENT '状态 1显示 0隐藏',
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    KEY `idx_skill_sort` (`sort`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT ='技能';

-- -----------------------------------------------------
-- 3. 项目作品
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `site_project` (
    `id`            BIGINT       NOT NULL AUTO_INCREMENT COMMENT '项目ID',
    `title`         VARCHAR(100) NOT NULL COMMENT '项目名称',
    `summary`       VARCHAR(300) DEFAULT NULL COMMENT '一句话简介(卡片用)',
    `cover`         VARCHAR(500) DEFAULT NULL COMMENT '封面图地址',
    `tech_json`     JSON         DEFAULT NULL COMMENT '技术标签 ["Java","Vue3"]',
    `repo_url`      VARCHAR(500) DEFAULT NULL COMMENT '仓库地址',
    `demo_url`      VARCHAR(500) DEFAULT NULL COMMENT '演示地址',
    `highlights_md` TEXT         DEFAULT NULL COMMENT '项目亮点(Markdown,详情页用)',
    `featured`      TINYINT      NOT NULL DEFAULT 0 COMMENT '是否精选 1是 0否(首页只展示精选)',
    `sort`          INT          NOT NULL DEFAULT 0 COMMENT '排序,越小越前',
    `status`        TINYINT      NOT NULL DEFAULT 1 COMMENT '状态 1发布 0下线',
    `created_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `updated_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    KEY `idx_project_status_sort` (`status`, `sort`),
    KEY `idx_project_featured` (`featured`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT ='项目作品';

-- -----------------------------------------------------
-- 4. 博客文章
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `site_post` (
    `id`           BIGINT       NOT NULL AUTO_INCREMENT COMMENT '文章ID',
    `title`        VARCHAR(200) NOT NULL COMMENT '标题',
    `slug`         VARCHAR(200) NOT NULL COMMENT 'URL 短标识(详情页 /posts/{slug})',
    `summary`      VARCHAR(500) DEFAULT NULL COMMENT '摘要(列表用)',
    `cover`        VARCHAR(500) DEFAULT NULL COMMENT '封面图地址',
    `content_md`   LONGTEXT     DEFAULT NULL COMMENT '正文(Markdown)',
    `tags_json`    JSON         DEFAULT NULL COMMENT '标签 ["Spring Boot","Redis"]',
    `status`       TINYINT      NOT NULL DEFAULT 0 COMMENT '状态 0草稿 1已发布',
    `published_at` DATETIME     DEFAULT NULL COMMENT '发布时间(草稿为空)',
    `views`        INT          NOT NULL DEFAULT 0 COMMENT '浏览量(Redis 计数回写)',
    `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `updated_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_post_slug` (`slug`),
    KEY `idx_post_status_published` (`status`, `published_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT ='博客文章';

-- -----------------------------------------------------
-- 5. 经历时间线
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `site_timeline` (
    `id`          BIGINT       NOT NULL AUTO_INCREMENT COMMENT '经历ID',
    `type`        VARCHAR(20)  NOT NULL DEFAULT 'work' COMMENT '类型:edu 教育 / work 工作 / project 项目',
    `title`       VARCHAR(100) NOT NULL COMMENT '标题(如:后端开发工程师)',
    `org`         VARCHAR(100) DEFAULT NULL COMMENT '组织/学校/公司',
    `start_date`  VARCHAR(20)  DEFAULT NULL COMMENT '开始时间(如 2023-07,允许只到月份)',
    `end_date`    VARCHAR(20)  DEFAULT NULL COMMENT '结束时间,空表示至今',
    `description` VARCHAR(1000) DEFAULT NULL COMMENT '描述',
    `sort`        INT          NOT NULL DEFAULT 0 COMMENT '排序,越小越前',
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `updated_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    KEY `idx_timeline_sort` (`sort`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT ='经历时间线';

-- -----------------------------------------------------
-- 6. 留言
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `site_message` (
    `id`         BIGINT       NOT NULL AUTO_INCREMENT COMMENT '留言ID',
    `nickname`   VARCHAR(50)  NOT NULL COMMENT '昵称',
    `email`      VARCHAR(100) DEFAULT NULL COMMENT '邮箱(不对外展示)',
    `content`    VARCHAR(1000) NOT NULL COMMENT '留言内容(渲染前必须过 dompurify)',
    `ip`         VARCHAR(64)  DEFAULT NULL COMMENT '来源IP(限流与审计用)',
    `ua`         VARCHAR(500) DEFAULT NULL COMMENT 'User-Agent(爬虫过滤用)',
    `status`     TINYINT      NOT NULL DEFAULT 0 COMMENT '状态 0待审核 1已通过 2已拒绝',
    `reply`      VARCHAR(1000) DEFAULT NULL COMMENT '站长回复',
    `replied_at` DATETIME     DEFAULT NULL COMMENT '回复时间',
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    KEY `idx_message_status_created` (`status`, `created_at`),
    KEY `idx_message_ip_created` (`ip`, `created_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT ='留言';

-- -----------------------------------------------------
-- 7. 访问日志(统计明细;PV/UV 靠聚合查询,不另建汇总表)
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `site_visit` (
    `id`         BIGINT       NOT NULL AUTO_INCREMENT COMMENT '记录ID',
    `path`       VARCHAR(300) NOT NULL COMMENT '访问路径',
    `ip`         VARCHAR(64)  DEFAULT NULL COMMENT '来源IP',
    `ua`         VARCHAR(500) DEFAULT NULL COMMENT 'User-Agent',
    `referer`    VARCHAR(500) DEFAULT NULL COMMENT '来源页',
    `session_id` VARCHAR(64)  DEFAULT NULL COMMENT '会话标识(UV 按它去重,不按 IP)',
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '访问时间',
    PRIMARY KEY (`id`),
    KEY `idx_visit_created` (`created_at`),
    KEY `idx_visit_session` (`session_id`),
    KEY `idx_visit_path` (`path`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT ='访问日志';

-- -----------------------------------------------------
-- 种子数据:个人资料占位行(单行表,固定 id=1)
-- 记得把下面这些占位内容改成你自己的
-- -----------------------------------------------------
INSERT IGNORE INTO `site_profile` (`id`, `nickname`, `avatar`, `slogan`, `bio_md`, `location`, `email`, `social_json`)
VALUES (1,
        '你的昵称',
        NULL,
        '一句话介绍你自己',
        '## 关于我\n\n这里写个人简介,支持 Markdown。',
        '中国 · 某城市',
        'you@example.com',
        JSON_ARRAY(
            JSON_OBJECT('name', 'GitHub', 'url', 'https://github.com/your-name'),
            JSON_OBJECT('name', '掘金', 'url', 'https://juejin.cn/user/your-id')
        ));

SELECT '个人主页内容表初始化完成' AS msg;
