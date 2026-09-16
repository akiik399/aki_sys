# aki_sys 部署说明(单台 Linux 服务器)

面向本仓库当前形态:**Spring Boot 3 后端 + Vue 3 前端 + MySQL 8 + Redis**,部署到一台 Linux 服务器,用 nginx 对外提供访问。

核心思路是 **本地构建、服务器只跑产物** —— 服务器上不需要装 Maven 和 Node,避免在服务器上装依赖失败拖慢整个流程。

## 一、总体架构

```
                    ┌──────────────── 服务器 ────────────────┐
   用户浏览器 ──80──▶│ nginx                                │
                    │  ├─ /            → /opt/aki-admin/web │ 前端静态文件(dist)
                    │  └─ /api/  (反代) → 127.0.0.1:8080    │
                    │                                      │
                    │  systemd: aki-admin (Java 17)         │
                    │    └─ jar /opt/aki-admin/aki-admin.jar│
                    │         ├─ MySQL 127.0.0.1:3306       │
                    │         └─ Redis 127.0.0.1:6379       │
                    └──────────────────────────────────────┘
```

## 二、需要准备的东西

| 项目 | 要求 |
|---|---|
| 服务器 | 1 台 Linux(Ubuntu 20.04+/Debian 11+/CentOS 8+ 均可),1 核 2G 起步(Java 内存按 512M 上限配的) |
| 网络 | 安全组/防火墙放行 **22、80、443**。**3306 和 6379 绝对不要对公网开放** |
| 本地 | JDK 17、Maven、Node 18+(本机已具备)、能免密 ssh 登录服务器 |
| 域名 | 可选。没有的话先用公网 IP 访问,后续再加 |

服务器上要装的东西(OpenJDK 17 / MySQL 8 / Redis / nginx)由 `deploy/server-init.sh` 自动处理。

## 三、第一次部署

> **最省事的方式**:直接跑 `deploy/bootstrap.ps1`,它把下面步骤 1-4 全串起来(只要求你在配置密钥时输一次密码),最后还会自动做端到端验证:
> ```powershell
> cd C:\myproject\aki_sys
> .\deploy\bootstrap.ps1 -Server root@<服务器IP>
> ```
> 下面的分步说明适合想逐步确认、或中途出问题需要单独重跑某一步的情况。

### 步骤 1:配置本地免密登录(如果还没配)

一键完成(推荐):
```powershell
.\deploy\setup-ssh-key.ps1 -Server root@<服务器IP>
```
它会在 `~/.ssh/config` 里写好别名 `aki`,之后 `ssh aki` 即可登录。

手动方式:

```powershell
# 生成部署专用密钥(不要用你的日常密钥)
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\aki_deploy

# 把公钥传到服务器
type $env:USERPROFILE\.ssh\aki_deploy.pub | ssh root@<服务器IP> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# 验证
ssh -i $env:USERPROFILE\.ssh\aki_deploy root@<服务器IP> "echo 通了"
```

也可以在 `~/.ssh/config` 里写个别名,之后直接用别名:

```
Host aki
    HostName 1.2.3.4
    User root
    IdentityFile ~/.ssh/aki_deploy
```

### 步骤 2:服务器初始化(推荐手动先跑一遍)

```bash
# 关键:deploy/ 和 sql/ 必须保持【同级】关系 ——
# server-init.sh 按 "<脚本目录>/../sql" 找 init.sql,层级错了就找不到 SQL、不会建表。
ssh root@<服务器IP> "rm -rf /tmp/aki-deploy && mkdir -p /tmp/aki-deploy/deploy /tmp/aki-deploy/sql"

scp -r deploy/* root@<服务器IP>:/tmp/aki-deploy/deploy/
scp -r sql/*    root@<服务器IP>:/tmp/aki-deploy/sql/

# 在服务器上执行(装软件 + 建目录 + 建库 + 配 nginx/systemd)
ssh root@<服务器IP> "bash /tmp/aki-deploy/deploy/server-init.sh"
```

脚本做完这些事:装 JDK17/MySQL/Redis/nginx、建系统用户 `aki`、建 `/opt/aki-admin` 等目录、启动并设开机自启、建库建表、装 nginx 与 systemd 配置、配防火墙、给你的部署用户配免密 sudo。**接管 80 之前会把现有 nginx 站点整体备份到 `/root/aki-nginx-backup-<时间戳>/`。**

