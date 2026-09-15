# =====================================================
# aki_sys 后台管理系统 - 一键启动
# 由 start-all.bat 调用
# =====================================================
$ErrorActionPreference = 'Continue'
try { $Host.UI.RawUI.WindowTitle = 'aki_sys 一键启动' } catch { }

$base      = Split-Path -Parent $PSScriptRoot
$redisHome = 'C:\tools\redis'
$backend   = Join-Path $base 'backend'
$frontend  = Join-Path $base 'frontend'
$logs      = Join-Path $base 'logs'
$jar       = Join-Path $backend 'target\aki-admin-1.0.0.jar'

if (-not (Test-Path $logs)) { New-Item -ItemType Directory -Path $logs -Force | Out-Null }

function Test-Listening([int]$port) {
    [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
}

function Start-Logged([string]$file, [string[]]$arguments, [string]$workDir, [string]$outLog, [string]$errLog) {
    Start-Process -FilePath $file -ArgumentList $arguments -WorkingDirectory $workDir `
        -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog
}

Write-Host '=========================================='
Write-Host '   aki_sys 后台管理系统 - 一键启动'
Write-Host '=========================================='
Write-Host "   项目目录: $base"
Write-Host ''

# ---------- 0. MySQL 服务 ----------
$mysql = Get-Service -Name 'MySQL80' -ErrorAction SilentlyContinue
if ($null -eq $mysql) {
    Write-Host '[警告] 未找到 MySQL80 服务,请确认 MySQL 已安装'
} elseif ($mysql.Status -ne 'Running') {
    Write-Host '[启动] MySQL80 服务 ...'
    try {
        Start-Service -Name 'MySQL80' -ErrorAction Stop
        Write-Host '[完成] MySQL80 已启动'
    } catch {
        Write-Host '[失败] MySQL80 启动失败,请用管理员身份运行本脚本'
    }
} else {
    Write-Host '[跳过] MySQL 已在运行  (3306)'
}

# ---------- 1. Redis ----------
if (Test-Listening 6379) {
    Write-Host '[跳过] Redis 已在运行  (6379)'
} else {
    $redisExe = Join-Path $redisHome 'redis-server.exe'
    if (Test-Path $redisExe) {
        Write-Host '[启动] Redis ...'
        Start-Logged $redisExe @((Join-Path $redisHome 'redis.windows.conf')) $redisHome `
            (Join-Path $logs 'redis.log') (Join-Path $logs 'redis.err.log')
    } else {
        Write-Host "[失败] 未找到 $redisExe"
    }
}

# ---------- 2. 后端 ----------
if (-not (Test-Path $jar)) {
    Write-Host '[构建] 未找到 jar,正在用 Maven 打包,请稍候 ...'
    Push-Location $backend
    & mvn -B -DskipTests clean package
    Pop-Location
}
if (Test-Listening 8080) {
    Write-Host '[跳过] 后端已在运行  (8080)'
} elseif (Test-Path $jar) {
    Write-Host '[启动] 后端 Spring Boot ...'
    # -Dfile.encoding / stdout / stderr = UTF-8:让 JVM 的标准输出与日志统一 UTF-8。
    # 否则中文 Windows 上 JVM 默认 GBK,写出的 logs\backend.log 用编辑器打开就是乱码。
    Start-Logged 'java' @('-Dfile.encoding=UTF-8', '-Dstdout.encoding=UTF-8', '-Dstderr.encoding=UTF-8', '-jar', $jar) $backend `
        (Join-Path $logs 'backend.log') (Join-Path $logs 'backend.err.log')
} else {
    Write-Host '[失败] jar 不存在,后端无法启动'
}

# ---------- 3. 前端 ----------
if (-not (Test-Path (Join-Path $frontend 'node_modules'))) {
    Write-Host '[安装] 首次运行,安装前端依赖 ...'
    Push-Location $frontend
    & npm install
    Pop-Location
}
if (Test-Listening 5173) {
    Write-Host '[跳过] 前端已在运行  (5173)'
} else {
    Write-Host '[启动] 前端 Vite ...'
    Start-Logged 'npm.cmd' @('run', 'dev') $frontend `
        (Join-Path $logs 'frontend.log') (Join-Path $logs 'frontend.err.log')
}

# ---------- 等待就绪 ----------
Write-Host ''
Write-Host '等待服务就绪 ...'
$waited = 0
while ($waited -lt 60) {
    if ((Test-Listening 8080) -and (Test-Listening 5173)) { break }
    Start-Sleep -Seconds 2
    $waited += 2
    Write-Host -NoNewline '.'
}
Write-Host ''

$ok8080 = Test-Listening 8080
$ok5173 = Test-Listening 5173
$ok6379 = Test-Listening 6379

Write-Host ''
Write-Host '=============== 启动结果 ==============='
Write-Host ("   MySQL  3306 : " + $(if (Test-Listening 3306) { '正常' } else { '未运行' }))
Write-Host ("   Redis  6379 : " + $(if ($ok6379) { '正常' } else { '未运行' }))
Write-Host ("   后端   8080 : " + $(if ($ok8080) { '正常' } else { '未就绪(见 logs\backend.log)' }))
Write-Host ("   前端   5173 : " + $(if ($ok5173) { '正常' } else { '未就绪(见 logs\frontend.log)' }))
Write-Host '========================================'
Write-Host '   访问地址: http://localhost:5173'
Write-Host '   登录账号: admin / admin123'
Write-Host '   接口文档: http://localhost:8080/swagger-ui.html'
Write-Host "   运行日志: $logs"
Write-Host '========================================'
Write-Host '   服务在后台运行,关闭本窗口不会停止它们;'
Write-Host '   需要停止请运行 stop-all.bat'
Write-Host ''

if ($ok5173) { Start-Process 'http://localhost:5173' }

Read-Host '按回车键关闭本窗口'
