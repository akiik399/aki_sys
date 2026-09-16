#!/usr/bin/env bash
# =====================================================
# aki_sys 服务器现状侦察(只读,不做任何修改)
#
# 用途:在部署前看清这台机器上已经有什么,决定怎么避让/复用。
# 全程只执行查看类命令,不装包、不改配置、不删文件。
#
# 两种用法:
#   A) 配好免密登录后,在本地一条命令跑完(推荐):
#        Get-Content .\deploy\recon.sh -Raw | ssh aki 'bash -s'
#   B) 直接登进服务器粘贴执行:
#        scp deploy/recon.sh root@<IP>:/tmp/ && ssh root@<IP> 'bash /tmp/recon.sh'
# =====================================================
set -uo pipefail

line() { printf '\n===== %s =====\n' "$1"; }

line "系统版本 / 内核 / 架构"
cat /etc/os-release 2>/dev/null | grep -E '^(PRETTY_NAME|VERSION_ID|VERSION_CODENAME)='
echo "内核: $(uname -r)"
echo "架构: $(uname -m)"
echo "时间: $(date '+%F %T %Z')"
echo "运行时长: $(uptime -p 2>/dev/null || uptime)"

line "CPU / 内存 / 磁盘(判断资源够不够跑 Java)"
echo "CPU 核数: $(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)"
free -h 2>/dev/null | head -n2
df -h / /opt /var 2>/dev/null | grep -v '^Filesystem' | sort -u

line "apt 源状态(18.04 已 EOL,这里最可能出问题)"
grep -rhE '^(deb|deb-src)' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | grep -v '^\s*#' | head -n 12
echo "--- 源可达性试连(不下载,只看能否连上)---"
for host in archive.ubuntu.com security.ubuntu.com old-releases.ubuntu.com mirrors.aliyun.com mirrors.cloud.aliyuncs.com; do
    if timeout 6 bash -c "cat < /dev/null > /dev/tcp/$host/80" 2>/dev/null; then
        echo "  $host:80 可连"
    else
        echo "  $host:80 不可连/超时"
    fi
done

line "JDK17 安装路线的可达性(18.04 必须走这里,关键)"
# 18.04 官方源没有 openjdk-17,server-init.sh 会回退到 Adoptium(Temurin)。
# 如果 Adoptium 拉不到,JDK17 就装不上,整个部署卡在第一关 —— 所以单独探一下。
echo "  --- apt 里到底有没有 openjdk-17 ---"
echo "  openjdk-17-jre-headless: $(apt-cache policy openjdk-17-jre-headless 2>/dev/null | grep -E 'Candidate' | head -n1 | sed 's/^ *//' || echo '查询失败')"
echo "  openjdk-11-jre-headless: $(apt-cache policy openjdk-11-jre-headless 2>/dev/null | grep -E 'Candidate' | head -n1 | sed 's/^ *//' || echo '查询失败')"
echo "  --- Adoptium / 镜像站连通性(443)---"
for host in packages.adoptium.net mirrors.tuna.tsinghua.edu.cn mirrors.huaweicloud.com download.oracle.com; do
    if timeout 8 bash -c "cat < /dev/null > /dev/tcp/$host/443" 2>/dev/null; then
        echo "  $host:443 可连"
    else
        echo "  $host:443 不可连/超时"
    fi
done
echo "  --- 实际拉取测试(只取 HTTP 头,不下文件)---"
if command -v curl >/dev/null 2>&1; then
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 -I https://packages.adoptium.net/artifactory/api/gpg/key/public 2>/dev/null || echo 000)"
    echo "  Adoptium GPG 公钥 HTTP 状态: $code   (200=可用)"
else
    echo "  curl 未安装,跳过"
fi

line "端口占用情况"
if command -v ss >/dev/null 2>&1; then
    ss -lntp 2>/dev/null || ss -lnt
else
    netstat -lntp 2>/dev/null || netstat -lnt
fi

line "80 端口上到底是谁在服务"
if command -v nginx >/dev/null 2>&1; then
    echo "nginx 版本: $(nginx -v 2>&1)"
    echo "nginx 二进制: $(command -v nginx)"
    echo "--- server_name / listen / root 指令 ---"
    grep -rhE '^\s*(listen|server_name|root|index)\s' /etc/nginx/nginx.conf /etc/nginx/conf.d/ /etc/nginx/sites-enabled/ 2>/dev/null | sed 's/^\s*/  /' | head -n 30
    echo "--- 已启用的站点文件 ---"
    ls -l /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ 2>/dev/null
