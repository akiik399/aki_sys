# aki_sys 后台管理系统

前后端分离的后台管理系统:Spring Boot 3 + MyBatis-Plus + MySQL + Redis(JWT 登录态)+ Vue 3 + Vite + Element Plus。

## 技术栈

| 端 | 技术 |
|---|---|
| 后端 | Java 17 · Spring Boot 3.4.4 · MyBatis-Plus 3.5.9 · JWT(jjwt 0.12.6) · Spring Data Redis · springdoc-openapi |
| 前端 | Vue 3.5 · Vite 5 · Element Plus · Pinia · Vue Router · Axios |
| 存储 | MySQL 8(库 `aki_sys`)· Redis(登录态,TTL 8h) |

## 目录结构

```
aki_sys/
├── backend/                 # Spring Boot 后端
│   ├── pom.xml
│   └── src/main/
│       ├── java/com/aki/admin/
│       │   ├── AdminApplication.java
│       │   ├── common/      # Result 统一返回 / 全局异常
│       │   ├── config/      # MyBatis-Plus 分页 / Web 拦截 / BCrypt
│       │   ├── controller/  # auth / users / roles 接口
│       │   ├── dto/         # 请求参数
│       │   ├── entity/      # SysUser / SysRole
│       │   ├── initializer/ # 启动初始化内置账号
│       │   ├── mapper/
│       │   ├── security/    # JwtUtil / AuthInterceptor / UserContext
│       │   └── service/
│       └── resources/
│           ├── application.yml       # 开发配置
│           └── application-prod.yml  # 生产配置(数据库/Redis/JWT 走环境变量注入)
├── frontend/                # Vue3 前端
│   └── src/
│       ├── api/             # axios 封装 + 接口
│       ├── config/          # 站点配置(站名 / 导航 / 页脚)
│       ├── layout/          # SiteLayout 公开站点 + AdminLayout 管理后台
│       ├── router/          # 路由 + 白名单守卫(公开区 与 /admin 管理区)
│       ├── store/           # Pinia 用户状态
│       └── views/           # 公开页(site/) / 后台页(system/)
├── deploy/                  # Linux 部署脚本与配置(详见 deploy/README.md)
├── docs/                    # 项目文档(面试准备文档 / 个人主页改造计划)
├── scripts/                 # 启停脚本的 PowerShell 实现(被 .bat 调用)
├── sql/
│   ├── init.sql             # 建库建表脚本(含 DROP,仅适合空白库)
│   ├── homepage_init.sql    # 个人主页内容表(幂等,可重复执行)
│   ├── sample_data.sql      # 示例角色/用户(练习用)
│   └── fix_mojibake.sql     # 中文乱码修复(幂等)
├── start-all.bat            # 一键启动(会按时间戳判断是否需要重新打包)
└── stop-all.bat             # 一键停止
```

## 项目文档

- `docs/面试准备文档.md` —— 基于本项目真实实现整理的面试准备材料:项目描述/STAR、架构与请求链路、15 道项目深挖题(附代码位置)、Java/Spring/MySQL/Redis/Vue/Maven 八股、手写题、场景设计题、反问清单、一周复习计划、可背诵代码片段。

## 一键启动 / 停止(推荐)

| 脚本 | 作用 |
|---|---|
| `start-all.bat` | **双击即可**:检查 MySQL 服务 → 启动 Redis → 启动后端(jar 不存在**或源码比 jar 新**会自动 Maven 打包)→ 启动前端(无 node_modules 会自动 npm install)→ 等待就绪 → 自动打开浏览器 |
| `stop-all.bat` | 停止后端(8080)、前端(5173)、Redis(6379);MySQL 服务不动 |

- 两个脚本都是**幂等**的:已在运行的服务会显示"[跳过]",不会重复启动。
- 服务在后台运行,**关掉脚本窗口不会停止它们**;要停就运行 `stop-all.bat`。
- 运行日志统一输出到 `logs/`(backend.log / frontend.log / redis.log)。
- 实现细节:`.bat` 只是 ASCII 启动器,真正逻辑在 `scripts/*.ps1`(中文提示放在 PowerShell 里,避开 cmd 代码页乱码问题)。

> 部署到 Linux 服务器请见 **`deploy/README.md`**(本地构建 + scp 上传 + systemd/nginx 配置,`deploy/deploy.ps1` 一键发版)。

## 快速启动(手动方式)

### 0. 环境要求
- JDK 17、Maven 3.6+、Node 18+、MySQL 8(已装)、Redis(已装并运行于 6379)

