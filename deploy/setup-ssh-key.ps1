#!/usr/bin/env pwsh
# =====================================================
# 一次性配置到服务器的免密 SSH 登录(在本地 Windows 上执行)
#
#   .\deploy\setup-ssh-key.ps1 -Server root@47.120.68.160
#   .\deploy\setup-ssh-key.ps1 -Server root@47.120.68.160 -Alias aki
#
# 做四件事:
#   1. 生成部署专用密钥(默认 ~/.ssh/aki_deploy,pwsh7 用 ed25519 / PS5.1 用 RSA)
#   2. 用【交互式】ssh 把公钥装到服务器(密码由 ssh 自己提示,不经过脚本参数,
#      不写入磁盘、不出现在命令行历史里)
#   3. 在 ~/.ssh/config 里写一个别名,以后 ssh aki 就能连
#   4. 验证免密登录是否生效
#
# 安全说明:
#   - 私钥文件权限设为仅当前用户可读
#   - 本脚本不接受 -Password 参数,是刻意的:密码走参数会进命令行历史/进程列表
#   - 装好之后建议在服务器上关掉 root 密码登录(见脚本末尾提示)
# =====================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Server,   # 形如 root@1.2.3.4
    [string]$Alias      = 'aki',
    [string]$KeyPath    = (Join-Path $env:USERPROFILE '.ssh\aki_deploy'),
    [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

# =====================================================
# 及早卸载 PSReadLine(必须放在最前面,任何交互式命令之前)
# =====================================================
# 这是"ssh 密码提示出现了、但打字没有任何反应"的根因:
# PowerShell 5.1 的交互式会话默认加载 PSReadLine,它接管控制台按键。
# 当原生命令(ssh)停下来等密码时,按键会被 PSReadLine 抢走 ——
# 提示看得见,却一个字符也输不进去。卸载后按键交还给子进程。
#
# 放在这里而不是用它的地方,是因为它必须在本脚本执行任何交互式外部命令之前生效。
try {
    $psrl = Get-Module -Name PSReadLine -ErrorAction SilentlyContinue
    if ($psrl) {
        Remove-Module PSReadLine -Force -ErrorAction SilentlyContinue
        Write-Host "  [i] 已卸载 PSReadLine $($psrl.Version)(它会导致 ssh 输不进密码)" -ForegroundColor Gray
    } else {
        Write-Host "  [i] PSReadLine 未加载,无需处理" -ForegroundColor Gray
    }
} catch {
    Write-Host "  [!] 卸载 PSReadLine 失败(若下面输不进密码,请在新窗口先手动执行 Remove-Module PSReadLine)" -ForegroundColor Yellow
}

function Write-Step([string]$T) { Write-Host "`n=== $T ===" -ForegroundColor Cyan }
function Write-Ok([string]$T)   { Write-Host "  [OK] $T" -ForegroundColor Green }
function Write-Warn2([string]$T){ Write-Host "  [!]  $T" -ForegroundColor Yellow }
function Write-Err([string]$T)  { Write-Host "  [X]  $T" -ForegroundColor Red }

# 调用原生命令(ssh / ssh-keygen)的统一入口。
#
# 为什么必须包装:本脚本是 $ErrorActionPreference='Stop',而 PowerShell 5.1 下
# 原生命令往 stderr 写内容会产生 NativeCommandError,在 EAP=Stop 时升级为
# 【终止性错误】。ssh/ssh-keygen 恰恰经常往 stderr 写正常信息(主机指纹提示、
# 密钥生成进度、连接失败原因),于是脚本会在这些"其实不算错"的地方直接中断。
#
# 注意:实测确认在函数内部改 $ErrorActionPreference 只影响该函数自身(局部变量),
# 不会污染调用方 —— 所以这个包装既能让原生命令的 stderr 不致命,
# 又能保留脚本其余部分 EAP=Stop 的严格性。
function Invoke-Native {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [switch]$PassThruRaw   # 置位时不捕获输出(用于需要直接占用终端的交互式命令)
    )
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($PassThruRaw) {
            & $FilePath @Arguments
            $code = $LASTEXITCODE
            return @{ Output = @(); Code = $code }
        }
        $out = & $FilePath @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $old
    }
    return @{ Output = @($out); Code = $code }
}

