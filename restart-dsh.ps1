<#
  restart-dsh.ps1 —— 重启 DeepSeek Harness（全局工具，不属于任何插件）
  ============================================================================
  用法：
    .\restart-dsh.ps1              # 重启 + 等 web 就绪 + 写日志（默认）
    .\restart-dsh.ps1 -NoStart     # 只停，不启动
    .\restart-dsh.ps1 -VerifyOnly  # 只检查当前 DSH 是否健康（不重启）
    .\restart-dsh.ps1 -TimeoutSec 120   # 等多久（默认 90 秒）

  静默运行（不弹窗）：wscript //nologo restart-dsh.vbs
  从 DSH 会话 / 插件 / Agent 内部触发：restart-dsh-launch.ps1（走计划任务，脱离 DSH 进程树）
  日志：同目录 restart.log
  ============================================================================
#>
param(
  [switch]$NoStart,
  [switch]$VerifyOnly,
  [int]$TimeoutSec = 90
)

$ErrorActionPreference = 'SilentlyContinue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = Join-Path $here 'restart.log'
$exe = 'E:\DeepSeek Harness\DeepSeek Harness.exe'

function Write-RestartLog([string]$text) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $text"
  Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
  Write-Host $line
}

function Get-MainProc {
  Get-CimInstance Win32_Process |
    Where-Object { $_.Name -eq 'DeepSeek Harness.exe' -and $_.CommandLine -notmatch '--type=' } |
    Select-Object -First 1
}

function Get-DshPids {
  @((Get-Process 'DeepSeek Harness' -ErrorAction SilentlyContinue).Id)
}

# DSH web 的端口是随机的：从 DSH 进程的监听端口里找
function Get-ListenPorts {
  $pids = Get-DshPids
  if (-not $pids.Count) { return @() }
  Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $pids -contains $_.OwningProcess } |
    Select-Object -ExpandProperty LocalPort -Unique
}

function Test-Tcp([int]$port) {
  $c = New-Object System.Net.Sockets.TcpClient
  try {
    $t = $c.ConnectAsync('127.0.0.1', $port)
    if (-not $t.Wait(1500)) { return $false }
    return $c.Connected
  } catch { return $false } finally { $c.Close() }
}

# ---------- 1) 可选：重启 ----------
if (-not $VerifyOnly) {
  $main = Get-MainProc
  if ($main) {
    Write-RestartLog "停止 DSH 主进程 PID=$($main.ProcessId)"
    Stop-Process -Id $main.ProcessId -Force
    Start-Sleep -Seconds 3
  } else {
    Write-RestartLog 'DSH 没在跑（不用停）'
  }
  if ($NoStart) {
    Write-RestartLog '只停不启动（-NoStart），结束'
    exit 0
  }
  Write-RestartLog '启动 DSH…'
  Start-Process -FilePath $exe
}

# ---------- 2) 等 DSH web 端口就绪 ----------
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$port = 0
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 2
  foreach ($p in @(Get-ListenPorts)) {
    if ($p -lt 1024) { continue }
    if (Test-Tcp $p) { $port = $p; break }
  }
  if ($port) { break }
}

if (-not $port) {
  Write-RestartLog "❌ ${TimeoutSec} 秒内没等到 DSH 的 web 端口"
  & schtasks.exe /Delete /TN 'DSH-RestartOnce' /F 2>$null | Out-Null
  exit 1
}

$main2 = Get-MainProc
$procCount = @(Get-DshPids).Count
Write-RestartLog ("✅ DSH 已重启，web 端口 :{0} 可连接" -f $port)
Write-RestartLog ("   主进程={0}  进程数={1}" -f $main2.ProcessId, $procCount)

# ---------- 3) 清理一次性启动任务 ----------
& schtasks.exe /Delete /TN 'DSH-RestartOnce' /F 2>$null | Out-Null

Write-RestartLog '完成'
exit 0