**这一步要几分钟**(apt 装包),耐心等。也可以跳过这步直接跑步骤 3 —— `deploy.ps1` 检测到服务器上没有 systemd 服务时会自动补做,但那样耗时更长且输出不够直观。

> **Ubuntu 18.04 等老系统**:官方源里没有 `openjdk-17`,脚本会自动改从 Adoptium(Temurin)仓库安装;若 `apt update` 因 EOL 报 404,还会自动把源切到 `old-releases.ubuntu.com`。两条路都走不通时会明确报出来并给出手动安装指引(而不是留下一个装不上 Java 却"初始化完成"的假象)。

> **CentOS/RHEL 注意**:全新的 `mysql-server` 会给 root 一个写在 `/var/log/mysqld.log` 里的临时密码,免密连不上。此时脚本会**跳过建库建账号但继续完成其余初始化**(不再半路中断),并打印提示。拿到密码后重跑一次即可:
> ```bash
> MYSQL_ROOT_PASSWORD='你的root密码' bash /tmp/aki-deploy/deploy/server-init.sh
> ```
> 或者手动导入(务必带字符集参数):
> ```bash
> mysql --default-character-set=utf8mb4 -u root -p < /tmp/aki-deploy/sql/init.sql
> mysql --default-character-set=utf8mb4 -u root -p < /tmp/aki-deploy/sql/homepage_init.sql
> ```

### 步骤 3:填好生产配置

```bash
ssh root@<服务器IP> "vi /etc/aki-admin/aki-admin.env"
```

必须改的三项:

| 变量 | 说明 |
|---|---|
| `AKI_DB_PASSWORD` | 数据库密码。**只能用字母、数字和 `. _ @ # % ^ + = -`**;禁用空格、`: / ?`、`\ $ ' "` 和中文。反斜杠和 `$` 会被 systemd 的 EnvironmentFile 转义/展开,导致"填的密码"和"应用收到的密码"不一致。推荐生成:`openssl rand -hex 24`。别做 URL 编码(`@` 是允许字符,写成 `%40` 反而对不上) |
| `AKI_REDIS_PASSWORD` | Redis 密码。同时要在服务器上给 Redis 设 `requirepass` |
| `AKI_JWT_SECRET` | JWT 签名密钥。init 脚本已自动填了随机值,确认不是 `CHANGE_ME` 即可 |

> 生成密钥:`openssl rand -base64 48`

### 步骤 4:本地一键部署

```powershell
cd C:\myproject\aki_sys
.\deploy\deploy.ps1 -Server root@<服务器IP>

# 用了密钥或 ssh 别名时:
.\deploy\deploy.ps1 -Server aki
.\deploy\deploy.ps1 -Server root@1.2.3.4 -IdentityFile $env:USERPROFILE\.ssh\aki_deploy
```

脚本流程:预检 ssh → 上传 SQL → 首次自动补装服务配置 → Maven 打包 → Vite 构建 → scp 传 jar → 解包 dist → 重启服务并做健康检查。

**执行前记得停掉本地服务**(`.\stop-all.bat`),否则本地后端进程锁着 `target\aki-admin-1.0.0.jar`,Maven 覆盖不了。脚本会提前检测并提示。

### 步骤 5:验证

```bash
ssh root@<服务器IP>

systemctl status aki-admin                    # 服务在跑
curl -i http://127.0.0.1:8080/api/auth/me     # 后端响应(未登录返回业务错误码属正常)
curl -I http://127.0.0.1/                     # nginx 返回 200
tail -n 50 /var/log/aki-admin/aki-admin.log   # 应用日志
```

然后浏览器打开 `http://<服务器IP>`,用 `admin / admin123` 登录 —— **登录后第一件事就是改掉这个默认密码**。

## 四、之后每次发版

```powershell
.\deploy\deploy.ps1 -Server root@<服务器IP>
```

常用选项:

| 参数 | 作用 |
|---|---|
| `-SkipBackend` | 只发前端 |
| `-SkipFrontend` | 只发后端 |
| `-NoBuild` | 用已有产物直接上传,跳过构建 |

