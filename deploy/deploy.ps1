#!/usr/bin/env pwsh
# =====================================================
# aki_sys 一键部署脚本(在本地 Windows 上执行)
#
#   1. 本地 Maven 打包后端      -> backend/target/aki-admin-1.0.0.jar
#   2. 本地 Vite 构建前端       -> frontend/dist
#   3. scp 上传 jar,ssh 解包前端,重启 systemd 服务
#
# 服务器上不需要装 Maven 和 Node。
#
# 用法(必须显式写参数,避免误操作):
#   .\deploy\deploy.ps1 -Server root@1.2.3.4
#   .\deploy\deploy.ps1 -Server deploy@aki.example.com -IdentityFile C:\Users\111\.ssh\aki_deploy
#   .\deploy\deploy.ps1 -Server root@1.2.3.4 -SkipBackend     # 只发前端
#   .\deploy\deploy.ps1 -Server root@1.2.3.4 -SkipFrontend    # 只发后端
#   .\deploy\deploy.ps1 -Server root@1.2.3.4 -NoBuild        # 用已有产物直接上传
#
# 前置条件:
#   - 本地能直接 ssh $Server 免密登录(已配好密钥)。
#     没配的话先执行:sshd 密钥生成 + ssh-copy-id,或让 DSH 帮你配 ~/.ssh/config。
#   - 服务器上已执行过 deploy/server-init.sh。
#   - 若登录用户不是 root,需要配置免密 sudo(server-init.sh 里会打印这条命令)。
# =====================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Server,
    [string]$IdentityFile,
    [string]$JarName     = 'aki-admin-1.0.0.jar',
    # 上传到服务器后的文件名。必须与 aki-admin.service 的 ExecStart 完全一致,
    # 否则 systemd 找不到 jar,直接报 "Unable to access jarfile"。
    # 故意不带版本号:每次发版同名覆盖,服务配置永远不用改。
    [string]$RemoteJarName = 'aki-admin.jar',
    [string]$RemoteApp   = '/opt/aki-admin',
    [string]$ServiceName = 'aki-admin',
    [switch]$SkipBackend,
    [switch]$SkipFrontend,
    [switch]$NoBuild,
    [switch]$SkipSql
)

$ErrorActionPreference = 'Stop'

# 统一命令输出的编码,中文提示在 PS 5.1 / 7 下都不乱码。
# 注意:本文件必须保存为【UTF-8 带 BOM】。PowerShell 5.1 对无 BOM 的 UTF-8
# 会按系统 ANSI 代码页(中文 Windows 是 GBK)解码,中文注释和提示全变乱码,
# 这一点和仓库里 scripts/*.ps1 的约定一致。
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch { }

# BOM 自检。
# 为什么值得加这几行:很多编辑器和脚本化改动会把 BOM 悄悄吃掉,一旦丢了,
# PowerShell 5.1 就按 GBK 解码本文件,中文提示全变乱码 —— 而且报错位置会
# 指向文件中段,极难联想到编码问题(这次开发就踩了)。这里主动检测并给出修复命令。
try {
    $selfBytes = [System.IO.File]::ReadAllBytes($PSCommandPath)
    $hasBom = ($selfBytes.Length -ge 3 -and $selfBytes[0] -eq 0xEF -and $selfBytes[1] -eq 0xBB -and $selfBytes[2] -eq 0xBF)
    if (-not $hasBom) {
        Write-Host "  [!] deploy.ps1 是 UTF-8 无 BOM —— PowerShell 5.1 下中文提示会变成乱码。" -ForegroundColor Yellow
        Write-Host "      修复(立即执行一次即可):" -ForegroundColor Gray
        Write-Host "        `$p='$PSCommandPath'; `$t=[IO.File]::ReadAllText(`$p,[Text.UTF8Encoding]::new(`$false)); [IO.File]::WriteAllText(`$p,`$t,[Text.UTF8Encoding]::new(`$true))" -ForegroundColor Gray
    }
} catch { }

$repoRoot = Split-Path -Parent $PSScriptRoot
$backendDir = Join-Path $repoRoot 'backend'
$frontendDir = Join-Path $repoRoot 'frontend'

function Write-Step([string]$Text) { Write-Host "`n=== $Text ===" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "  [OK] $Text"   -ForegroundColor Green }
function Write-Warn2([string]$Text){ Write-Host "  [!]  $Text"   -ForegroundColor Yellow }
function Write-Err([string]$Text)  { Write-Host "  [X]  $Text"   -ForegroundColor Red }