# ---------- 0. 解析 Server ----------
if ($Server -notmatch '^([^@]+)@(.+)$') {
    throw "Server 必须写成 用户@主机 的形式,例如 root@47.120.68.160"
}
$sshUser = $Matches[1]
$sshHost = $Matches[2]
Write-Step "目标: $sshUser@$sshHost  别名: $Alias"

$sshDir = Join-Path $env:USERPROFILE '.ssh'
if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }

# ---------- 1. 生成密钥 ----------
Write-Step '生成部署专用密钥'

# 生成 SSH 密钥这里踩过两个坑,记下来免得以后重蹈覆辙:
#
# 坑 1:PowerShell 5.1 调用原生命令时会【丢掉空字符串实参】。
#   & ssh-keygen -t ed25519 -f $key -N '' -C x
#   -> -N 后面那个空串消失,ssh-keygen 收到 "-N -C x",直接报
#      "Too many arguments." 并打印用法(退出码 1)。
#   而不写 -N 更糟:ssh-keygen 会开始交互式索要 passphrase 并停住等输入
#   (实测:加超时跑,进程一直不返回)。
#
# 坑 2:用 cmd /c 包一层可以保住空口令,但 cmd 会把路径里的 \ 变成 \\
#   -> "Unable to save public key to C:\\Users\\...: Bad file descriptor"
#   私钥侥幸写成功、公钥写失败,留下一个半成品。
#
# 所以这里不用 & 也不用 cmd,而是自己拼命令行、经 CreateProcess 直接启动:
# 空口令参数按 Windows 命令行规范写成 "" ,并且完全绕开 cmd 的路径改写。
function Invoke-Keygen {
    param([string[]]$KeygenArgs)

    $exe = (Get-Command ssh-keygen -ErrorAction Stop).Source

    # 按 CommandLineToArgvW 的规则引号化;$null 与 '' 都产出 ""
    $quoted = $KeygenArgs | ForEach-Object {
        if ($null -eq $_) { '""' }
        else {
            $a = [string]$_
            if ($a -eq '') { '""' }
            elseif ($a -match '[\s"]') { '"' + ($a -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }
            else { $a }
        }
    }
    $argLine = ($quoted -join ' ')

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $exe
    # UseShellExecute=$false 时 .Arguments 就是子进程的完整命令行(除 argv[0]);
    # 我们的 exe 路径没有空格,所以这里不需要再包一层引号。
    $psi.Arguments              = $argLine
    $psi.UseShellExecute        = $false       # 关键:false 才走 CreateProcess,保留原始命令行
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    # .NET Framework 下必须调用两次 WaitForExit:第一次等进程结束,
    # 第二次(带超时的重载)才会等待被重定向的流彻底读完。
    # 只调一次会导致"进程已退出但句柄没释放",紧接着写文件就报 Access denied。
    $proc.WaitForExit()
    $proc.WaitForExit(10000) | Out-Null

    $lines = @()
    if ($stdout) { $lines += ($stdout -split "`r?`n" | Where-Object { $_ -ne '' }) }
    if ($stderr) { $lines += ($stderr -split "`r?`n" | Where-Object { $_ -ne '' }) }
    return @{ Code = $proc.ExitCode; Output = $lines }
}

# 覆盖写文件,带重试。
# 就算句柄已经释放,Windows 也可能因为杀毒软件实时扫描短暂占用而拒绝写入;
# 这里重试几次比直接失败友好得多。
function Write-FileRetry {
    param([string]$Path, [string]$Content, [int]$Attempts = 10)
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.ASCIIEncoding))
            return $true
        } catch {
            if ($i -eq $Attempts) { return $false }
            Start-Sleep -Milliseconds 300
        }
    }
    return $false
}

# ---- 已有密钥就复用,不重新生成 ----
#
# 为什么重要:如果每次都重新生成,authorized_keys 会越积越多旧公钥,
# 而且 -- 更麻烦的 -- 云控制台/其他工具里配的指纹会对不上,排查时容易误判。
# 复用逻辑:
#   私钥在 + .pub 有内容  -> 直接读 .pub(最省事)
#   私钥在 + .pub 缺失/为空 -> 用 ssh-keygen -y 从私钥重新导出公钥
#   私钥不在              -> 生成新的
$pubKey = ''