## 五、日常运维命令

```bash
# 服务
sudo systemctl restart aki-admin       # 重启后端
sudo systemctl status aki-admin        # 状态
sudo journalctl -u aki-admin -n 100    # systemd 侧日志(启动失败先看这个)

# 日志
tail -f /var/log/aki-admin/aki-admin.log    # 应用日志
tail -f /var/log/aki-admin/stdout.log       # 标准输出
tail -f /var/log/nginx/aki-admin.error.log  # nginx 错误

# nginx
sudo nginx -t && sudo systemctl reload nginx

# 回滚(脚本每次发版都会把上一版存成 aki-admin.jar.bak)
sudo cp -f /opt/aki-admin/aki-admin.jar.bak /opt/aki-admin/aki-admin.jar
sudo systemctl restart aki-admin
```

## 六、这个项目部署时的专属注意点

这几条都是踩过或极易踩的坑,和本项目代码强相关:

1. **前端不能跑 `npm run dev`**
   `vite.config.js` 里的 `proxy` 只在开发服务器生效。生产必须 nginx 托管 `dist` 并反代 `/api`。

2. **nginx 不能 rewrite 掉 `/api` 前缀**
   前端 `src/api/request.js` 的 `baseURL` 是 `/api`,后端接口也是 `/api/auth/login`。若写成 `proxy_pass http://127.0.0.1:8080/;`(末尾带斜杠 = 去掉前缀),所有接口 404。

3. **必须配置 history 路由回退**
   `router/index.js` 用 `createWebHistory()`,直接访问或刷新 `/admin/system/user` 这类路径,服务器上并不存在对应文件。`nginx.conf` 里靠 `try_files $uri $uri/ /index.html;` 兜住,不能删。

4. **`index.html` 不能缓存**
   Vite 产物的文件名带内容 hash,`index.html` 一旦被浏览器缓存,发版后用户会拿着旧 html 去请求已被删除的旧 assets,直接白屏。配置里已对 `index.html` 设 `no-cache`。

5. **JDK 启动参数里的 UTF-8 三个开关别删**
   `-Dfile.encoding=UTF-8 -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8`。JDK 17 在 locale 为 `C/POSIX` 的服务器上会让 `System.out` 退化成 ANSI,中文日志乱码 —— 这个项目已经在本地踩过同样的坑(`README.md` 里有专门一节)。

6. **导入 SQL 必须带字符集参数**
   ```bash
   mysql --default-character-set=utf8mb4 -u root -p < sql/init.sql
   mysql --default-character-set=utf8mb4 -u root -p < sql/homepage_init.sql
   ```
   漏了会把 UTF-8 中文按客户端编码二次编码,页面上出现 `杩愯惀浜哄憳`。已经乱了就用 `sql/fix_mojibake.sql` 就地修复。

7. **两个 SQL 脚本性质不同**
   - `sql/init.sql`:**含 `DROP TABLE IF EXISTS`**,只适合空白库,重复执行会清空 `sys_user` / `sys_role`。
   - `sql/homepage_init.sql`:全部是 `CREATE TABLE IF NOT EXISTS`,可重复执行,不会动已有数据。
   `server-init.sh` 已经做了判断:库不存在才跑 `init.sql`。

8. **`application-prod.yml` 里关掉了 Swagger**
   生产环境不暴露接口文档。需要在线调试就把 `springdoc.api-docs.enabled` 改 true,并给 nginx 加 IP 白名单,别直接敞开。

9. **`admin/admin123` 是内置初始账号**
   由后端启动时的 `DataInitializer` 写入。上线后立刻改密码,否则等于把后台送人。

10. **PowerShell 脚本必须保存为 UTF-8 带 BOM**
    `scripts/*.ps1` 和 `deploy/deploy.ps1` 都含中文。PowerShell 5.1 对无 BOM 的 UTF-8 会按系统 ANSI 代码页(中文 Windows 是 GBK)解码,中文全变乱码,甚至因为字节被误解而报出莫名其妙的语法错误。用 VSCode 另存为 "UTF-8 with BOM"。

## 七、文件清单