# 把本地路径统一成正斜杠再交给原生命令(tar / mvn / java)。
# Windows 下 C:\a\b 反斜杠在个别原生工具里会被当成转义字符,
# 正斜杠在 Windows 上同样被接受,统一后省掉一类偶发问题。
function ConvertTo-NativePath([string]$Path) { return ($Path -replace '\\', '/') }

# 检查产物文件是否被占用。
# 必要性:本地 start-all.bat 起着的后端进程(或 IDE 打开着 jar)会锁住
# target/*.jar,此时 spring-boot:repackage 会失败并抛出
# "Unable to rename '...jar' to '...jar.original'" —— 这个报错完全看不出
# 真实原因,还可能在 target 里留下一个 0 字节的残缺 jar。
# 提前用独占方式打开一次,直接把原因说清楚。
function Test-FileLocked([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'ReadWrite', 'None')
        $fs.Close()
        return $false
    } catch {
        return $true
    }
}
function Assert-NotLocked([string]$Path, [string]$Hint) {
    if (Test-FileLocked $Path) {
        Write-Err "文件被占用,无法覆盖: $Path"
        Write-Host "      $Hint" -ForegroundColor Gray
        throw "目标文件被其他进程占用"
    }
}

# 找出本机上监听某个端口的进程 id(排除 PID 0/4 这类系统进程)
function Get-PortOwner([int]$Port) {
    $ids = @()
    try {
        $ids = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
               Select-Object -ExpandProperty OwningProcess -Unique
    } catch { }
    if (-not $ids -or $ids.Count -eq 0) {
        # Get-NetTCPConnection 在个别环境不可用,退回 netstat
        try {
            $ids = (netstat -ano | Select-String ":$Port\s+.*LISTENING") |
                   ForEach-Object { ($_ -split '\s+')[-1] } | Select-Object -Unique
        } catch { }
    }
    return @($ids | Where-Object { $_ -and $_ -ne 0 -and $_ -ne 4 })
}

