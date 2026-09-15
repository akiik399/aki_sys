# =====================================================
# aki_sys 后台管理系统 - 停止服务
# 由 stop-all.bat 调用
# =====================================================
$ErrorActionPreference = 'Continue'
try { $Host.UI.RawUI.WindowTitle = 'aki_sys 停止服务' } catch { }

Write-Host '=========================================='
Write-Host '   aki_sys - 停止后端 / 前端 / Redis'
Write-Host '=========================================='
Write-Host ''

function Stop-Port([int]$port, [string]$name) {
    $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if (-not $conns) {
        Write-Host "[跳过] $name 未在运行  (端口 $port)"
        return
    }
    $procIds = $conns | Select-Object -ExpandProperty OwningProcess -Unique
    foreach ($procId in $procIds) {
        try {
            Stop-Process -Id $procId -Force -ErrorAction Stop
            Write-Host "[完成] $name 已停止  (端口 $port, PID $procId)"
        } catch {
            Write-Host "[失败] $name 停止失败  (PID $procId): $($_.Exception.Message)"
        }
    }
}

# Redis 优雅关闭(落盘关闭)
$redisCli = 'C:\tools\redis\redis-cli.exe'
if ((Test-Path $redisCli) -and (Get-NetTCPConnection -LocalPort 6379 -State Listen -ErrorAction SilentlyContinue)) {
    & $redisCli shutdown nosave | Out-Null
    Start-Sleep -Milliseconds 500
}

Stop-Port 8080 '后端'
Stop-Port 5173 '前端'
Stop-Port 6379 'Redis'

Write-Host ''
Write-Host '注意: MySQL80 是 Windows 服务,本脚本不会停止它。'
Write-Host '      如需停止(需管理员): net stop MySQL80'
Write-Host ''
Read-Host '按回车键关闭本窗口'