if (Test-Path $KeyPath) {
    Write-Ok "私钥已存在,复用: $KeyPath"
    if ((Test-Path "$KeyPath.pub") -and ((Get-Content "$KeyPath.pub" -Raw -ErrorAction SilentlyContinue) -match '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-)')) {
        $pubKey = (Get-Content "$KeyPath.pub" -Raw).Trim()
        Write-Ok "已从 .pub 读取公钥"
    } else {
        Write-Warn2 ".pub 缺失或为空,从私钥重新导出公钥"
        $ex = Invoke-Keygen @('-y', '-f', $KeyPath)
        if ($ex.Code -eq 0 -and $ex.Output.Count -gt 0) {
            $pubKey = ($ex.Output -join '').Trim()
            Write-Ok "公钥已重新导出"
        } else {
            throw "私钥存在但无法导出公钥,请删除 $KeyPath 后重跑"
        }
    }
} else {

# 生成到临时文件名,再挪到目标位置。
# 为什么不直接生成到 $KeyPath:ssh-keygen 在目标已存在时会交互式提问
# "Overwrite (y/n)?",脚本里没人回答就会失败。生成到临时路径可完全绕开。
$kgTmp  = Join-Path ([System.IO.Path]::GetTempPath()) ("aki-key-{0}" -f (Get-Random))
$keyType = 'ed25519'

Write-Host "  密钥类型: $keyType(密钥文件: $KeyPath)"
$kg = Invoke-Keygen @('-t', $keyType, '-f', $kgTmp, '-N', '', '-C', "aki-deploy@$env:COMPUTERNAME")

# 回退:极老的 ssh-keygen 不支持 ed25519 时改用 RSA 4096
if ($kg.Code -ne 0 -or -not (Test-Path $kgTmp)) {
    Write-Warn2 "ed25519 生成失败(退出码 $($kg.Code)),回退到 RSA 4096"
    $kgTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("aki-key-{0}" -f (Get-Random))
    $kg = Invoke-Keygen @('-t', 'rsa', '-b', '4096', '-f', $kgTmp, '-N', '', '-C', "aki-deploy@$env:COMPUTERNAME")
}

if (-not (Test-Path $kgTmp)) {
    Write-Err "ssh-keygen 没能生成私钥(退出码 $($kg.Code))"
    $kg.Output | Select-Object -Last 6 | ForEach-Object { Write-Host "      $_" }
    throw "无法生成 SSH 密钥"
}

# 公钥一律从私钥导出,不依赖 ssh-keygen 写的 .pub 文件。
#
# 本环境实测:ssh-keygen 会把 .pub 创造成 0 字节文件并报
#   "Unable to save public key to <路径>: Bad file descriptor"
# 而私钥却写成功 —— 留下"有私钥、公钥是空文件"的半成品。
# 如果只看退出码不看内容,后面就会把空行塞进 authorized_keys,
# 表现为"配好了却仍然要密码",极难排查。
# `ssh-keygen -y -f <私钥>` 导出公钥稳定可靠,所以以它作为唯一来源。
$pub = Invoke-Keygen @('-y', '-f', $kgTmp)
if ($pub.Code -ne 0 -or $pub.Output.Count -eq 0) {
    Write-Err "无法从私钥导出公钥(退出码 $($pub.Code))"
    $pub.Output | Select-Object -Last 4 | ForEach-Object { Write-Host "      $_" }
    throw "公钥导出失败"
}

$pubText = ($pub.Output -join '').Trim()
if ($pubText -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-)') {
    throw "导出的公钥内容不合法(长度 $($pubText.Length)):$($pubText.Substring(0, [Math]::Min(40, $pubText.Length)))"
}

# 写 .pub 只是"尽力而为",不作为失败条件。
#
# 本环境下 ssh-keygen 只会把 .pub 创造成一个 0 字节文件(并报 Bad file descriptor),
# 而且那个文件句柄还被它占着,紧接着覆盖写会 Access denied。
# 真正用于安装公钥的是 $pubKey 变量,不依赖磁盘上这个文件,
# 所以这里失败只提示、不中断 —— 否则会卡在一个和部署无关的小问题上。
if (Write-FileRetry -Path "$kgTmp.pub" -Content ($pubText + "`n")) {
    Write-Ok "公钥已生成并校验($($pubText.Split(' ')[0]),$($pubText.Length) 字符)"
} else {
    Write-Warn2 "公钥写盘失败(被 ssh-keygen 的残留句柄占用),不影响安装 —— 安装用内存里的公钥"
}

