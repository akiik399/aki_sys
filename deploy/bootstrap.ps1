#!/usr/bin/env pwsh
# =====================================================
# aki_sys 一键引导部署(在本地 Windows 上执行,唯一需要你手动跑的一条命令)
#
#   cd C:\myproject\aki_sys
#   .\deploy\bootstrap.ps1 -Server root@47.120.68.160
#
# 它会依次完成:
#   1. 配置免密 SSH 登录(只在这一步需要你输入密码)
#   2. 上传 SQL 与部署配置到服务器
#   3. 服务器初始化:装 MySQL/Redis/nginx/JDK17、建库建表、
#      备份现有 nginx 站点并接管 80、装 systemd 服务
#   4. 自动生成数据库密码与 JWT 密钥并填入 env(免手工编辑)
#      Redis 默认无密码,会自动把 env 里的 AKI_REDIS_PASSWORD 置空;
#      想给 Redis 加密码就加 -SetRedisPassword
#   5. 本地构建 jar + 前端 dist 并上传
#   6. 启服务 + 端到端验证(登录接口、Redis 登录态、nginx 反代、路由回退)
#
# 为什么要有这个脚本:单独跑 server-init.sh + 手工 vi 改密码 + deploy.ps1
# 是一条容易出错的链路(密码字符集、jar 名、本地后端锁文件等),
# 这里把手动环节全部收敛成参数。
# =====================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Server,      # root@1.2.3.4
    [string]$Alias = 'aki',
    [switch]$SkipInit,                                   # 跳过服务器初始化(已初始化过)
    [switch]$SkipBuild,                                  # 跳过本地构建步骤
    [switch]$NoBuild,                                    # 直通给 deploy.ps1:用已有产物,不重新构建
    [switch]$SkipSql,                                    # 跳过重传 SQL(服务器上已有)
    [switch]$SetRedisPassword                            # 顺手给 Redis 设个密码并同步到 env
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$deployDir = $PSScriptRoot
$repoRoot  = Split-Path -Parent $deployDir

function Write-Step([string]$T) { Write-Host "`n========== $T ==========" -ForegroundColor Cyan }
function Write-Ok([string]$T)   { Write-Host "  [OK] $T" -ForegroundColor Green }
function Write-Warn2([string]$T){ Write-Host "  [!]  $T" -ForegroundColor Yellow }
function Write-Err([string]$T)  { Write-Host "  [X]  $T" -ForegroundColor Red }

$bash = 'C:\tools\git\bin\bash.exe'
$env:MSYS_NO_PATHCONV = '1'

# 调用原生命令(ssh/scp)的统一入口。
#
# 为什么需要这个包装:PowerShell 5.1 里原生命令往 stderr 写东西会产生
# NativeCommandError 记录,而 $ErrorActionPreference='Stop' 会让它升级成
# 【终止性错误】把整个脚本打断。ssh 在"连不上 / 解析不了主机名"时恰好就是
# 往 stderr 写错误 —— 于是本该是"探测失败 -> 去配置密钥"的正常分支,
# 变成了脚本直接崩在探测那一行(这就是第一次运行时的表现:
#   ssh.exe : ssh: Could not resolve hostname aki
#   + FullyQualifiedErrorId : NativeCommandError
# 连报两次,因为两次都在同一行崩掉,根本没走到配置密钥那一步)。
#
# 这里临时把 EAP 降为 Continue,让 stderr 只当普通输出被捕获,
# 由调用方按退出码判断,而不是让 PowerShell 替我们决定"这是致命错误"。
function Invoke-Native {
    param([string]$FilePath, [string[]]$Arguments, [string]$StdinText)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($PSBoundParameters.ContainsKey('StdinText') -and $null -ne $StdinText) {
            $out = $StdinText | & $FilePath @Arguments 2>&1
        } else {
            $out = & $FilePath @Arguments 2>&1
        }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $old
    }
    return @{ Output = @($out); Code = $code }
}