# 准备本地文件:被占用时自动停掉本地后端。
# 为什么值得自动做:本地 start-all.bat 起着的后端(8080)会锁住 target 里的 jar,
# 导致 Maven repackage 报一个完全看不懂的
# "Unable to rename '...jar' to '...jar.original'"。
# 用户每次发版都要记得先停本地服务,是个很容易忘、忘了就浪费半天的坑。
# 只停本机 8080 上的进程(就是本地后端),不动 MySQL,也不碰服务器。
function Stop-LocalBackendIfNeeded([string]$JarPath) {
    if (-not (Test-FileLocked $JarPath)) { return }

    Write-Warn2 "$([System.IO.Path]::GetFileName($JarPath)) 被占用(本地后端还在跑,它锁着 jar)"
    $pids = Get-PortOwner 8080
    if ($pids.Count -eq 0) {
        Write-Warn2 "本机 8080 上没有监听的进程,但文件仍被占用 —— 可能是编辑器/杀毒软件打开着它"
        Write-Host @"
      请先关掉占用该文件的程序再重试。定位占用进程:
        netstat -ano | findstr :8080
        tasklist /FI "PID eq <上面查到的PID>"
"@ -ForegroundColor Gray
        throw "构建产物被占用"
    }

    foreach ($procId in $pids) {
        $pname = '未知'
        try { $pname = (Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch { }
        Write-Host "  停止本地进程: PID $procId ($pname)" -ForegroundColor Gray
        try {
            Stop-Process -Id $procId -Force -ErrorAction Stop
        } catch {
            Write-Err "停止 PID $procId 失败: $($_.Exception.Message)"
            throw "无法停止占用 8080 的本地进程"
        }
    }

    # 等文件锁真正释放
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        if (-not (Test-FileLocked $JarPath)) {
            Write-Ok "本地后端已停止,jar 已解锁"
            return
        }
    }
    throw "停止进程后 jar 仍被占用,请手动处理后重试"
}

# ---------- ssh / scp 公共参数 ----------
$sshArgs = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10')
$scpArgs = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10')
if ($IdentityFile) {
    if (-not (Test-Path $IdentityFile)) { throw "密钥文件不存在: $IdentityFile" }
    $sshArgs += @('-i', $IdentityFile)
    $scpArgs += @('-i', $IdentityFile)
}

# 调用原生命令的统一入口。
#
# 为什么必须包装:PowerShell 5.1 里原生命令往 stderr 写内容会产生
# NativeCommandError,而本脚本是 $ErrorActionPreference='Stop',会把它升级成
# 【终止性错误】直接打断脚本。ssh 往 stderr 写东西极其常见 —— 连接告警、
# 主机指纹提示、`grep` 没匹配到(退出码 1)、systemctl 的输出等等。
# 之前 Invoke-Remote / Invoke-RemoteSh 用 `... 2>&1` 捕获,正好踩中这个坑:
# 远端任何一句看似无害的 stderr 输出都会让部署在那一行莫名中断。
#
# 实测确认:函数内部改 $ErrorActionPreference 只作用于该函数(局部变量),
# 不影响调用方,所以包装既能兜住原生命令的 stderr,又保留了全局的严格模式。
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

function Invoke-Remote([string]$Command) {
    $r = Invoke-Native -FilePath 'ssh' -Arguments ($sshArgs + @($Server, $Command))
    if ($r.Code -ne 0) {
        Write-Err "远程命令失败: $Command"
        $r.Output | ForEach-Object { Write-Host "      $_" }
        throw "远程执行失败(退出码 $($r.Code))"
    }
    return $r.Output
}
# 把 CRLF 规范成 LF 再交给远端 bash。
#
# 【必须做】本文件行尾是 CRLF,PowerShell 的 here-string 会原样继承 ——
# 于是每一行发给远端 bash 都带一个 \r,造成:
#   set -o pipefail\r  -> invalid option name
#   .../aki-init.log'\r' -> No such file or directory
#   test -f ...service\r -> 恒假,把"已部署"误判成"首次部署"
# 这些报错全都指向错误方向,统一在此转换。
function ConvertTo-Lf([string]$Text) {
    if ($null -eq $Text) { return '' }
    return ($Text -replace "`r`n", "`n" -replace "`r", "`n")
}

function Invoke-RemoteSh([string]$Script) {
    # 走 stdin 传脚本,省掉多层引号转义
    $r = Invoke-Native -FilePath 'ssh' -Arguments ($sshArgs + @($Server, 'bash -s')) -StdinText (ConvertTo-Lf $Script)
    if ($r.Code -ne 0) {
        Write-Err "远程脚本执行失败"
        $r.Output | ForEach-Object { Write-Host "      $_" }
        throw "远程执行失败(退出码 $($r.Code))"
    }
    return $r.Output
}

# scp 上传的统一入口。走 Invoke-Native 的原因同上:
# scp 的告警/进度写在 stderr 上,EAP=Stop 下裸调用会被当成致命错误。
# 返回退出码,由调用方决定是否致命(例如发前端包时 scp 失败必须中断,
# 否则后面解包会把 web 目录清空 —— 那种静默后果比报错严重得多)。
function Invoke-Upload {
    param([string[]]$Paths, [string]$Destination)
    $r = Invoke-Native -FilePath 'scp' -Arguments ($scpArgs + @($Paths) + @($Destination))
    if ($r.Code -ne 0) {
        $r.Output | ForEach-Object { Write-Host "      $_" }
    }
    return $r.Code
}

# =====================================================
# 0. 预检
# =====================================================
Write-Step "预检:连接 $Server"

foreach ($cmd in 'ssh', 'scp', 'tar') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "本地缺少命令 $cmd(ssh/scp/tar 由 Windows 10+ 自带,请检查 PATH)"
    }
}

try {
    $who = Invoke-Remote 'echo "$(whoami)@$(hostname)"'
    Write-Ok "SSH 免密登录正常: $who"
} catch {
    Write-Err "无法免密登录 $Server"
    Write-Host @"
      请在本地先配置好密钥登录(任选一种):
        a) 生成密钥并上传公钥:
             ssh-keygen -t ed25519 -f `$env:USERPROFILE\.ssh\aki_deploy
             type `$env:USERPROFILE\.ssh\aki_deploy.pub | ssh $Server "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
        b) 或在 ~/.ssh/config 里写好 Host 别名后用别名当 -Server 参数。
"@ -ForegroundColor Gray
    exit 1
}