### 1. 初始化数据库(仅首次)
```bash
mysql --default-character-set=utf8mb4 -u root -p < sql/init.sql          # 本机 root 密码: password
mysql --default-character-set=utf8mb4 -u root -p < sql/sample_data.sql   # 可选:示例角色与示例用户
```
内置角色与 `admin` 账号由后端首次启动时自动写入,无需手工执行。

> **导入脚本必须带 `--default-character-set=utf8mb4`**(脚本内的 `SET NAMES utf8mb4` 也会兜底)。
> Windows 控制台默认代码页是 GBK,用 GBK 客户端导入 UTF-8 的 `.sql`,中文字节会被当成 GBK
> 解读后再存进 utf8mb4 列(双重编码),页面上就出现 `杩愯惀浜哄憳` 这类乱码。
> 已经乱了不用重建库:执行 `sql/fix_mojibake.sql` 即可就地修复(幂等,不增删数据)。

### 2. 启动后端(端口 8080)
```bash
cd backend
mvn spring-boot:run
# 或 mvn -DskipTests package && java -Dfile.encoding=UTF-8 -Dstdout.encoding=UTF-8 -jar target/aki-admin-1.0.0.jar
```

### 3. 启动前端(端口 5173)
```bash
cd frontend
npm install
npm run dev
```

访问 **http://localhost:5173** 即可。

## 默认账号

| 账号 | 密码 | 角色 |
|---|---|---|
| admin | admin123 | 超级管理员 |

## 登录态与 Redis

- 登录成功:签发 JWT 并把 `aki:login:token:{token} -> userId` 写入 Redis,TTL 8 小时;
- 请求鉴权:所有 `/api/**`(除登录)需带 `Authorization: Bearer {token}`,`AuthInterceptor` 校验 JWT 且要求 Redis 中存在该键;
- 退出登录:删除 Redis 键,token 立即失效,支持强制下线。

## 主要接口(前缀 /api)

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | /auth/login | 登录,返回 token + 用户信息 |
| POST | /auth/logout | 退出(删除 Redis 登录态)|
| GET | /auth/me | 当前登录用户信息 |
| GET/POST/PUT/DELETE | /users(…) | 用户分页/新增/编辑/删除 |
| PUT | /users/{id}/password | 重置密码 |
| GET/POST/PUT/DELETE | /roles(…) | 角色分页/新增/编辑/删除 |
| GET | /roles/all | 全部角色(下拉框用)|

Swagger 文档:**http://localhost:8080/swagger-ui.html**

## 配置修改点

数据库/Redis/JWT 密钥均在 `backend/src/main/resources/application.yml`,生产环境建议通过环境变量注入
(`SPRING_DATASOURCE_PASSWORD`、`AKI_JWT_SECRET` 等),JWT 密钥务必更换。

## 常见问题:中文乱码

| 现象 | 原因 | 处理 |
|---|---|---|
| 页面上角色名/用户昵称是 `杩愯惀浜哄憳`、`寮犱笁` 这类乱码 | 导入 `sql/sample_data.sql` 时客户端字符集不是 utf8mb4,UTF-8 中文字节被按 GBK 解读后再写进 utf8mb4 列(双重编码),个别字还因 GBK 无法映射而丢成 `?` | 跑 `mysql --default-character-set=utf8mb4 -u root -p < sql/fix_mojibake.sql` 就地修复;以后导入任何 `.sql` 都带 `--default-character-set=utf8mb4` |
| `logs/backend.log` 里中文乱码 | JDK 17 在中文 Windows 上默认按 GBK 写 `System.out`,与 logback 的 UTF-8 输出混在同一个文件里,编辑器只能按一种编码解析 | 已修:`log-impl` 换成 `Slf4jImpl`、`logging.charset.*=UTF-8`、启动加 `-Dfile.encoding=UTF-8 -Dstdout.encoding=UTF-8` |
| `start-all.bat` 控制台提示乱码 | PowerShell 5.1 会把**无 BOM** 的 UTF-8 `.ps1` 按 ANSI/GBK 解析 | `scripts/*.ps1` 必须保存为 **UTF-8 带 BOM**(不要另存为无 BOM) |

补充:应用本身的链路是干净的——`sys_user`/`sys_role` 均为 `utf8mb4`,后端直接返回 UTF-8 JSON,
前端 `index.html` 有 `<meta charset="UTF-8">`,经接口新增/编辑中文数据可正常往返(已实测)。
所以乱码只会来自"往库里灌数据时用错了客户端字符集"这一处。