# 走 stdin 把脚本喂给远端 bash,省掉层层引号转义。
# BatchMode=yes:需要密码时立即失败,绝不卡在交互提示上。
#
# 【关键】必须把 CRLF 规范成 LF 再发。
# 本文件的行尾是 CRLF(工具写入时保留了 Windows 行尾),而 PowerShell 的
# here-string 会原样继承文件行尾 —— 于是每一行发给远端 bash 时都带一个 \r:
#   set -o pipefail\r            -> invalid option name,脚本开头就废
#   grep -qE "...CHANGE_ME\r"    -> 模式被污染,判断失效
#   .../aki-init.log'\r'         -> 文件名多出 \r,报 No such file or directory
#   test -f /etc/systemd/...service\r -> 恒为假,导致把"已部署"误判成"首次部署"
# 这些错误全都指向错误的方向,极难排查。统一在这里转换,一次解决。
function ConvertTo-Lf([string]$Text) {
    if ($null -eq $Text) { return '' }
    return ($Text -replace "`r`n", "`n" -replace "`r", "`n")
}

function Invoke-RemoteScript([string]$Script, [string]$Target) {
    return Invoke-Native -FilePath 'ssh' `
        -Arguments @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15', $Target, 'bash -s') `
        -StdinText (ConvertTo-Lf $Script)
}

# =====================================================
# 步骤 1:免密登录
# =====================================================
Write-Step "步骤 1/6  配置免密 SSH 登录"