# 非 root 时需要免密 sudo,否则后面的 systemctl 会卡在密码提示
$loginUser = (Invoke-Remote 'id -un' | Select-Object -First 1).ToString().Trim()
$sudoPrefix = 'sudo -n '
if ($loginUser -eq 'root') {
    $sudoPrefix = ''
    Write-Ok "登录用户是 root,无需 sudo"
} else {
    try {
        Invoke-Remote 'sudo -n true' | Out-Null
        Write-Ok "免密 sudo 可用"
    } catch {
        Write-Err "用户 $loginUser 没有免密 sudo 权限"
        Write-Host "      在服务器上执行(把 USER 换成你的用户名):" -ForegroundColor Gray
        Write-Host "        echo 'USER ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/aki-deploy && sudo chmod 440 /etc/sudoers.d/aki-deploy" -ForegroundColor Gray
        exit 1
    }
}

# 服务器目录存在性
try {
    Invoke-Remote "test -d $RemoteApp" | Out-Null
    Write-Ok "远程目录存在: $RemoteApp"
} catch {
    Write-Err "远程目录 $RemoteApp 不存在 —— 先在服务器上执行 deploy/server-init.sh"
    exit 1
}

# 生产配置的占位符检查。
# 不检查的话,部署会一路"成功",最后只看到服务起不来,而真实原因
# (env 里还是 CHANGE_ME)埋在 journalctl 里,白折腾一轮。
# Invoke-Remote 在远程退出码非 0 时抛异常:grep 命中(退出码 0)不抛,
# grep 没命中(退出码 1)抛 —— 所以"命中"要靠设标志位而不是 catch 来判定。
$placeholderHit = $false
try { Invoke-Remote 'grep -qE "^[[:space:]]*(AKI_DB_PASSWORD|AKI_REDIS_PASSWORD|AKI_JWT_SECRET)=[[:space:]]*CHANGE_ME" /etc/aki-admin/aki-admin.env' | Out-Null; $placeholderHit = $true } catch { $placeholderHit = $false }
if ($placeholderHit) {
    Write-Err "/etc/aki-admin/aki-admin.env 里还有未填写的 CHANGE_ME 占位符"
    Write-Host "      后端会因连不上 MySQL/Redis 而启动失败,先填好再部署:" -ForegroundColor Gray
    Write-Host "        ssh $Server 'sudo vi /etc/aki-admin/aki-admin.env'" -ForegroundColor Gray
    Write-Host "      (数据库密码只能用字母数字和 . _ @ # % ^ + = -,禁用反斜杠和 $)" -ForegroundColor Gray
    exit 1
}
Write-Ok "生产环境变量已填写(无 CHANGE_ME 占位符)"

# =====================================================
# 0.5 首次部署:上传 SQL 脚本并自动装好 systemd / nginx 配置
# =====================================================
if (-not $SkipSql) {
    Write-Step '上传 SQL 脚本到服务器 /tmp/aki-sql'
    $sqlDir = Join-Path $repoRoot 'sql'
    $sqlFiles = @('init.sql', 'homepage_init.sql')
    $toUpload = $sqlFiles | ForEach-Object { Join-Path $sqlDir $_ } | Where-Object { Test-Path $_ }
    if ($toUpload.Count -gt 0) {
        Invoke-Remote 'rm -rf /tmp/aki-sql && mkdir -p /tmp/aki-sql' | Out-Null
        if ((Invoke-Upload -Paths $toUpload -Destination "${Server}:/tmp/aki-sql/") -ne 0) { throw 'scp 上传 SQL 失败' }
        Write-Ok "已上传: $(($toUpload | ForEach-Object { Split-Path $_ -Leaf }) -join ', ')"
    } else {
        Write-Warn2 "本地 sql/ 下没找到 init.sql / homepage_init.sql,跳过"
    }
}