Move-Item -Path $kgTmp -Destination $KeyPath -Force
Remove-Item "$kgTmp.pub" -Force -ErrorAction SilentlyContinue
Write-Ok "已生成: $KeyPath"

# 收紧私钥权限(Windows 上 ssh 会检查这个,权限过宽会拒绝使用)
try {
    $acl = Get-Acl $KeyPath
    $acl.SetAccessRuleProtection($true, $false)
    $me = New-Object System.Security.Principal.NTAccount($env:USERNAME)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($me, 'FullControl', 'Allow')
    $acl.SetAccessRule($rule)
    Set-Acl -Path $KeyPath -AclObject $acl
    Write-Ok "私钥权限已收紧为仅 $env:USERNAME 可读"
} catch {
    Write-Warn2 "收紧私钥权限失败(多数情况不影响使用): $($_.Exception.Message)"
}

$pubKey = $pubText

}   # 结束"私钥不存在则生成"的分支

# 无论走哪条路径,到这里都必须有一份合法的公钥
if ($pubKey -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-)') {
    throw "公钥内容异常,无法继续:$($pubKey.Substring(0, [Math]::Min(40, $pubKey.Length)))"
}
Write-Host "  公钥指纹: $($pubKey.Substring(0, [Math]::Min(50, $pubKey.Length)))..." -ForegroundColor Gray

# ---------- 2. 安装公钥到服务器 ----------
Write-Step '把公钥装到服务器'
Write-Host @"
  接下来 ssh 会提示输入 $sshUser@$sshHost 的密码。
  密码由 ssh 自己读取,不会写入本脚本、不会进命令行历史。
  如果服务器提示需要接受主机指纹,输入 yes。
"@ -ForegroundColor Gray

# 关键:必须用【交互式】调用,不能让 PowerShell 接管 stdin/stderr,否则密码提示拿不到终端。
# 用单引号拼接远端命令,避免本地 PowerShell 展开 $HOME 之类。
$remoteCmd = 'umask 077; mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && grep -qxF "' + $pubKey + '" ~/.ssh/authorized_keys || echo "' + $pubKey + '" >> ~/.ssh/authorized_keys'

# 先卸载 PSReadLine。
#
# 这是"密码提示出现但打字没反应"的根因:PowerShell 5.1 默认加载 PSReadLine,
# 它接管控制台按键;当原生命令(ssh)停下来等密码时,按键会被它抢走,
# 于是提示看得见、却打不进任何字符。卸载后按键交还给子进程。
# (实际卸载动作放在脚本最开头执行,这里只是说明原因,不再重复卸载。)

# 调用方式:用 PowerShell 的调用运算符直接跑 ssh,【不套 cmd】。
#
# 为什么不用 `cmd /s /c "... ssh ... "远端命令" ..."`:
# 远端命令里本身就含双引号(公钥要引起来),再套一层 cmd 的引号后会被解析错位 ——
# 实测报 '"-o StrictHostKeyChecking=accept-new ..." is not recognized'。
# 这个方向已验证不通,不要再回头改。
#
# PowerShell 直接调用是可行的:$remoteCmd 作为带空格的整体字符串传参时,
# 调用运算符会把它作为【单个 argv 元素】交给 ssh(已用 mock 校验)。
$installCode = $null
$oldEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & ssh -o StrictHostKeyChecking=accept-new "$sshUser@$sshHost" $remoteCmd
    $installCode = $LASTEXITCODE
} catch {
    Write-Warn2 "ssh 调用异常: $($_.Exception.Message)"
    $installCode = 1
} finally {
    $ErrorActionPreference = $oldEap
}

Write-Host "  执行: ssh -o StrictHostKeyChecking=accept-new $sshUser@$sshHost (公钥安装命令)" -ForegroundColor Gray

