#!/usr/bin/env bash
# =====================================================
# aki_sys 服务器初始化脚本(在服务器上以 root 执行,只需跑一次)
#
#   scp deploy/server-init.sh root@服务器:/tmp/
#   ssh root@服务器 'bash /tmp/server-init.sh'
#
# 这个脚本只负责"把人装好、目录建好、库建好",不负责传业务代码。
# 之后每次发版都在本地跑 deploy/deploy.ps1。
#
# 幂等:重复执行不会破坏已有数据(建库/建表用 IF NOT EXISTS,
# 目录用 mkdir -p,软件包已装则跳过)。
# =====================================================
set -euo pipefail

APP_USER="aki"
APP_DIR="/opt/aki-admin"
CONF_DIR="/etc/aki-admin"
LOG_DIR="/var/log/aki-admin"
WEB_DIR="${APP_DIR}/web"
APP_JAR="aki-admin-1.0.0.jar"

if [[ $EUID -ne 0 ]]; then
    echo "请用 root 执行:sudo bash $0" >&2
    exit 1
fi

step() { echo; echo "=== $* ==="; }
ok()   { echo "  [OK] $*"; }
warn() { echo "  [!]  $*"; }

# SQL 脚本目录:依次尝试
#   1) 环境变量 SQL_DIR_OVERRIDE
#   2) ./sql                        (从仓库根目录执行)
#   3) <脚本所在目录>/../sql        (deploy/ 与 sql/ 作为兄弟目录一起上传 —— README 推荐的方式)
#   4) <脚本所在目录>               (把 sql/*.sql 直接和脚本放同一目录)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR=""
for cand in "${SQL_DIR_OVERRIDE:-}" "./sql" "${SCRIPT_DIR}/../sql" "${SCRIPT_DIR}"; do
    if [[ -n "$cand" && -f "${cand}/init.sql" ]]; then
        SQL_DIR="$(cd "$cand" && pwd)"
        break
    fi
done
if [[ -z "$SQL_DIR" ]]; then
    # 退一步:只找 deploy 目录下的配套文件(nginx/systemd/env 模板)
    SQL_DIR="$SCRIPT_DIR"
    warn "没找到 sql/init.sql,建表步骤需要你手动执行(见文末)"
else
    ok "SQL 脚本目录: $SQL_DIR"
fi

# -----------------------------------------------------
# 1. 识别发行版 & 安装软件
# -----------------------------------------------------
step "识别系统并安装依赖"

# 先记录发行版信息,后面判断要不要走 Adoptium 装 JDK17
DISTRO_ID=""; DISTRO_VER=""; DISTRO_CODENAME=""
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-}"
    DISTRO_VER="${VERSION_ID:-}"
    DISTRO_CODENAME="${VERSION_CODENAME:-}"
fi
ok "系统: ${PRETTY_NAME:-未知} (${DISTRO_ID} ${DISTRO_VER} ${DISTRO_CODENAME})"

# -----------------------------------------------------
# 1a. 基础软件包(不含 Java —— Java 单独处理,见 1b)
# -----------------------------------------------------
if command -v apt-get >/dev/null 2>&1; then
    PKG=apt
    export DEBIAN_FRONTEND=noninteractive

    # 18.04(bionic)已过标准支持期,archive.ubuntu.com 上的 bionic 可能已下架,
    # 表现为 apt-get update 报 404/Release file not found。
    # 这时把源切到 old-releases.ubuntu.com 即可继续用。
    if apt-get update -qq 2>/tmp/aki-apt-update.log; then
        ok "apt 源可用"
    else
        warn "apt-get update 失败,最近几行输出:"
        tail -n 5 /tmp/aki-apt-update.log 2>/dev/null | sed 's/^/      /' || true
        if [[ "$DISTRO_ID" == "ubuntu" && -z "${AKI_SKIP_OLD_RELEASES:-}" ]]; then
            warn "尝试切换到 old-releases.ubuntu.com(仅适用于已 EOL 的 Ubuntu)"
            if [[ -f /etc/apt/sources.list ]]; then
                cp -n /etc/apt/sources.list /etc/apt/sources.list.aki-bak 2>/dev/null || true
                sed -i \
                    -e 's|https\?://archive\.ubuntu\.com/ubuntu|http://old-releases.ubuntu.com/ubuntu|g' \
                    -e 's|https\?://security\.ubuntu\.com/ubuntu|http://old-releases.ubuntu.com/ubuntu|g' \
                    -e 's|https\?://[a-z0-9.]*\.ubuntu\.com/ubuntu|http://old-releases.ubuntu.com/ubuntu|g' \
                    /etc/apt/sources.list
                ok "已改写 sources.list(原文件备份在 /etc/apt/sources.list.aki-bak)"
                if apt-get update -qq; then
                    ok "切换后 apt 源可用"
                else
                    warn "仍然失败。请手动修好 apt 源再重跑本脚本。"
                fi
            fi
        fi
    fi

    apt-get install -y -qq mysql-server redis-server nginx curl tar openssl ca-certificates gnupg apt-transport-https
    MYSQL_SVC=mysql
    REDIS_SVC=redis-server
elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    PKG=rpm
    if command -v dnf >/dev/null 2>&1; then YUM=dnf; else YUM=yum; fi
    $YUM install -y mysql-server redis nginx curl tar openssl ca-certificates
    MYSQL_SVC=mysqld
    REDIS_SVC=redis
else
    echo "未识别的发行版(没有 apt/yum/dnf),请手动安装:OpenJDK 17 / MySQL / Redis / nginx" >&2
    exit 1
fi
ok "基础依赖安装完成(包管理器: $PKG)"

# -----------------------------------------------------
# 1b. Java 17
# -----------------------------------------------------
# 关键点:Ubuntu 18.04 的官方源里【没有】openjdk-17(最高 11),而本项目
# 是 Java 17 编译的,11 跑不起来(报 UnsupportedClassVersionError)。
# 所以先探测 apt 里有没有 17,没有就从 Adoptium(现 Eclipse Temurin)的
# 仓库装 —— 这是目前最可靠的 JDK17 来源,且支持 bionic。
step "安装 Java 17"

java_major() {
    # 从 java -version 输出里取主版本号。
    # 要兼容三种写法:
    #   openjdk version "17.0.13" 2024-10-15     (Debian/Ubuntu 打包)
    #   java version "1.8.0_401"                 (老式 1.x 编号)
    #   openjdk version "17.0.13" ... / Temurin-17.0.13+11  (Adoptium 有时不带引号)
    # 之前用 [[ =~ \"([0-9]+) ]] 匹配带引号的串,遇到 Temurin 的不带引号输出会解析为空,
    # 导致明明装了 17 却被判成"未知版本"。
    local v
    v="$(java -version 2>&1 | head -n1 || true)"
    v="${v//\"/}"                       # 去掉引号
    # 直接抓第一个数字段,不依赖厂商名和数字之间有没有空格。
    # 例:openjdk version "17.0.13" / Temurin-17.0.13+11 / java version "1.8.0_401"
    if [[ "$v" =~ ([0-9]+) ]]; then
        local n="${BASH_REMATCH[1]}"
        # 老式编号 1.8.0_401 的主版本是 8,不是 1
        if [[ "$n" == "1" && "$v" =~ 1\.([0-9]+) ]]; then
            echo "${BASH_REMATCH[1]}"
        else
            echo "$n"
        fi
    else
        echo ""
    fi
}

APT_HAS_17=0
if [[ "$PKG" == "apt" ]]; then
    # apt-cache policy 对不存在的包会输出 Candidate: (none)
    if apt-cache policy openjdk-17-jre-headless 2>/dev/null | grep -q 'Candidate: [0-9]'; then
        APT_HAS_17=1
    fi
fi

if [[ "$PKG" == "rpm" ]]; then
    $YUM install -y java-17-openjdk-headless || warn "java-17-openjdk-headless 安装失败"
elif [[ "$APT_HAS_17" == "1" ]]; then
    apt-get install -y -qq openjdk-17-jre-headless
    ok "已从官方源安装 openjdk-17-jre-headless"
else
    warn "官方源里没有 openjdk-17(常见于 Ubuntu 18.04),改用 Adoptium(Temurin)仓库"
    if [[ -z "$DISTRO_CODENAME" ]]; then
        warn "无法确定发行版代号,跳过 Adoptium 自动安装。请手动装 JDK17 后重跑。"
    else
        mkdir -p /etc/apt/keyrings
        if curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
                -o /tmp/adoptium.asc; then
            # 新版 apt 支持 signed-by 直接用 ascii-armored key;
            # 18.04 的 apt 1.6 也支持,但用 .gpg 二进制更稳
            gpg --dearmor < /tmp/adoptium.asc > /etc/apt/keyrings/adoptium.gpg 2>/dev/null \
                || cp /tmp/adoptium.asc /etc/apt/keyrings/adoptium.gpg
            echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb ${DISTRO_CODENAME} main" \
                > /etc/apt/sources.list.d/adoptium.list
            if apt-get update -qq -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/adoptium.list \
                                  -o Dir::Etc::sourceparts=/dev/null 2>/dev/null; then
                ok "Adoptium 仓库已添加,apt 源更新成功"
            else
                apt-get update -qq 2>/dev/null || warn "apt update 有告警,继续尝试安装"
            fi
            if apt-get install -y -qq temurin-17-jdk; then
                ok "已安装 Temurin JDK 17"
            else
                warn "temurin-17-jdk 安装失败。可能原因:服务器无法访问 packages.adoptium.net"
                echo "      阿里云服务器如果拉不到,可换清华/华为镜像,或手动下载 tar.gz:"
                echo "        curl -LO https://mirrors.tuna.tsinghua.edu.cn/Adoptium/17/jdk/x64/linux/OpenJDK17U-jdk_x64_linux_hotspot_17.0.13_11.tar.gz"
                echo "        mkdir -p /opt/jdk17 && tar -xzf OpenJDK17U-jdk_x64_linux_hotspot_*.tar.gz -C /opt/jdk17 --strip-components=1"
                echo "        ln -sf /opt/jdk17/bin/java /usr/local/bin/java"
                echo "        ln -sf /opt/jdk17/bin/jar  /usr/local/bin/jar"
            fi
        else
            warn "下载 Adoptium GPG 公钥失败(服务器出网受限?)"
            echo "      请手动安装 JDK17,或改用系统源里的 openjdk-11 并重新编译项目。"
        fi
    fi