| 文件 | 作用 | 装到哪 |
|---|---|---|
| `deploy/deploy.ps1` | 本地一键构建 + 上传 + 重启 | 本地运行 |
| `deploy/server-init.sh` | 服务器初始化(装环境、建库、配服务) | 服务器执行一次 |
| `deploy/nginx.conf` | nginx 站点配置 | `/etc/nginx/conf.d/aki-admin.conf` |
| `deploy/aki-admin.service` | systemd 服务 | `/etc/systemd/system/aki-admin.service`(ExecStart 指向 `/opt/aki-admin/aki-admin.jar`,与 `deploy.ps1` 的上传名一致) |
| `deploy/aki-admin.env.example` | 环境变量模板 | `/etc/aki-admin/aki-admin.env`(权限 600) |
| `backend/src/main/resources/application-prod.yml` | 生产配置(环境变量注入) | 打包进 jar |

## 八、常见问题排查

| 现象 | 原因与处理 |
|---|---|
| `deploy.ps1` 报无法免密登录 | 没配密钥。按步骤 1 配好,或检查 `~/.ssh/config` 别名 |
| 报 `用户 xxx 没有免密 sudo 权限` | 在服务器执行 `echo 'xxx ALL=(ALL) NOPASSWD:ALL' \| sudo tee /etc/sudoers.d/aki-deploy && sudo chmod 440 /etc/sudoers.d/aki-deploy` |
| `systemctl status` 报 `Unable to access jarfile` | `/etc/systemd/system/aki-admin.service` 的 ExecStart 路径与 `/opt/aki-admin/` 下实际文件名不一致。本仓库两者都是 `aki-admin.jar`;若你改过 `-RemoteJarName`,记得同步改 unit 并 `systemctl daemon-reload` |
| 登录时报 SQL 错误 / 表不存在 | `server-init.sh` 没能建库(常见于 CentOS/RHEL 的 root 临时密码)。按步骤 2 的提示带 `MYSQL_ROOT_PASSWORD` 重跑,或手动导入 `sql/init.sql` 与 `sql/homepage_init.sql` |
| 后端日志 `Access denied for user 'aki'` | `/etc/aki-admin/aki-admin.env` 里的密码与数据库里的不一致。重跑 `server-init.sh` 即可对齐(它会对已存在的账号执行 `ALTER USER` 同步密码) |
| Maven 报 `Unable to rename ... .jar.original` | 本地后端进程锁着 jar。先 `.\stop-all.bat`。若它显示"未在运行"但 jar 仍被锁,用 `netstat -ano \| findstr :8080` 查 PID 再 `taskkill /F /PID <PID>` |
| 服务起不来,`journalctl` 里是数据库连接失败 | `/etc/aki-admin/aki-admin.env` 密码没改或不对。MySQL 8 的 `caching_sha2_password` 也可能需要 `ALTER USER ... IDENTIFIED WITH mysql_native_password` |
| 页面能打开,接口全 404 | nginx 的 `proxy_pass` 末尾多写了 `/`,把 `/api` 前缀吃掉了 |
| 刷新 `/admin/...` 白页或 404 | nginx 缺 `try_files ... /index.html` |
| 页面白屏、控制台报 assets 404 | `index.html` 被缓存了。确认配置里 `location = /index.html` 的 `no-cache` 还在,并强刷一次 |
| 中文显示成乱码方块 | 两类原因:导 SQL 没带 `--default-character-set=utf8mb4`(用 `fix_mojibake.sql` 修);或 systemd 里那三个 UTF-8 启动参数被删了 |
| 登录后立刻掉线 / 请求 401 | Redis 连不上或密码不对。`src/main/java/.../security/AuthInterceptor.java` 要求 Redis 中存在该 token,Redis 重启清空后所有人需重新登录 |
| 8080 端口被占 | `ss -lntp \| grep 8080` 看是谁。改 `AKI_PORT` 后记得同步 nginx 的 `proxy_pass` |

## 九、后续可选增强

- **HTTPS**:`sudo apt install -y certbot python3-certbot-nginx && sudo certbot --nginx -d <域名>`,自动续期。
- **数据库备份**:`mysqldump --default-character-set=utf8mb4 aki_sys > backup.sql` 写进 crontab。
- **后端直连改内网**:MySQL/Redis 已默认只监听 127.0.0.1,更彻底的做法是给云数据库或独立实例,应用只连内网。