if ($installCode -ne 0) {
    Write-Err "公钥安装失败(退出码 $installCode)"
    Write-Host @"
  常见原因:
    - 密码错误
    - 服务器 sshd 配置了 PasswordAuthentication no,但你还没法用密钥(死锁):
        需要用云厂商控制台的 VNC/救援终端登录后手动加公钥
    - root 登录被禁用(PermitRootLogin no):改用普通用户,或用控制台开一个
    - 网络不通 / 端口不是 22:检查安全组与 sshd 的 Port 配置
    - 密码提示出现但打字没反应(PSReadLine 抢按键):
      新开一个窗口,先用纯 cmd 验证一次(完全绕开 PowerShell):
        cmd /c ssh root@$sshHost "echo OK"
      能正常输入密码并看到 OK,再回来重跑本脚本。
"@ -ForegroundColor Gray
    exit 1
}
Write-Ok '公钥已写入服务器 ~/.ssh/authorized_keys'

# ---------- 3. 写 ssh config 别名 ----------
Write-Step "写入 ~/.ssh/config 别名 [$Alias]"
$configPath = Join-Path $sshDir 'config'
$block = @"
# >>> aki_sys deploy (setup-ssh-key.ps1 生成,可整段删除)
Host $Alias
    HostName $sshHost
    User $sshUser
    IdentityFile $KeyPath
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 4
# <<< aki_sys deploy
"@

$existing = if (Test-Path $configPath) { Get-Content $configPath -Raw } else { '' }
# 幂等:先删掉旧的同名块再写,避免重复追加
$pattern = '(?ms)^# >>> aki_sys deploy.*?^# <<< aki_sys deploy\r?\n?'
if ($existing -match $pattern) {
    $existing = [regex]::Replace($existing, $pattern, '')
    Write-Ok '已移除旧的同名配置块'
}
$newContent = ($existing.TrimEnd() + "`n`n" + $block).TrimStart() + "`n"
# ssh 在 Windows 上要求 config 不能有 BOM,用无 BOM 的 UTF8
[System.IO.File]::WriteAllText($configPath, $newContent, (New-Object System.Text.UTF8Encoding($false)))
Write-Ok "已写入: $configPath"

# ---------- 4. 验证免密登录 ----------
if (-not $SkipVerify) {
    Write-Step '验证免密登录'
    # BatchMode=yes:一旦还需要密码就立即失败,不会卡在交互提示上。
    # 走 Invoke-Native 以免连接失败时的 stderr 被 EAP=Stop 变成致命错误。
    $v = Invoke-Native -FilePath 'ssh' -Arguments @(
        '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', '-o', 'StrictHostKeyChecking=accept-new',
        $Alias, 'echo READY; id -un; hostname; . /etc/os-release 2>/dev/null && echo "OS=$PRETTY_NAME"; uname -r'
    )
    if ($v.Code -ne 0 -or ($v.Output -join "`n") -notmatch 'READY') {
        Write-Err "免密登录验证失败(退出码 $($v.Code))"
        $v.Output | ForEach-Object { Write-Host "      $_" }
        Write-Host "  排查建议:" -ForegroundColor Gray
        Write-Host "    ssh -v $Alias 'echo ok'      # 看实际用的是哪个 config 与哪个密钥" -ForegroundColor Gray
        Write-Host "    type `$env:USERPROFILE\.ssh\config" -ForegroundColor Gray
        exit 1
    }
    $v.Output | ForEach-Object { Write-Host "  $_" }
    Write-Ok "免密登录已生效: ssh $Alias"
}

# ---------- 完成 ----------
Write-Step '完成'
Write-Host @"
  现在可以直接用别名:
    ssh $Alias
    .\deploy\deploy.ps1 -Server $Alias

  【建议立刻做的安全加固】(部署成功、确认免密可用之后再执行):
    1) 改掉你刚才在聊天里发过的 root 密码:
         ssh $Alias 'passwd'
    2) 确认密钥登录可用后,关闭密码登录(能挡住 99% 的暴力破解,云服务器上
       root 每天被撞库几千次很正常):
         ssh $Alias "sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && sudo systemctl restart sshd"
       注意:执行前务必先开一个新窗口确认 ssh $Alias 还能进,别把自己关在门外!
"@ -ForegroundColor Gray