fi

# 校验最终版本 —— 不通过就直接停,免得后面服务起来了却报
# UnsupportedClassVersionError 让人一头雾水
if ! command -v java >/dev/null 2>&1; then
    echo "没找到 java,Java 17 安装失败。请手动安装后重跑本脚本。" >&2
    exit 1
fi
JV="$(java_major)"
JAVA_BIN="$(command -v java)"
JAVA_VER_STR="$(java -version 2>&1 | head -n1 || true)"
if [[ -z "$JV" || "$JV" -lt 17 ]]; then
    warn "当前 Java 主版本是 ${JV:-未知},低于项目要求的 17 —— 服务会启动失败"
    echo "      当前: $JAVA_VER_STR"
    echo "      已安装的 JDK:"
    ls -d /usr/lib/jvm/* 2>/dev/null | sed 's/^/        /' || true
    echo "      手动指定: update-alternatives --config java"
    echo "      或指向解压版: ln -sf /opt/jdk17/bin/java /usr/local/bin/java"
else
    ok "Java 已就绪: Java $JV ($JAVA_BIN)"
    ok "版本串: $JAVA_VER_STR"
fi

# -----------------------------------------------------
# 2. 创建运行用户与目录
# -----------------------------------------------------
step "创建用户与目录"

if ! id -u "$APP_USER" >/dev/null 2>&1; then
    # --system:系统账号,不建家目录、不能登录 —— 应用进程不需要 shell
    useradd --system --no-create-home --shell /usr/sbin/nologin "$APP_USER"
    ok "已创建系统用户 $APP_USER"
else
    ok "用户 $APP_USER 已存在"
fi

mkdir -p "$APP_DIR" "$WEB_DIR" "$CONF_DIR" "$LOG_DIR"
chown -R "${APP_USER}:${APP_USER}" "$APP_DIR" "$LOG_DIR"
chmod 755 "$APP_DIR" "$WEB_DIR"
chmod 750 "$LOG_DIR"
ok "目录就绪: $APP_DIR / $WEB_DIR / $CONF_DIR / $LOG_DIR"

# 日志文件必须先存在并归 aki 所有。
# 因为 systemd 里用的是 StandardOutput=append:<file>(而不是 journal),
# 这个文件由 systemd(以 root 身份)打开,不存在的话 systemd 会用 root 建,
# 之后应用自己写同名的 logback 文件就会因权限不足失败。
for f in aki-admin.log stdout.log; do
    touch "$LOG_DIR/$f"
    chown "${APP_USER}:${APP_USER}" "$LOG_DIR/$f"
    chmod 640 "$LOG_DIR/$f"
done
ok "日志文件已创建并授权"

# -----------------------------------------------------
# 3. 配置 MySQL
# -----------------------------------------------------
step "配置并启动 MySQL"

systemctl enable --now "$MYSQL_SVC"
sleep 2
if systemctl is-active --quiet "$MYSQL_SVC"; then
    ok "MySQL 已运行 ($MYSQL_SVC)"
else
    warn "MySQL 未启动,请检查 journalctl -u $MYSQL_SVC"
fi

# ---------- 先确定能不能连上 MySQL ----------
# Debian/Ubuntu 的 root 默认走 auth_socket,免密可连;
# CentOS/RHEL 的全新 mysql-server 会给 root 一个写在 /var/log/mysqld.log 里的
# 临时密码,此时所有免密调用都会失败。这里先探测清楚,后面统一走
# mysql_query / mysql_exec 包装函数 —— 绝不能像之前那样把失败直接抛给 set -e,
# 那会在建库这一步半路中断,用户/目录/nginx/systemd 全都来不及配,
# 而且报错信息里看不出真正原因。
# 需要密码时:先 export MYSQL_ROOT_PASSWORD=xxx 再跑本脚本。
MYSQL_MODE=""

if mysql -N -B -e "SELECT 1" >/dev/null 2>&1; then
    MYSQL_MODE="socket"
    ok "MySQL 可免密连接(Deploy 系统常见的 auth_socket)"
elif [[ -n "${MYSQL_ROOT_PASSWORD:-}" ]] && mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -N -B -e "SELECT 1" >/dev/null 2>&1; then
    MYSQL_MODE="password"
    ok "MySQL 使用 MYSQL_ROOT_PASSWORD 连接成功"
else
    MYSQL_MODE="none"
    warn "无法连接 MySQL,跳过建库/建表/建账号(其余初始化继续完成)"
    echo "      CentOS/RHEL 的 root 临时密码在: sudo grep 'temporary password' /var/log/mysqld.log"
    echo "      拿到密码后重新执行一次:"
    echo "        MYSQL_ROOT_PASSWORD='你的root密码' bash $0"
    echo "      或手动导入(务必带字符集参数):"
    echo "        mysql --default-character-set=utf8mb4 -u root -p < ${SQL_DIR}/init.sql"
    echo "        mysql --default-character-set=utf8mb4 -u root -p < ${SQL_DIR}/homepage_init.sql"
fi

# 密码传递方式:用 MYSQL_PWD 环境变量,不用 -p"$PW"。
# -p 会把明文密码放进进程的**命令行参数**,同机任何用户 `ps aux` 都能看到;
# MYSQL_PWD 只存在于该进程的环境里(/proc/<pid>/environ,仅 root 可读)。
# 官方也提示 MYSQL_PWD 不算安全,但比命令行参数高一个量级,
# 而这里是"本机 root 初始化数据库"的场景,没有更轻量的替代方案。
mysql_query() {
    case "$MYSQL_MODE" in
        socket)   mysql -N -B -e "$1" ;;
        password) MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -u root -N -B -e "$1" ;;
        *)        return 1 ;;
    esac
}
mysql_exec() {
    case "$MYSQL_MODE" in
        socket)   mysql -e "$1" ;;
        password) MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -u root -e "$1" ;;
        *)        return 1 ;;
    esac
}
mysql_import() {
    case "$MYSQL_MODE" in
        socket)   mysql --default-character-set=utf8mb4 < "$1" ;;
        password) MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -u root --default-character-set=utf8mb4 < "$1" ;;
        *)        return 1 ;;
    esac
}

# 安全提醒:MySQL 默认只监听 127.0.0.1。如果你的云服务器安全组
# 开了 3306,请立刻关掉 —— 数据库绝不该暴露在公网。
if [[ -f /etc/mysql/mysql.conf.d/mysqld.cnf ]]; then
    ok "MySQL 配置位于 /etc/mysql/mysql.conf.d/mysqld.cnf"
elif [[ -f /etc/my.cnf ]]; then
    ok "MySQL 配置位于 /etc/my.cnf"
fi

# 建库 + 建表(只建 sys_user / sys_role,不上示例数据)
# init.sql 里有 DROP TABLE IF EXISTS,在空白库上是安全的;
# 但千万不要在有数据的库上重跑 —— 所以这里先用 information_schema 判断一次。
if [[ "$MYSQL_MODE" != "none" && -f "${SQL_DIR}/init.sql" ]]; then
    # 关键:必须区分"查到了 0(库确实不存在)"和"查询本身失败"。
    # 原来写的是 `|| echo 0`,把失败也变成 0 —— 一旦 MySQL 刚启动还没就绪、
    # 这次查询瞬时失败,而紧接着的导入又成功了,就会在已有数据的库上跑 init.sql;
    # 它含 DROP TABLE IF EXISTS,直接把 sys_user / sys_role 清空。
    # 所以失败时取哨兵值并跳过导入:宁可让你手动补一次,也绝不盲跑 DROP。
    DB_EXISTS="$(mysql_query "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='aki_sys'" 2>/dev/null)" || DB_EXISTS="QUERY_FAILED"
    if [[ "$DB_EXISTS" == "QUERY_FAILED" || -z "$DB_EXISTS" ]]; then
        warn "无法确认库 aki_sys 是否存在(查询失败),已跳过 init.sql —— 它含 DROP TABLE,不能盲跑"
        echo "      确认 MySQL 正常后重跑本脚本;或手动导入:"
        echo "      mysql --default-character-set=utf8mb4 -u root -p < ${SQL_DIR}/init.sql"
    elif [[ "$DB_EXISTS" == "0" ]]; then
        if mysql_import "${SQL_DIR}/init.sql"; then
            ok "已执行 init.sql(建库建表)"
        else
            warn "执行 init.sql 失败,请手动导入:mysql --default-character-set=utf8mb4 -u root -p < ${SQL_DIR}/init.sql"
        fi
    else
        warn "库 aki_sys 已存在,跳过 init.sql(它含 DROP TABLE,重跑会清空数据)"
    fi
elif [[ "$MYSQL_MODE" == "none" ]]; then
    : # 上面已经提示过
elif [[ ! -f "${SQL_DIR}/init.sql" ]]; then
    warn "没找到 init.sql,请手动导入(务必带字符集参数,否则中文会双重编码成乱码):"
    echo "      mysql --default-character-set=utf8mb4 -u root -p < sql/init.sql"
    echo "      mysql --default-character-set=utf8mb4 -u root -p < sql/homepage_init.sql"
fi

# 个人主页内容表(homepage_init.sql)。
# 它和 init.sql 性质不同:全部是 CREATE TABLE IF NOT EXISTS,幂等、不清数据,
# 所以不需要像 init.sql 那样先判断库是否存在,每次都可以安全执行。
# 漏掉它的后果很容易被忽略:sys_user / sys_role 建好了、后端也能起来,
# 但 site_profile / site_project / site_post 等七张表不存在 ——
# 公开主页和后台内容管理一访问就报 table doesn't exist。
if [[ "$MYSQL_MODE" != "none" && -f "${SQL_DIR}/homepage_init.sql" ]]; then
    if mysql_import "${SQL_DIR}/homepage_init.sql"; then
        ok "已执行 homepage_init.sql(个人主页内容表,幂等)"
    else
        warn "执行 homepage_init.sql 失败(库 aki_sys 是否已建?),请手动导入:"
        echo "      mysql --default-character-set=utf8mb4 -u root -p < ${SQL_DIR}/homepage_init.sql"
    fi
elif [[ "$MYSQL_MODE" != "none" ]]; then
    warn "没找到 homepage_init.sql,个人主页的七张 site_* 表不会创建"
    echo "      手动导入:mysql --default-character-set=utf8mb4 -u root -p < sql/homepage_init.sql"
fi

# 应用专用数据库账号:比直接用 root 更好 —— 万一被注入,影响面只有这一个库
# 密码来源(优先级从高到低):
#   1) 环境变量 AKI_DB_PASSWORD='xxx' bash server-init.sh
#   2) /etc/aki-admin/aki-admin.env 里已填好的 AKI_DB_PASSWORD
# 取第 2 种是因为实际流程是"先初始化、再 vi 填密码、最后部署" ——
# 重新跑一次 init 就能顺手把账号建好/对齐密码。
ENV_FILE="${CONF_DIR}/aki-admin.env"
if [[ -z "${AKI_DB_PASSWORD:-}" && -f "$ENV_FILE" ]]; then
    # tail -n1:避免变量被定义多次时取到旧值
    ENV_PW="$(grep -E '^[[:space:]]*AKI_DB_PASSWORD=' "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '"'"'"'\r' || true)"
    if [[ -n "$ENV_PW" && "$ENV_PW" != "CHANGE_ME" ]]; then
        AKI_DB_PASSWORD="$ENV_PW"
        ok "已从 $ENV_FILE 读到数据库密码"
    fi
fi

if [[ "$MYSQL_MODE" == "none" ]]; then
    warn "MySQL 当前连不上,跳过创建数据库账号(连上后重跑本脚本即可)"
elif [[ -n "${AKI_DB_PASSWORD:-}" && "$AKI_DB_PASSWORD" != "CHANGE_ME" ]]; then
    # 密码要同时进 shell、SQL 字面量、systemd EnvironmentFile 和 JDBC URL 四处,
    # 限制字符集是最省心的做法。白名单是刻意选出来的:
    #   @ 允许 —— 它出现在 JDBC URL 里理论上要编码,但只要我们不允许 : / ? #
    #             这些真正的 URL 分隔符,整串就不需要任何转义。
    #   # 允许 —— 查过 systemd 的 env-file.c:只有在行首(未进入 KEY 状态前)
    #             才算注释开始,出现在值里就是普通字符。
    #   \ 和 $ 禁止 —— 这两个是 systemd 的 SHELL_NEED_ESCAPE 字符:
    #             反斜杠会触发转义(密码被改写),$ 会被做变量展开
    #             (密码里出现 $ 时实际值会变),两者都属于"配好了却连不上"的坑。
    if [[ ! "$AKI_DB_PASSWORD" =~ ^[A-Za-z0-9._@#%^+=-]+$ ]]; then
        warn "AKI_DB_PASSWORD 含不支持的字符,跳过创建库账号"
        echo "      允许的字符:字母 数字 . _ @ # % ^ + = -"
        echo "      禁止:空格 : / ? \\ \$ ' \" (反斜杠和 \$ 会被 systemd 转义/展开)"
    else
        # CREATE USER IF NOT EXISTS 对已存在的用户是静默空操作,不会改密码。
        # 而"改了 env 里的密码后重跑 init"正是本脚本推荐的流程 ——
        # 只 CREATE 的话数据库里还是旧密码,后端会 Access denied。
        # 所以补一条 ALTER USER 把密码对齐。
        # 用 --execute 而不是 heredoc:密码由 shell 变量原样拼进去,不踩引号转义。
        if mysql_exec "CREATE USER IF NOT EXISTS 'aki'@'127.0.0.1' IDENTIFIED BY '${AKI_DB_PASSWORD}'; ALTER USER 'aki'@'127.0.0.1' IDENTIFIED BY '${AKI_DB_PASSWORD}'; GRANT ALL PRIVILEGES ON aki_sys.* TO 'aki'@'127.0.0.1'; FLUSH PRIVILEGES;"; then
            ok "数据库账号 aki@127.0.0.1 已就绪(密码与 env 文件一致,仅授权 aki_sys 库)"
        else
            warn "创建数据库账号失败,请手动执行 CREATE USER / GRANT"
        fi
    fi
else
    warn "未设置 AKI_DB_PASSWORD,跳过创建专用库账号。"
    echo "      想创建的话执行:"
    echo "        AKI_DB_PASSWORD='你的强密码' bash $0"
    echo "      然后在 /etc/aki-admin/aki-admin.env 里同步 AKI_DB_USERNAME=aki 和 AKI_DB_PASSWORD"
fi

# -----------------------------------------------------
# 4. 配置 Redis
# -----------------------------------------------------
step "配置并启动 Redis"

systemctl enable --now "$REDIS_SVC"
sleep 1
systemctl is-active --quiet "$REDIS_SVC" && ok "Redis 已运行 ($REDIS_SVC)" || warn "Redis 未启动"

echo "  Redis 加固建议(手动执行一次):"
# 配置文件路径各发行版不同,先探测出来再给命令,别让复制粘贴失败
REDIS_CONF=""
for c in /etc/redis/redis.conf /etc/redis.conf /etc/redis/6379.conf; do
    [[ -f "$c" ]] && { REDIS_CONF="$c"; break; }
done
if [[ -n "$REDIS_CONF" ]]; then
    echo "    配置文件: $REDIS_CONF"
    echo "    1) 设密码: sudo sed -i 's/^# *requirepass .*/requirepass 你的强密码/' $REDIS_CONF"
    echo "    2) 只监听本机: 确认该项是 bind 127.0.0.1 -::1(默认通常已是)"
    echo "    3) 重启: sudo systemctl restart $REDIS_SVC"
    echo "    4) 把密码同步到 /etc/aki-admin/aki-admin.env 的 AKI_REDIS_PASSWORD"