else
    echo "未安装 nginx"
fi
echo "--- 首页内容首行(判断是不是默认页)---"
for f in /var/www/html/index.html /var/www/html/index.nginx-debian.html /usr/share/nginx/html/index.html; do
    if [ -f "$f" ]; then
        echo "  文件: $f  ($(stat -c %s "$f") 字节, 改于 $(stat -c %y "$f" | cut -d. -f1))"
        head -c 200 "$f" | tr '\n' ' '
        echo
    fi
done

line "Java 环境"
if command -v java >/dev/null 2>&1; then
    java -version 2>&1 | head -n 1
    echo "JAVA_HOME=${JAVA_HOME:-未设置}"
else
    echo "未安装 Java"
fi
echo "--- apt 源里能装到哪些 openjdk(18.04 通常只有 11)---"
apt-cache policy openjdk-17-jre-headless openjdk-11-jre-headless 2>/dev/null | grep -E '^\S|Candidate' | head -n 8

line "MySQL"
if command -v mysql >/dev/null 2>&1; then
    mysql --version 2>/dev/null
    systemctl is-active mysql 2>/dev/null || systemctl is-active mysqld 2>/dev/null || echo "mysql 服务状态未知"
    echo "--- 能否免密连上 ---"
    if mysql -N -B -e "SELECT VERSION()" >/dev/null 2>&1; then
        echo "  可以免密连接"
        echo "  现有数据库:"
        mysql -N -B -e "SHOW DATABASES" 2>/dev/null | sed 's/^/    /'
        echo "  aki_sys 库是否存在: $(mysql -N -B -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='aki_sys'" 2>/dev/null)"
    else
        echo "  不能免密连接(root 可能需要密码)"
    fi
else
    echo "未安装 MySQL"
fi

line "Redis"
if command -v redis-server >/dev/null 2>&1; then
    redis-server --version 2>/dev/null
    systemctl is-active redis-server 2>/dev/null || systemctl is-active redis 2>/dev/null || echo "redis 服务状态未知"
    if command -v redis-cli >/dev/null 2>&1; then
        redis-cli ping 2>/dev/null | sed 's/^/  ping: /'
        echo "  已用内存: $(redis-cli info memory 2>/dev/null | grep -E '^used_memory_human' | cut -d: -f2 | tr -d '\r')"
        echo "  现有 key 数: $(redis-cli dbsize 2>/dev/null | tr -d '\r')"
    fi
else
    echo "未安装 Redis"
fi

line "已有目录(看是否有历史部署)"
for d in /opt/aki-admin /etc/aki-admin /var/log/aki-admin; do
    if [ -e "$d" ]; then
        echo "  存在: $d"
        ls -la "$d" 2>/dev/null | head -n 8 | sed 's/^/    /'
    else
        echo "  不存在: $d"
    fi
done
echo "--- 是否已有 aki-admin 服务 ---"
systemctl list-unit-files 2>/dev/null | grep -i aki || echo "  无"

line "/opt 与 /var/log 的现有内容"
ls -l /opt 2>/dev/null | head -n 10
ls -l /var/log 2>/dev/null | head -n 12

line "防火墙状态"
if command -v ufw >/dev/null 2>&1; then
    ufw status 2>/dev/null | head -n 8
else
    echo "未安装 ufw"
fi
if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --list-all 2>/dev/null | head -n 10
else
    echo "未安装 firewalld"
fi
echo "--- iptables 规则数(阿里云镜像常预置规则)---"
iptables -S 2>/dev/null | wc -l

line "SSH 配置(看是否已禁用密码登录)"
grep -iE '^\s*(PasswordAuthentication|PermitRootLogin|PubkeyAuthentication|Port)\b' /etc/ssh/sshd_config 2>/dev/null | sed 's/^/  /'
echo "  authorized_keys 条目数: $(wc -l < ~/.ssh/authorized_keys 2>/dev/null || echo 0)"

line "sudo 权限"
if [ "$(id -u)" -eq 0 ]; then echo "  当前是 root"; else echo "  当前用户: $(id -un)"; sudo -n true 2>/dev/null && echo "  免密 sudo 可用" || echo "  无免密 sudo"; fi

line "结束"
echo "以上均为只读检查,未做任何修改。"