# 配置文件(target 服务不存在 = 第一次部署,顺手装好并启用)
try {
    Invoke-Remote "test -f /etc/systemd/system/$ServiceName.service" | Out-Null
    Write-Ok "systemd 服务已存在,跳过配置安装"
} catch {
    Write-Step '首次部署:安装 systemd / nginx / env 配置'

    $initScript = Join-Path $PSScriptRoot 'server-init.sh'
    if (-not (Test-Path $initScript)) { throw "找不到 $initScript" }

    # 只传配置类文件到 /tmp/aki-deploy-conf,再原地执行 server-init.sh。
    # 脚本是幂等的:软件已装会跳过,库已存在不会重跑 init.sql,
    # 已填好密码的 aki-admin.env 也不会被覆盖。
    Invoke-Remote 'rm -rf /tmp/aki-deploy-conf && mkdir -p /tmp/aki-deploy-conf' | Out-Null
    # 注意:这里必须写成一行。PowerShell 5.1 不允许把管道符 | 放在行尾
    # (7.x 可以),分行写会在 5.1 上报 "Missing expression after '|'"。
    $confFiles = @('nginx.conf', 'aki-admin.service', 'aki-admin.env.example', 'server-init.sh') | ForEach-Object { Join-Path $PSScriptRoot $_ } | Where-Object { Test-Path $_ }
    # 【sql/*.sql 必须一并放进这个目录】server-init.sh 找 init.sql 的顺序是
    #   $SQL_DIR_OVERRIDE -> ./sql -> <脚本目录>/../sql -> <脚本目录>
    # 而这里是用 `sudo bash <绝对路径>` 执行的(不会切换 CWD),前三项全部落空,
    # 只有"sql 与脚本同目录"这一条能命中。漏掉的后果非常隐蔽:脚本只打一行
    # [!] 没找到 sql/init.sql 就继续跑完,于是部署全绿、健康检查通过,
    # 但库里根本没有表,登录时才报 table doesn't exist。
    # (第 0.5 步传到 /tmp/aki-sql 的那份是给手动导入用的,和这里是两个目录;
    #  这段代码只在"首次部署"时执行,不会每次发版都重复上传。)
    $initSqlFiles = @('init.sql', 'homepage_init.sql') | ForEach-Object { Join-Path (Join-Path $repoRoot 'sql') $_ } | Where-Object { Test-Path $_ }
    $confFiles = @($confFiles) + @($initSqlFiles)
    if ((Invoke-Upload -Paths $confFiles -Destination "${Server}:/tmp/aki-deploy-conf/") -ne 0) { throw 'scp 上传部署配置失败' }

    # 这个块交给远端的 bash 执行,所以写成单引号 here-string(见前面 restartScript 的说明)。
    # 这里【不能】用 $sudoPrefix:server-init.sh 内部有 root 校验,
    # 而前缀在 root 登录时是空串,会以普通用户身份跑,直接被脚本拒绝。
    # 预检已确认 root 或有免密 sudo,所以无条件用 sudo。
    #
    # 先重定向到文件再 cat,而不是直接管道给 tail:
    # 管道会让退出码变成 tail 的(永远 0),脚本真实失败会被吞掉。
    $initOut = Invoke-RemoteSh @'
set -o pipefail
sudo bash /tmp/aki-deploy-conf/server-init.sh > /tmp/aki-init.log 2>&1
init_rc=$?
tail -n 40 /tmp/aki-init.log
if [ "$init_rc" -ne 0 ]; then
  echo "  [X] server-init.sh 执行失败(退出码 $init_rc),完整日志: /tmp/aki-init.log"
  exit "$init_rc"
fi
echo
echo "  --- 数据库表结构 ---"
sudo mysql --default-character-set=utf8mb4 -e "SELECT table_schema, table_name FROM information_schema.tables WHERE table_schema IN ('aki_sys') ORDER BY table_name" 2>/dev/null || echo "  (MySQL 尚未就绪或需要密码,稍后手动导入)"
'@
    $initOut | ForEach-Object { Write-Host "  $_" }

    Write-Warn2 "如果 /etc/aki-admin/aki-admin.env 里的数据库/Redis 密码还是 CHANGE_ME,"
    Write-Warn2 "先把它们改好再继续(服务会启动失败):"
    Write-Host "      ssh $Server 'sudo vi /etc/aki-admin/aki-admin.env'" -ForegroundColor Gray
}

# =====================================================
# 1. 构建
# =====================================================
$jarLocal = Join-Path $backendDir "target\$JarName"
$distLocal = Join-Path $frontendDir 'dist'