else
    echo "    未找到 redis.conf,可用 'redis-cli CONFIG SET requirepass 你的强密码' 临时设置(重启失效)"
fi
echo
echo "  【重要】Redis 里存的是登录态(JWT 白名单)。Redis 没开持久化也没关系,"
echo "  只是重启后所有人需要重新登录 —— 但一定要设密码,否则被人清库就等于强制全站下线。"

# -----------------------------------------------------
# 5. 部署配置文件(nginx / systemd / env)
# -----------------------------------------------------
step "安装 nginx 与 systemd 配置"

# 这个脚本和 deploy/ 下的配置一起上传时,能自动装好;
# 只上传了脚本的话就打印手动步骤。
#
# 注意 install 的返回值必须显式判断:本函数只会在 if / || 这类上下文里被调用,
# 而 bash 对这类上下文里的整个函数体关闭 errexit —— 也就是说 install 失败
# 不会中断执行,会径直跑到 ok 并 return 0,把失败报成成功。
install_if_present() {
    local src="$1" dst="$2" mode="${3:-644}"
    if [[ ! -f "$src" ]]; then
        return 1
    fi
    if ! install -m "$mode" "$src" "$dst"; then
        warn "安装失败: $src -> $dst"
        return 1
    fi
    ok "已安装 $dst"
    return 0
}

