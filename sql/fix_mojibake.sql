-- =====================================================
-- aki_sys 中文乱码修复脚本(可重复执行 / 幂等)
--
-- 【病因】
--   导入 sql/sample_data.sql 时客户端字符集不是 utf8mb4(Windows 控制台默认 GBK),
--   文件里的 UTF-8 中文字节被按 GBK 解读后交给 utf8mb4 列 —— 双重编码,
--   页面/接口读出来就是 "运营人员" -> "杩愯惀浜哄憳" 这种乱码,少数汉字还因
--   GBK 无法映射而丢字节变成 "?"(如 "访客" -> "璁垮?")。
--
-- 【受影响范围】
--   sys_role  : code = OPERATOR / ANALYST / GUEST (id 3/4/5)
--   sys_user  : sample_data.sql 里的 16 个示例用户(id 2~17)
--   不受影响  : 内置角色 ADMIN/USER 与 admin 账号由后端 DataInitializer 写库,字符集正确;
--               应用自身的写入链路(接口新增/编辑)已实测正常,无需改动。
--
-- 【用法】
--   mysql --default-character-set=utf8mb4 -u root -p < sql/fix_mojibake.sql
--
-- 【做法】
--   以 code / username 为业务键,按 sample_data.sql 的原始文案覆盖 name/remark/nickname。
--   不新增、不删除任何行,不改密码、状态、角色绑定与时间字段,可安全重复执行。
--   脚本末尾会做一致性校验,两个计数都应为 0。
-- =====================================================
SET NAMES utf8mb4;
USE `aki_sys`;

-- ---------- 期望值(唯一真相来源,同时用于修复与校验) ----------
DROP TEMPORARY TABLE IF EXISTS `tmp_expect_role`;
CREATE TEMPORARY TABLE `tmp_expect_role` (
    `code`   VARCHAR(50)  NOT NULL PRIMARY KEY,
    `name`   VARCHAR(50)  NOT NULL,
    `remark` VARCHAR(200) DEFAULT NULL
);
INSERT INTO `tmp_expect_role` (`code`, `name`, `remark`) VALUES
    ('OPERATOR', '运营人员',   '日常运营'),
    ('ANALYST',  '数据分析师', '数据统计与分析'),
    ('GUEST',    '访客',       '只读访客');

DROP TEMPORARY TABLE IF EXISTS `tmp_expect_user`;
CREATE TEMPORARY TABLE `tmp_expect_user` (
    `username` VARCHAR(50) NOT NULL PRIMARY KEY,
    `nickname` VARCHAR(50) DEFAULT NULL
);
INSERT INTO `tmp_expect_user` (`username`, `nickname`) VALUES
    ('zhangsan',  '张三'),
    ('lisi',      '李四'),
    ('wangwu',    '王五'),
    ('zhaoliu',   '赵六'),
    ('sunqi',     '孙七'),
    ('zhouba',    '周八'),
    ('wujiu',     '吴九'),
    ('zhengshi',  '郑十'),
    ('linxia',    '林夏'),
    ('huangdong', '黄东'),
    ('xuyang',    '许洋'),
    ('zhangxiao', '张晓'),
    ('liqiang',   '李强'),
    ('wangfang',  '王芳'),
    ('chenjing',  '陈静'),
    ('yangfan',   '杨帆');

-- ---------- 修复 ----------
UPDATE `sys_role` AS r
    JOIN `tmp_expect_role` AS e ON e.`code` = r.`code`
SET r.`name` = e.`name`, r.`remark` = e.`remark`;

UPDATE `sys_user` AS u
    JOIN `tmp_expect_user` AS e ON e.`username` = u.`username`
SET u.`nickname` = e.`nickname`;

-- ---------- 校验(两个计数都必须是 0) ----------
SELECT
    (SELECT COUNT(*) FROM `sys_role` AS r JOIN `tmp_expect_role` AS e ON e.`code` = r.`code`
      WHERE r.`name` <> e.`name` OR COALESCE(r.`remark`, '') <> COALESCE(e.`remark`, '')) AS `角色不一致数`,
    (SELECT COUNT(*) FROM `sys_user` AS u JOIN `tmp_expect_user` AS e ON e.`username` = u.`username`
      WHERE COALESCE(u.`nickname`, '') <> COALESCE(e.`nickname`, ''))                    AS `用户不一致数`;

-- ---------- 修复后的实际数据(人工确认一眼) ----------
SELECT `id`, `name`, `code`, `remark` FROM `sys_role` ORDER BY `id`;
SELECT `id`, `username`, `nickname`, `role_id`, `status` FROM `sys_user` ORDER BY `id`;