if (-not $NoBuild) {
    if (-not $SkipBackend) {
        Write-Step '本地构建后端 (mvn -DskipTests package)'
        # 构建前先确保产物不被占用:必要时自动停掉本地后端(见函数注释)
        Stop-LocalBackendIfNeeded $jarLocal
        # 兜底:仍被占用(例如被杀毒软件扫描)就明确报错,而不是让 Maven 抛一个费解的 rename 失败
        Assert-NotLocked $jarLocal @"
jar 仍被其他程序占用。请先停掉本地服务再重试:
        .\stop-all.bat
"@
        Push-Location $backendDir
        try {
            & mvn -q -DskipTests package
            if ($LASTEXITCODE -ne 0) { throw 'Maven 打包失败' }
        } finally { Pop-Location }
        if (-not (Test-Path $jarLocal)) { throw "打包成功但没找到 $jarLocal" }
        $mb = [math]::Round((Get-Item $jarLocal).Length / 1MB, 1)
        if ($mb -lt 1) {
            throw "产物只有 $mb MB,明显不是可执行 fat jar —— 多半是 repackage 中途失败留下的残缺文件。删除 backend/target 后重试。"
        }
        Write-Ok "后端产物: $jarLocal ($mb MB)"
    }

    if (-not $SkipFrontend) {
        Write-Step '本地构建前端 (npm run build)'
        Push-Location $frontendDir
        try {
            if (-not (Test-Path (Join-Path $frontendDir 'node_modules'))) {
                Write-Warn2 'node_modules 不存在,先 npm install'
                & npm install
                if ($LASTEXITCODE -ne 0) { throw 'npm install 失败' }
            }
            & npm run build
            if ($LASTEXITCODE -ne 0) { throw 'vite build 失败' }
        } finally { Pop-Location }
        if (-not (Test-Path (Join-Path $distLocal 'index.html'))) {
            throw "构建产物缺少 index.html,检查 $distLocal"
        }
        Write-Ok "前端产物: $distLocal"
    }
}