# -----------------------------------------------------
# 5a. 记录并备份 80 端口上已有的站点
# -----------------------------------------------------
# 这一步的目的:接管 80 之前先把现状留档。
# 云服务器上经常已经跑着别的站点(宝塔面板、旧的测试页、另一个项目),
# 直接覆盖会让人事后找不到原来的配置。
# 备份放在 /root/aki-nginx-backup-<时间戳>/,不删任何原文件,可随时还原。
NGINX_BACKUP="/root/aki-nginx-backup-$(date +%Y%m%d-%H%M%S)"
NGINX_BACKED_UP=0

existing_sites=""
if [[ -d /etc/nginx/sites-enabled ]]; then
    existing_sites="$(find /etc/nginx/sites-enabled -maxdepth 1 -type f -o -maxdepth 1 -type l 2>/dev/null | sort)"
fi
if [[ -d /etc/nginx/conf.d ]]; then
    existing_sites="${existing_sites}
$(find /etc/nginx/conf.d -maxdepth 1 -type f -name '*.conf' 2>/dev/null | sort)"
fi
existing_sites="$(echo "$existing_sites" | sed '/^$/d')"

if [[ -n "$existing_sites" ]]; then
    mkdir -p "$NGINX_BACKUP"
    echo "$existing_sites" | while read -r f; do
        [[ -e "$f" ]] || continue
        cp -a "$f" "$NGINX_BACKUP/$(basename "$f").$(echo "$f" | tr '/' '_')" 2>/dev/null || true
    done
    # 顺带把 web 根目录也留一份(只有小站才这么做,避免备份出几个 G)
    for d in /var/www/html /usr/share/nginx/html; do
        if [[ -d "$d" ]]; then
            sz="$(du -sm "$d" 2>/dev/null | cut -f1 || echo 9999)"
            if [[ "${sz:-9999}" -le 100 ]]; then
                cp -a "$d" "$NGINX_BACKUP/webroot-$(basename "$d")" 2>/dev/null || true
            else
                warn "跳过备份 $d(超过 100MB,请自行确认是否重要)"
            fi
        fi
    done
    cp -a /etc/nginx/nginx.conf "$NGINX_BACKUP/nginx.conf" 2>/dev/null || true
    NGINX_BACKED_UP=1
    ok "已备份现有 nginx 站点配置到: $NGINX_BACKUP"
    echo "      备份内容:"
    echo "$existing_sites" | sed 's/^/        /'
    echo "      需要还原时:cp -a $NGINX_BACKUP/<备份文件名> <原路径> && nginx -t && systemctl reload nginx"
