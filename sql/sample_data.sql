-- =====================================================
-- aki_sys 练习用示例数据(可重复执行)
-- 说明: 所有用户密码均为 admin123(BCrypt)
-- 执行方式(务必用 utf8mb4): mysql --default-character-set=utf8mb4 -u root -p < sample_data.sql
--       本文件是 UTF-8 编码,若用 GBK 客户端导入,'运营人员'/'数据分析师'/'访客'
--       以及 16 个示例用户昵称会被双重编码成乱码(见 sql/fix_mojibake.sql)。
-- =====================================================
SET NAMES utf8mb4;

USE `aki_sys`;

-- 新增角色(ADMIN=1, USER=2 已存在)
INSERT IGNORE INTO `sys_role` (`id`, `name`, `code`, `remark`) VALUES
  (3, '运营人员', 'OPERATOR', '日常运营'),
  (4, '数据分析师', 'ANALYST', '数据统计与分析'),
  (5, '访客', 'GUEST', '只读访客');

-- 示例用户(密码统一为 admin123)
INSERT IGNORE INTO `sys_user` (`username`, `password`, `nickname`, `role_id`, `status`) VALUES
  ('zhangsan', '$2a$10$jGzLSckXPjoNglj6LxRnJ.VCptsb0PaMoyl6V/qvmHoZluNzx3e5G', '张三', 3, 1),
  ('lisi',     '$2a$10$jGzLSckXPjoNglj6LxRnJ.VCptsb0PaMoyl6V/qvmHoZluNzx3e5G', '李四', 3, 1),
  ('wangwu',   '$2a$10$jGzLSckXPjoNglj6LxRnJ.VCptsb0PaMoyl6V/qvmHoZluNzx3e5G', '王五', 4, 1),
  ('zhaoliu',  '$2a$10$jGzLSckXPjoNglj6LxRnJ.VCptsb0PaMoyl6V/qvmHoZluNzx3e5G', '赵六', 4, 0),
  ('sunqi',    '$2a$10$jGzLSckXPjoNglj6LxRnJ.VCptsb0PaMoyl6V/qvmHoZluNzx3e5G', '孙七', 2, 1),
  ('zhouba',   '$2a$10$jGzLSckXPjoNglj6LxRnJ.VCptsb0PaMoyl6V/qvmHoZluNzx3e5G', '周八', 2, 1),
  ('wujiu',    '$2a$10$jGzLSckXPjoNglj6LxRnJ.VCptsb0PaMoyl6V/qvmHoZluNzx3e5G', '吴九', 5, 1),
  ('zhengshi', '$2a$10$jGzLSckXPjoNglj6LxRnJ.VCptsb0PaMoyl6V/qvmHoZluNzx3e5G', '郑十', 5, 0),
  ('linxia',   '$2a$10$jGzLSckXPjoNglj6LxRnJ.VCptsb0PaMoyl6V/qvmHoZluNzx3e5G', '林夏', 3, 1),
  ('huangdong','$2a$10$jGzLSckXPjoNglj6LxRnJ.VCptsb0PaMoyl6V/qvmHoZluNzx3e5G', '黄东', 4, 1),
  ('xuyang',   '$2a$10$jGzLSckXPjoNglj6LxRnJ.VCptsb0PaMoyl6V/qvmHoZluNzx3e5G', '许洋', 2, 0),
  ('zhangxiao','$2a$10$jGzLSckXPjoNglj6LxRnJ.VCptsb0PaMoyl6V/qvmHoZluNzx3e5G', '张晓', 3, 1),
  ('liqiang',  '$2a$10$jGzLSckXPjoNglj6LxRnJ.VCptsb0PaMoyl6V/qvmHoZluNzx3e5G', '李强', 2, 1),
  ('wangfang', '$2a$10$jGzLSckXPjoNglj6LxRnJ.VCptsb0PaMoyl6V/qvmHoZluNzx3e5G', '王芳', 4, 1),
  ('chenjing', '$2a$10$jGzLSckXPjoNglj6LxRnJ.VCptsb0PaMoyl6V/qvmHoZluNzx3e5G', '陈静', 5, 1),
  ('yangfan',  '$2a$10$jGzLSckXPjoNglj6LxRnJ.VCptsb0PaMoyl6V/qvmHoZluNzx3e5G', '杨帆', 3, 0);