# 探测别名能不能免密登录。失败是【正常分支】,不是错误 ——
# 所以必须用 Invoke-Native(内部 EAP=Continue),不能直接 & ssh 2>&1,
# 否则 stderr 会变成终止性错误。
$probe = (Invoke-Native -FilePath 'ssh' -Arguments @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', $Alias, 'echo AKI_OK')).Output
if (($probe -join "`n") -match 'AKI_OK') {
    Write-Ok "免密登录已就绪(别名 $Alias)"
} else {
    Write-Warn2 "别名 $Alias 还不能免密登录,现在开始配置"
    Write-Host "  接下来会生成密钥并提示输入 $Server 的密码 —— 这是全程唯一需要密码的地方。" -ForegroundColor Gray
    Write-Host "  如果服务器问是否接受主机指纹,输入 yes 回车。" -ForegroundColor Gray
    Write-Host "  (密钥生成时若弹出 passphrase 提示,直接回车留空,否则后续自动化会卡住)" -ForegroundColor Gray
    Write-Host ""

    # 关键:这一步【不能】捕获输出。
    # setup-ssh-key.ps1 里有一段交互式 ssh 会向终端索要密码,
    # 如果用 `$out = & powershell ... -File setup-ssh-key.ps1` 那样捕获,
    # 子进程的 stdout/stderr 会被重定向成管道,密码提示就看不见了,
    # 用户只能看到"卡住"。所以这里让子进程直接继承当前控制台
    # (PowerShell 的调用运算符 & 本身不会重定向子进程的 stdio)。
    $setupScript = Join-Path $deployDir 'setup-ssh-key.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $setupScript -Server $Server -Alias $Alias
    $setupCode = $LASTEXITCODE

    if ($setupCode -ne 0) {
        Write-Err ("免密登录配置失败(退出码 {0})" -f $setupCode)
        Write-Host "  单独重跑这一步看更详细的输出:" -ForegroundColor Gray
        Write-Host "    .\deploy\setup-ssh-key.ps1 -Server $Server -Alias $Alias" -ForegroundColor Gray
        exit 1
    }

    # 再探一次,确认别名真的可用了
    # (避免"配完了却因为 config 没生效而继续用别名失败")
    $probe2 = (Invoke-Native -FilePath 'ssh' -Arguments @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', $Alias, 'echo AKI_OK')).Output
    if (($probe2 -join "`n") -notmatch 'AKI_OK') {
        Write-Err "密钥配置完成后,别名 $Alias 仍无法免密登录"
        $probe2 | ForEach-Object { Write-Host "      $_" }
        Write-Host "  手动确认:" -ForegroundColor Gray
        Write-Host "    ssh -v $Alias 'echo ok'    # 看它到底用了哪个 config / 哪个密钥" -ForegroundColor Gray
        Write-Host "    type `$env:USERPROFILE\.ssh\config" -ForegroundColor Gray
        exit 1
    }
    Write-Ok "免密登录已生效"
}

# 目标一律用别名,后面就不需要密码了
$target = $Alias

# =====================================================
# 步骤 2:上传 SQL 与部署配置
# =====================================================
Write-Step "步骤 2/6  上传 SQL 与部署配置"

$sqlDir = Join-Path $repoRoot 'sql'
$tmpStage = Join-Path $env:TEMP "aki-stage-$(Get-Random)"
New-Item -ItemType Directory -Path $tmpStage -Force | Out-Null

# 服务器上期望的布局: /tmp/aki-deploy/{deploy/*, sql/*}
# server-init.sh 会按 "脚本所在目录/../sql" 找 init.sql,所以必须保持这个层级
Copy-Item (Join-Path $sqlDir '*.sql') $tmpStage -Force
Copy-Item (Join-Path $deployDir 'server-init.sh')     $tmpStage -Force
Copy-Item (Join-Path $deployDir 'nginx.conf')         $tmpStage -Force
Copy-Item (Join-Path $deployDir 'aki-admin.service')  $tmpStage -Force
Copy-Item (Join-Path $deployDir 'aki-admin.env.example') $tmpStage -Force

$r = Invoke-RemoteScript 'rm -rf /tmp/aki-deploy && mkdir -p /tmp/aki-deploy/deploy /tmp/aki-deploy/sql' $target
if ($r.Code -ne 0) { throw "创建远端目录失败" }

# 用 scp 传目录内容:sql 归到 sql/,脚本与配置归到 deploy/。
# 同样走 Invoke-Native:scp 的进度与告警都写在 stderr 上,
# 在 EAP=Stop 下裸调用会被判成致命错误。
$scp1 = Invoke-Native -FilePath 'scp' -Arguments @(
    '-q', (Join-Path $tmpStage '*.sql'), "${target}:/tmp/aki-deploy/sql/"
)
if ($scp1.Code -ne 0) {
    Write-Err "上传 sql 失败(退出码 $($scp1.Code))"
    $scp1.Output | ForEach-Object { Write-Host "      $_" }
    throw "上传 sql 失败"
}

$scp2 = Invoke-Native -FilePath 'scp' -Arguments @(
    '-q',
    (Join-Path $tmpStage 'server-init.sh'),
    (Join-Path $tmpStage 'nginx.conf'),
    (Join-Path $tmpStage 'aki-admin.service'),
    (Join-Path $tmpStage 'aki-admin.env.example'),
    "${target}:/tmp/aki-deploy/deploy/"
)
if ($scp2.Code -ne 0) {
    Write-Err "上传部署配置失败(退出码 $($scp2.Code))"
    $scp2.Output | ForEach-Object { Write-Host "      $_" }
    throw "上传部署配置失败"
}
Remove-Item $tmpStage -Recurse -Force
Write-Ok "已上传到 /tmp/aki-deploy/(布局: deploy/ 与 sql/ 同级)"

# =====================================================
# 步骤 3:服务器初始化
# =====================================================
if (-not $SkipInit) {
    Write-Step "步骤 3/6  服务器初始化(装环境 + 建库 + 配服务)"
    Write-Host "  这一步要几分钟(apt 装 MySQL/Redis/nginx + JDK17),期间不要中断..." -ForegroundColor Gray

    # 关键:退出码不能靠 `echo "...: $rc"` 这种文本约定来传。
    #
    # 之前就是这么写的,结果翻车:echo 的输出混进了变量捕获,远端看到的是
    #   server-init.sh ???: 0        <- 本应是"退出码: 0"
    # 于是 `exit $rc` 拿到非数字,报 ": numeric argument required" 并以退出码 2 结束,
    # 让一次【实际成功的初始化】被判成失败(白跑一趟几十分钟)。
    #
    # 现在改成:把退出码写进一个文件,由外层单独读那个文件。
    # 文本流怎么乱都不影响这个数字,而且 echo 一律重定向到 stderr,
    # 彻底避免和要解析的内容混在一起。
    $initScript = @'
set -o pipefail
if [ -f /etc/systemd/system/aki-admin.service ] && [ -d /opt/aki-admin ]; then
  echo "existing aki_sys install detected - re-running init (idempotent)" >&2
fi

sudo bash /tmp/aki-deploy/deploy/server-init.sh > /tmp/aki-init.log 2>&1
rc=$?

{
  echo "---------- server-init.sh output (last 60 lines) ----------"
  tail -n 60 /tmp/aki-init.log
  echo "---------- end of output ----------"
  echo "server-init.sh exit code: ${rc}"
} >&2

# 成功标记,由本脚本自己打印,客户端按标记判断成败。
#
# 为什么不再用"读退出码文件 + 客户端解析数字"那套:
# (a) 退出码经 stdin 传脚本这条链路回来可能被污染;
# (b) 更糟的是客户端做 -replace '[^0-9]','' 提取数字时,
#     遇到乱码错误信息里的数字串会拼出一个天文数字(实测:
#     ssh: Could not resolve hostname ...: \262\273\326\252... -> 解析成 262273326252...),
#     于是"成功"被判成失败。用标记判断就没有这类解析歧义。
if [ "$rc" -eq 0 ]; then
  echo "AKI_INIT_OK"
else
  echo "AKI_INIT_FAIL rc=${rc}"
fi

exit "$rc"
'@
    $r = Invoke-RemoteScript $initScript $target
    $r.Output | ForEach-Object { Write-Host "  $_" }

    $joined = ($r.Output -join "`n")
    if ($joined -match 'AKI_INIT_OK') {
        Write-Ok "服务器初始化完成"
    } else {
        Write-Err "服务器初始化失败"
        Write-Host "  判定依据:远端没有输出成功标记 AKI_INIT_OK" -ForegroundColor Gray
        Write-Host "  远端命令退出码: $($r.Code)" -ForegroundColor Gray
        Write-Host "  完整日志在服务器上,直接看这几条:" -ForegroundColor Gray
        Write-Host "    ssh $target 'tail -n 80 /tmp/aki-init.log'" -ForegroundColor Gray
        Write-Host "    ssh $target 'grep -nE \"\[X\]|失败|ERROR|error\" /tmp/aki-init.log | tail -n 20'" -ForegroundColor Gray
        exit 1
    }
} else {
    Write-Step "步骤 3/6  跳过服务器初始化(-SkipInit)"
}

# =====================================================
# 步骤 4:生成密钥 / 配置 env
# =====================================================
Write-Step "步骤 4/6  配置 /etc/aki-admin/aki-admin.env"

$secretScript = @'
set -uo pipefail
ENV_FILE=/etc/aki-admin/aki-admin.env
if ! sudo test -f "$ENV_FILE"; then
  echo "ERROR: $ENV_FILE not found - init may have failed"
  exit 1
fi

# 先确认免密 sudo 真的可用。
# 如果 sudo 要密码,后面的 sudo cat 会失败,ENV_TXT 变空,
# 判断又会走偏(把已填的密码当成没填)—— 宁可在这一步就明确报出来。
if ! sudo -n true 2>/dev/null; then
  echo "ERROR: passwordless sudo unavailable; cannot read/write $ENV_FILE (mode 600 root)"
  echo "       fix: echo '\$(id -un) ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/aki-deploy && sudo chmod 440 /etc/sudoers.d/aki-deploy"
  exit 1
fi

# env 文件是 600 root,必须以 root 身份读。
#
# 这一点之前写错过:读它用的是裸 grep,普通用户读不到就【静默返回空】,
# 于是一连串判断全部走偏 —— 以为密码没填(其实填了),还会拿空密码去建
# MySQL 账号,最后表现为"配好了却连不上"。所以下面统一:
#   读 -> 一次 sudo cat 拿全文,后续用 shell 变量解析,不再反复 sudo
#   写 -> sudo sed -i
ENV_TXT="$(sudo cat "$ENV_FILE")"

if [ -z "$ENV_TXT" ]; then
  echo "ERROR: read empty content from $ENV_FILE; cannot proceed reliably"
  exit 1
fi
echo "  read $ENV_FILE ($(printf '%s\n' "$ENV_TXT" | wc -l) lines)"

# 从 ENV_TXT 里取某个键的值(去掉引号与 CR)
env_get() {
  printf '%s\n' "$ENV_TXT" \
    | grep -E "^[[:space:]]*$1=" \
    | tail -n1 \
    | cut -d= -f2- \
    | tr -d '"'"'"'\r' || true
}

gen_hex() { openssl rand -hex 24; }

# --- 数据库密码:仍是占位符或为空就生成一个(纯 hex,天然满足字符集要求)---
CUR_DB_PW="$(env_get AKI_DB_PASSWORD)"
if [ -z "$CUR_DB_PW" ] || [ "$CUR_DB_PW" = "CHANGE_ME" ] || [ "$CUR_DB_PW" = "CHANGE_ME_openssl_rand_base64_48" ]; then
  PW="$(gen_hex)"
  sudo sed -i "s|^[[:space:]]*AKI_DB_PASSWORD=.*|AKI_DB_PASSWORD=${PW}|" "$ENV_FILE"
  ENV_TXT="$(sudo cat "$ENV_FILE")"
  echo "  generated DB password (pure hex, charset-safe)"
else
  echo "  DB password already set, keeping it"
fi

# --- JWT 密钥:server-init.sh 通常已填好,这里只兜底 ---
CUR_JWT="$(env_get AKI_JWT_SECRET)"
if [ -z "$CUR_JWT" ] || [ "$CUR_JWT" = "CHANGE_ME" ] || [ "$CUR_JWT" = "CHANGE_ME_openssl_rand_base64_48" ]; then
  JWT="$(openssl rand -hex 48)"
  sudo sed -i "s|^[[:space:]]*AKI_JWT_SECRET=.*|AKI_JWT_SECRET=${JWT}|" "$ENV_FILE"
  ENV_TXT="$(sudo cat "$ENV_FILE")"
  echo "  generated JWT secret"
else
  echo "  JWT secret already set, keeping it"
fi

# --- 按 env 里的密码,在 MySQL 里建/对齐 aki 账号 ---
PW="$(env_get AKI_DB_PASSWORD)"
USER_="$(env_get AKI_DB_USERNAME)"
DBNAME="$(env_get AKI_DB_NAME)"
USER_="${USER_:-aki}"; DBNAME="${DBNAME:-aki_sys}"

if [ -n "$PW" ] && [ "$PW" != "CHANGE_ME" ]; then
  if sudo mysql -N -B -e "SELECT 1" >/dev/null 2>&1; then
    sudo mysql --execute="CREATE USER IF NOT EXISTS '${USER_}'@'127.0.0.1' IDENTIFIED BY '${PW}'; ALTER USER '${USER_}'@'127.0.0.1' IDENTIFIED BY '${PW}'; GRANT ALL PRIVILEGES ON ${DBNAME}.* TO '${USER_}'@'127.0.0.1'; FLUSH PRIVILEGES;" \
      && echo "  MySQL user ${USER_}@127.0.0.1 synced to the password in env" \
      || echo "  WARN: failed to create MySQL user"
  else
    echo "  WARN: cannot connect to MySQL without password; skipped user sync (service may fail to reach DB)"
  fi
fi

# --- 可选的 Redis 密码 ---
if [ "${AKI_SET_REDIS_PW:-0}" = "1" ]; then
  RPW="$(gen_hex)"
  for c in /etc/redis/redis.conf /etc/redis.conf; do
    # redis.conf 是 640 root:redis,普通用户读不到,所以判断也要 sudo
    sudo test -f "$c" || continue
    if sudo grep -qE '^[[:space:]]*requirepass ' "$c"; then
      sudo sed -i "s|^[[:space:]]*requirepass .*|requirepass ${RPW}|" "$c"
    elif sudo grep -qE '^[[:space:]]*# *requirepass ' "$c"; then
      sudo sed -i "s|^[[:space:]]*# *requirepass .*|requirepass ${RPW}|" "$c"
    else
      echo "requirepass ${RPW}" | sudo tee -a "$c" >/dev/null
    fi
    sudo systemctl restart redis-server 2>/dev/null || sudo systemctl restart redis 2>/dev/null || true
    sudo sed -i "s|^[[:space:]]*AKI_REDIS_PASSWORD=.*|AKI_REDIS_PASSWORD=${RPW}|" "$ENV_FILE"
    ENV_TXT="$(sudo cat "$ENV_FILE")"
    echo "  Redis password set and synced to env"
    break
  done
else
  # Redis 没设密码时,env 里的 AKI_REDIS_PASSWORD 必须为空,
  # 否则 Spring 会拿一个错误密码去 AUTH,直接连不上。
  # 判空用 sudo redis-cli:普通用户执行 redis-cli 连的是同一个本地实例,
  # 但若 socket/端口权限受限会误判,统一加 sudo 更稳。
  CUR="$(env_get AKI_REDIS_PASSWORD)"
  if [ -n "$CUR" ]; then
    if sudo redis-cli ping >/dev/null 2>&1; then
      sudo sed -i "s|^[[:space:]]*AKI_REDIS_PASSWORD=.*|AKI_REDIS_PASSWORD=|" "$ENV_FILE"
      ENV_TXT="$(sudo cat "$ENV_FILE")"
      echo "  Redis has no password -> AKI_REDIS_PASSWORD blanked in env"
    else
      echo "  WARN: redis-cli not responding; left AKI_REDIS_PASSWORD untouched"
    fi
  fi
fi

echo "  --- env key items (secrets masked) ---"
sudo grep -E '^(AKI_PORT|AKI_DB_HOST|AKI_DB_NAME|AKI_DB_USERNAME|AKI_REDIS_HOST)=' "$ENV_FILE" | sed 's/^/    /'
# 用 env_get 判断而不是 grep -c:grep 在 600 文件上要 sudo,且 -c 的输出还要再 sed,
# 层层管道容易出错;env_get 读的是已经拿到手的 $ENV_TXT,最可靠。
FINAL_DB="$(env_get AKI_DB_PASSWORD)"
FINAL_JWT="$(env_get AKI_JWT_SECRET)"
FINAL_REDIS="$(env_get AKI_REDIS_PASSWORD)"
if [ -n "$FINAL_DB" ] && [ "$FINAL_DB" != "CHANGE_ME" ]; then echo "    AKI_DB_PASSWORD    : filled (${#FINAL_DB} chars)"; else echo "    AKI_DB_PASSWORD    : STILL PLACEHOLDER/EMPTY"; fi
if [ -n "$FINAL_JWT" ] && [ "$FINAL_JWT" != "CHANGE_ME" ]; then echo "    AKI_JWT_SECRET     : filled (${#FINAL_JWT} chars)"; else echo "    AKI_JWT_SECRET     : STILL PLACEHOLDER/EMPTY"; fi
if [ -z "$FINAL_REDIS" ]; then echo "    AKI_REDIS_PASSWORD : empty (Redis has no password, as expected)"; else echo "    AKI_REDIS_PASSWORD : filled (${#FINAL_REDIS} chars)"; fi

# 成功标记(和步骤 3 同一套协议)。
# 不再依赖退出码:实测退出码经这条 stdin 链路回来会变成 2 并附带
# "numeric argument required",把一次成功的配置报成失败。
if [ -n "$FINAL_DB" ] && [ "$FINAL_DB" != "CHANGE_ME" ] && [ -n "$FINAL_JWT" ] && [ "$FINAL_JWT" != "CHANGE_ME" ]; then
  echo "AKI_STEP4_OK"
else
  echo "AKI_STEP4_FAIL"
fi
exit 0
'@

$redisFlag = if ($SetRedisPassword) { '1' } else { '0' }
$r = Invoke-RemoteScript ("export AKI_SET_REDIS_PW=$redisFlag`n" + $secretScript) $target
$r.Output | ForEach-Object { Write-Host "  $_" }

# 按标记判断,不看退出码(退出码在这条链路上不可靠,详见上面的注释)
if (($r.Output -join "`n") -notmatch 'AKI_STEP4_OK') {
    Write-Err "env 配置失败(未输出成功标记 AKI_STEP4_OK)"
    Write-Host "  远端命令退出码: $($r.Code)(此值在本链路不可靠,仅作参考)" -ForegroundColor Gray
    Write-Host "  请手动检查服务器的 /etc/aki-admin/aki-admin.env:" -ForegroundColor Gray
    Write-Host "    ssh $target 'sudo grep -E \"^AKI_(DB_PASSWORD|JWT_SECRET)\" /etc/aki-admin/aki-admin.env | cut -c1-40'" -ForegroundColor Gray
    exit 1
}
Write-Ok "env 配置完成"

# =====================================================
# 步骤 5:本地构建
# =====================================================
if (-not $SkipBuild) {
    Write-Step "步骤 5/6  本地构建(后端 jar + 前端 dist)"
} else {
    Write-Step "步骤 5/6  跳过本地构建(-SkipBuild)"
}

# =====================================================
# 步骤 6:上传产物并启动
# =====================================================
Write-Step "步骤 6/6  上传产物、启动服务并验证"

$deployArgs = @{ Server = $target }
# -NoBuild 或 -SkipBuild 都表示"用已有产物,不要再跑 Maven/Vite"
if ($NoBuild -or $SkipBuild) { $deployArgs['NoBuild'] = $true }
if ($SkipSql) { $deployArgs['SkipSql'] = $true }

# deploy.ps1 内部出错时是 throw(不是 exit),所以要接住异常,
# 否则 $LASTEXITCODE 判断不到,脚本会带着错误继续往下跑"端到端验证"。
try {
    & (Join-Path $deployDir 'deploy.ps1') @deployArgs
} catch {
    Write-Err "deploy.ps1 执行失败: $($_.Exception.Message)"
    Write-Host "  修好上面的问题后可以只重跑这一步:" -ForegroundColor Gray
    Write-Host "    .\deploy\deploy.ps1 -Server $Alias" -ForegroundColor Gray
    exit 1
}
if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
    Write-Err "deploy.ps1 失败(退出码 $LASTEXITCODE)"
    exit 1
}

# ---------- 端到端验证 ----------
Write-Step "端到端验证"

$verifyScript = @'
set -uo pipefail
echo "--- service status ---"
echo "  aki-admin : $(sudo systemctl is-active aki-admin 2>/dev/null || echo unknown)"
echo "  nginx     : $(sudo systemctl is-active nginx 2>/dev/null || echo unknown)"
echo "  mysql     : $(sudo systemctl is-active mysql 2>/dev/null || sudo systemctl is-active mysqld 2>/dev/null || echo unknown)"
echo "  redis     : $(sudo systemctl is-active redis-server 2>/dev/null || sudo systemctl is-active redis 2>/dev/null || echo unknown)"

echo "--- backend direct (expect 401 unauth: process alive + auth interceptor active) ---"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1:8080/api/auth/me || echo 000)
echo "  /api/auth/me -> HTTP $code  (401/200 both fine; 000 means not up)"