# =====================================================
# 2. 上传后端
# =====================================================
if (-not $SkipBackend) {
    if (-not (Test-Path $jarLocal)) { throw "找不到后端产物 $jarLocal(去掉 -NoBuild 重新打包)" }

    Write-Step '上传后端 jar'
    # 先传到临时名再原子替换:避免服务正好在读取 jar 时被覆盖,
    # 也保证上传中断不会留下一个半截的 jar。
    $remoteTmp = "/tmp/$RemoteJarName.new"
    if ((Invoke-Upload -Paths @($jarLocal) -Destination "${Server}:$remoteTmp") -ne 0) { throw 'scp 上传 jar 失败' }
    Write-Ok "已上传到 $remoteTmp"

    Write-Step "替换 jar 并重启服务 $ServiceName"
    # 用【单引号】here-string + -f 填本地变量,而不是双引号插值。
    # 原因:双引号 here-string 里的 $(...) 会被 PowerShell 当成子表达式开始,
    # 而我们要的是原样传给远端 shell 的命令替换,5.1 下还会直接报语法错。
    # 用单引号后整块内容一字不改地传给 bash,只有 {n} 占位符被替换。
    $restartScript = @'
set -euo pipefail
cd {0}

# 留一份上一版,出问题能 30 秒回滚
if [ -f {1} ]; then
  cp -f {1} {1}.bak
  echo "  已备份旧版本 -> {1}.bak"
fi

mv -f {2} {1}
chown aki:aki {1} 2>/dev/null || true
chmod 644 {1}

{3} systemctl restart {4}
sleep 3

if {3} systemctl is-active --quiet {4}; then
  echo "  服务已启动"
else
  echo "  服务启动失败,最近日志:"
  {3} journalctl -u {4} -n 40 --no-pager || true
  echo "  最近应用日志:"
  {3} tail -n 40 /var/log/aki-admin/aki-admin.log || true
  exit 1
fi

# 健康检查:接口都在 /api 下,未带 token 应返回业务错误码
# (401/200 都说明进程活着并接管了请求;000 才说明真的没起来)
code=$(curl -s -o /dev/null -w '%{{http_code}}' --max-time 5 http://127.0.0.1:8080/api/auth/me || echo 000)
if [ "$code" = "000" ]; then
  echo "  警告:8080 端口无响应,请检查日志"
  exit 1
fi
echo "  健康检查通过,本地接口返回 HTTP $code"
'@ -f $RemoteApp, $RemoteJarName, $remoteTmp, $sudoPrefix, $ServiceName
    Invoke-RemoteSh $restartScript | ForEach-Object { Write-Host "  $_" }
    Write-Ok "后端部署完成"
}

# =====================================================
# 3. 上传前端
# =====================================================
if (-not $SkipFrontend) {
    if (-not (Test-Path (Join-Path $distLocal 'index.html'))) {
        throw "找不到前端产物 $distLocal(去掉 -NoBuild 重新构建)"
    }

    Write-Step '打包并上传前端 dist'
    # 做法:本地先打成 tar.gz 文件,再用 scp 传上去解包。
    #
    # 为什么不用 `tar -czf - . | ssh ... 'tar -xzf -'` 这种管道流式传输:
    # Windows PowerShell 在把原生命令的输出接到另一个原生命令时,是按【文本】
    # 逐行转码的,二进制 gzip 流会被破坏(可能静默损坏或直接报错),
    # 而且管道里某一段失败时退出码会被下一段覆盖。
    # 分两步走虽然多一次磁盘写入,但字节流交给 scp 处理,结果可靠。
    #
    # 单引号 here-string:PowerShell 不替换变量,{0}/{1} 用 -f 填,
    # 免得远端 $ 变量和本地变量混在一起(双引号 here-string 里的 $( 还会被
    # PowerShell 当成子表达式,5.1 下直接报语法错)。
    $remoteUnpack = @'
set -euo pipefail
# 清空 web 目录但保留目录本身(inode 不变,更稳妥)
sudo -n find {0}/web -mindepth 1 -delete
sudo -n tar -xzf /tmp/aki-web.tar.gz -C {0}/web
rm -f /tmp/aki-web.tar.gz
sudo -n chown -R {1}:{1} {0}/web
sudo -n find {0}/web -type d -exec chmod 755 {{}} +
sudo -n find {0}/web -type f -exec chmod 644 {{}} +
echo "  已解包到 {0}/web,文件数: $(sudo -n find {0}/web -type f | wc -l)"
'@ -f $RemoteApp, 'aki'

    $tarTmp = Join-Path $env:TEMP 'aki-web.tar.gz'
    if (Test-Path $tarTmp) { Remove-Item $tarTmp -Force }
    & tar -czf (ConvertTo-NativePath $tarTmp) -C (ConvertTo-NativePath $distLocal) .
    if ($LASTEXITCODE -ne 0) { throw '本地打包 dist 失败' }
    $tarMb = [math]::Round((Get-Item $tarTmp).Length / 1MB, 2)
    Write-Ok "已打包: $tarTmp ($tarMb MB)"

    if ((Invoke-Upload -Paths @($tarTmp) -Destination "${Server}:/tmp/aki-web.tar.gz") -ne 0) { throw 'scp 上传前端包失败' }

    Invoke-RemoteSh $remoteUnpack | ForEach-Object { Write-Host "  $_" }
    Remove-Item $tarTmp -Force -ErrorAction SilentlyContinue

    Write-Step '重载 nginx'
    Invoke-RemoteSh @'
set -e
sudo -n nginx -t
sudo -n systemctl reload nginx
echo "  nginx 配置检查通过并已重载"
'@ | ForEach-Object { Write-Host "  $_" }
    Write-Ok "前端部署完成"
}

# =====================================================
# 4. 汇总
# =====================================================
Write-Step '部署完成'
$summary = Invoke-RemoteSh (@'
set -e
echo "  时间        : $(date '+%F %T')"
echo "  当前版本    : $(ls -l --time-style='+%F %T' {0}/{1} | awk '{{print $6, $7, $8}}')"
echo "  服务状态    : $({2} systemctl is-active {3})"
echo "  nginx 状态  : $({2} systemctl is-active nginx)"
echo "  站点根目录  : $(ls {0}/web | tr '\n' ' ')"
'@ -f $RemoteApp, $RemoteJarName, $sudoPrefix, $ServiceName)
$summary | ForEach-Object { Write-Host $_ }

Write-Host "`n  回滚命令(出问题时):" -ForegroundColor Gray
Write-Host "    ssh $Server '$sudoPrefix cp -f $RemoteApp/$RemoteJarName.bak $RemoteApp/$RemoteJarName && $sudoPrefix systemctl restart $ServiceName'" -ForegroundColor Gray
Write-Host "  查看实时日志:" -ForegroundColor Gray
Write-Host "    ssh $Server '$sudoPrefix tail -f /var/log/aki-admin/aki-admin.log'" -ForegroundColor Gray