else
    ok "nginx 上暂无站点配置,无需备份"
fi

# 被本脚本接管而需要停用的默认站点。
# 注意:这里【只处理明确的发行版默认页】,不再像以前那样无条件删 sites-enabled/default ——
# 万一你原来的站点正好叫 default,无条件删除就把它弄没了(虽然有备份,但没必要冒这风险)。
for f in /etc/nginx/sites-enabled/default; do
    if [[ -e "$f" ]]; then
        tgt="$(readlink -f "$f" 2>/dev/null || echo "$f")"
        if grep -qE 'index\.nginx-debian\.html|/var/www/html' "$tgt" 2>/dev/null; then
            rm -f "$f"
            ok "已停用发行版默认站点: $f(配置文件与 web 根目录均已备份)"
        else
            warn "$f 不是发行版默认页,为安全起见【未删除】"
            echo "      它可能和 aki_sys 抢 80 端口。请确认后手动处理,或先停用它:"
            echo "        sudo rm -f $f   # 备份在 $NGINX_BACKUP"
        fi
    fi
done

# -----------------------------------------------------
# 5b. 安装 aki_sys 的 nginx / systemd 配置
# -----------------------------------------------------
step "安装 aki_sys 的 nginx 与 systemd 配置"

# nginx 站点配置:优先 conf.d,某些发行版用 sites-available
if install_if_present "${SQL_DIR}/nginx.conf" /etc/nginx/conf.d/aki-admin.conf; then
    # 显式 if 而不是 `nginx -t && reload && ok`:
    # 在 && 列表里除最后一条外都被 errexit 豁免,配置写错时既不中断也不报警,
    # 脚本会一路走到"初始化完成",而 nginx 其实还在用旧配置。
    if nginx -t; then
        systemctl reload nginx && ok "nginx 配置生效"
    else
        warn "nginx 配置检查失败,未重载。修好后手动执行:sudo nginx -t && sudo systemctl reload nginx"
    fi