echo "--- database tables ---"
if sudo mysql -N -B -e "SELECT 1" >/dev/null 2>&1; then
  sudo mysql -N -B -e "SELECT table_name FROM information_schema.tables WHERE table_schema='aki_sys' ORDER BY table_name" 2>/dev/null | tr '\n' ' ' | sed 's/^/  /'
  echo
  echo "  sys_user rows: $(sudo mysql -N -B -e "SELECT COUNT(*) FROM aki_sys.sys_user" 2>/dev/null || echo 'query-failed')"
else
  echo "  cannot query DB without password"
fi

echo "--- login API test (real MySQL + Redis round trip) ---"
resp=$(curl -s --max-time 10 -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin123"}' \
  http://127.0.0.1:8080/api/auth/login || echo '')
if echo "$resp" | grep -q '"code":200'; then
  echo "  LOGIN OK (admin/admin123 works)"
  TOKEN=$(echo "$resp" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
  echo "  token length: ${#TOKEN}"
  me=$(curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8080/api/auth/me || echo '')
  echo "$me" | grep -q '"nickname"' && echo "  GET /api/auth/me with token OK -> Redis whitelist works" || echo "  WARN: authed request failed: $me"
else
  echo "  LOGIN FAILED, response: $(echo "$resp" | head -c 300)"
  echo "  check: sudo tail -n 50 /var/log/aki-admin/aki-admin.log"
fi

echo "--- via nginx (port 80, frontend) ---"
curl -s -o /dev/null -w "  http://127.0.0.1/ -> HTTP %{http_code}\n" --max-time 8 http://127.0.0.1/ || echo "  nginx not responding"
echo "  page title: $(curl -s --max-time 8 http://127.0.0.1/ | grep -o '<title>[^<]*</title>' | head -n1)"

echo "--- SPA fallback (should be 200, not 404) ---"
curl -s -o /dev/null -w "  /admin/system/user -> HTTP %{http_code}\n" --max-time 8 http://127.0.0.1/admin/system/user || true

echo "--- API via nginx proxy (expect 401 body, not 404) ---"
curl -s --max-time 8 http://127.0.0.1/api/auth/me | head -c 200
echo

echo "--- recent app log ---"
sudo tail -n 15 /var/log/aki-admin/aki-admin.log 2>/dev/null | sed 's/^/  /'
exit 0
'@

$r = Invoke-RemoteScript $verifyScript $target
$r.Output | ForEach-Object { Write-Host "  $_" }

Write-Step "部署结束"
Write-Host @"
  访问地址: http://47.120.68.160/
  默认账号: admin / admin123   <-- 登录后请立刻改密码

  下一步(建议):
    1) 改 root 密码(你之前在聊天里发过):  ssh $Alias 'passwd'
    2) 关闭 SSH 密码登录(先确认新窗口能进!):
         ssh $Alias "sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && sudo systemctl restart sshd"
    3) 以后发版只需:  .\deploy\deploy.ps1 -Server $Alias

  常用排查:
    ssh $Alias 'sudo tail -f /var/log/aki-admin/aki-admin.log'
    ssh $Alias 'sudo journalctl -u aki-admin -n 100'
"@ -ForegroundColor Gray