else
    warn "未找到 nginx.conf,请手动拷到 /etc/nginx/conf.d/aki-admin.conf 后执行 nginx -t && sudo systemctl reload nginx"
fi

install_if_present "${SQL_DIR}/aki-admin.service" /etc/systemd/system/aki-admin.service || \
    warn "未找到 aki-admin.service,请手动拷到 /etc/systemd/system/"

if [[ -f /etc/systemd/system/aki-admin.service ]]; then
    systemctl daemon-reload
    systemctl enable aki-admin >/dev/null 2>&1 || true
    ok "aki-admin 服务已注册并设为开机自启"
fi

# env 文件:不存在才生成模板,绝不覆盖已填好的密钥
if [[ ! -f "${CONF_DIR}/aki-admin.env" ]]; then
    if [[ -f "${SQL_DIR}/aki-admin.env.example" ]]; then
        install -m 600 -o root -g root "${SQL_DIR}/aki-admin.env.example" "${CONF_DIR}/aki-admin.env"
    else
        cat > "${CONF_DIR}/aki-admin.env" <<'EOF'
AKI_PORT=8080
AKI_DB_HOST=127.0.0.1
AKI_DB_PORT=3306
AKI_DB_NAME=aki_sys
AKI_DB_USERNAME=aki
AKI_DB_PASSWORD=CHANGE_ME
AKI_REDIS_HOST=127.0.0.1
AKI_REDIS_PORT=6379
AKI_REDIS_PASSWORD=CHANGE_ME
AKI_JWT_SECRET=CHANGE_ME
AKI_JWT_EXPIRE_SECONDS=28800
EOF
        chmod 600 "${CONF_DIR}/aki-admin.env"
    fi
    ok "已生成 ${CONF_DIR}/aki-admin.env(权限 600)"
else
    ok "${CONF_DIR}/aki-admin.env 已存在,保持不动"
fi

# 顺手把 JWT 密钥填成随机值,避免有人忘了改就上线。
# 两种模板都要覆盖:env.example 里是 CHANGE_ME_openssl_rand_base64_48,
# 上面 heredoc 兜底生成的则是 CHANGE_ME。
# 用 | 当 sed 分隔符:base64 的字母表含 / 和 +,用 / 会破坏替换。
if grep -qE '^[[:space:]]*AKI_JWT_SECRET=[[:space:]]*CHANGE_ME' "${CONF_DIR}/aki-admin.env" 2>/dev/null; then
    SECRET="$(openssl rand -base64 48 | tr -d '\n')"
    sed -i "s|^AKI_JWT_SECRET=.*|AKI_JWT_SECRET=${SECRET}|" "${CONF_DIR}/aki-admin.env"
    ok "已自动生成随机 JWT 密钥"
fi

warn "还需要手动改 ${CONF_DIR}/aki-admin.env 里的数据库/Redis 密码:"
echo "      sudo vi ${CONF_DIR}/aki-admin.env"

# -----------------------------------------------------
# 6. 防火墙
# -----------------------------------------------------
step "防火墙"

if command -v ufw >/dev/null 2>&1; then
    # 不要写成 `ufw status | grep -q ...`:grep -q 命中后立刻退出,ufw 收到
    # SIGPIPE(141),pipefail 会把整条管道判为失败,于是判断走 else 分支,
    # 结果是防火墙规则一条都没放行却毫无提示。
    # 先把输出整段取回来(|| true 兜住 ufw 自身非 0 的情况),再用 [[ == ]] 匹配。
    UFW_STATUS="$(ufw status 2>/dev/null || true)"
    if [[ "$UFW_STATUS" == *"Status: active"* ]]; then
        ufw allow 22/tcp  >/dev/null 2>&1 || true
        ufw allow 80/tcp  >/dev/null 2>&1 || true
        ufw allow 443/tcp >/dev/null 2>&1 || true
        ok "ufw 已放行 22/80/443"
    else
        echo "  ufw 已安装但未启用,未改动规则。"
    fi
elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-service=ssh   >/dev/null
    firewall-cmd --permanent --add-service=http  >/dev/null
    firewall-cmd --permanent --add-service=https >/dev/null
    firewall-cmd --reload >/dev/null
    ok "firewalld 已放行 ssh/http/https"
else
    echo "  未检测到启用中的 ufw/firewalld。"
fi
echo "  【别忘了云厂商安全组】阿里云/腾讯云/AWS 的入站规则也要放行 80、443;"
echo "  3306(MySQL)和 6379(Redis)绝对不要对公网开放。"

# -----------------------------------------------------
# 7. 免密 sudo(给部署用户用)
# -----------------------------------------------------
step "部署用户免密 sudo"

DEPLOY_USER="${SUDO_USER:-}"
if [[ -n "$DEPLOY_USER" && "$DEPLOY_USER" != "root" ]]; then
    # 这里给的是 NOPASSWD:ALL(权限等同于 root),不是"部署所需命令"的白名单 ——
    # 注释原先写作"部署所需命令",容易让人误以为已收窄。这是有意的取舍:
    # deploy.ps1 会调用 systemctl / install / chown / mysql / tar 等一大批命令,
    # 收窄成白名单时只要漏掉一条,发版就会在服务器上失败,而那时你很难立刻定位。
    # 要收窄的话,先把 deploy.ps1 与 bootstrap.ps1 里所有 sudo 调用列全,再改这里。
    #
    # 写法:先写临时文件、visudo 校验通过后再 install 到 /etc/sudoers.d/。
    # 不要直接写目标文件再校验:那样在校验之前 sudo 就已经会读到这个坏文件,
    # 语法一旦有误,你可能把自己彻底锁在 sudo 之外。
    SUDOERS_TMP="$(mktemp)"
    cat > "$SUDOERS_TMP" <<EOF
# 由 server-init.sh 生成:部署用户免密 sudo(本地 deploy.ps1 依赖它)
# 权限等同于 root,仅适用于个人 / 单机部署场景。
${DEPLOY_USER} ALL=(ALL) NOPASSWD:ALL
EOF
    if visudo -c -f "$SUDOERS_TMP" >/dev/null; then
        install -m 440 -o root -g root "$SUDOERS_TMP" /etc/sudoers.d/aki-deploy
        ok "已为 $DEPLOY_USER 配置免密 sudo(本地 deploy.ps1 依赖它)"
    else
        warn "sudoers 内容校验失败,未安装。请手动配置:"
        echo "      echo '${DEPLOY_USER} ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/aki-deploy && sudo chmod 440 /etc/sudoers.d/aki-deploy"
    fi
    rm -f "$SUDOERS_TMP"
else
    warn "无法确定部署用户(不是通过 sudo 执行的),请手动配置免密 sudo:"
    echo "      echo '你的用户名 ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/aki-deploy && sudo chmod 440 /etc/sudoers.d/aki-deploy"
fi

# -----------------------------------------------------
# 7.5 密码占位符检查(直接决定服务能不能起来)
# -----------------------------------------------------
step "生产配置检查"

PLACEHOLDER_FOUND=0
for key in AKI_DB_PASSWORD AKI_REDIS_PASSWORD AKI_JWT_SECRET; do
    if grep -qE "^[[:space:]]*${key}=[[:space:]]*(CHANGE_ME|CHANGE_ME_.*)[[:space:]]*$" "$ENV_FILE" 2>/dev/null; then
        warn "${key} 仍是占位符 CHANGE_ME —— 不改的话后端启动会失败"
        PLACEHOLDER_FOUND=1
    fi
done

if [[ "$PLACEHOLDER_FOUND" == "1" ]]; then
    echo "      编辑: sudo vi ${ENV_FILE}"
    echo "      Redis 密码若留空,需保证 Redis 端也没有 requirepass;"
    echo "      否则把它设成 Redis 的实际密码。"
else
    ok "环境变量文件已填写完整"
fi

# -----------------------------------------------------
# 完成
# -----------------------------------------------------
step "初始化完成"
cat <<EOF
  下一步:
    1) 与本仓库 sql/ 一起上传后导入表结构(中文务必带字符集参数):
         mysql --default-character-set=utf8mb4 -u root -p < sql/init.sql
         mysql --default-character-set=utf8mb4 -u root -p < sql/homepage_init.sql
       (init.sql 已由本脚本自动执行过则跳过它)
    2) 填好 /etc/aki-admin/aki-admin.env 里的密码
    3) 回本地执行:  .\\deploy\\deploy.ps1 -Server root@<服务器IP>
    4) 部署完后在服务器上确认:
         systemctl status aki-admin
         curl -i http://127.0.0.1:8080/api/auth/me
         curl -I http://127.0.0.1/
EOF
