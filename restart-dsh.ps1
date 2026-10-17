<#
  restart-dsh.ps1 —— 重启 DeepSeek Harness（全局工具，不属于任何插件）
  ============================================================================
  用法：
    .\restart-dsh.ps1                  # 重启 + 等 web 就绪 + 写日志（默认）
    .\restart-dsh.ps1 -NoStart         # 只停，不启动
    .\restart-dsh.ps1 -VerifyOnly      # 只检查当前 DSH 是否健康（不重启）
    .\restart-dsh.ps1 -TimeoutSec 120  # 等多久（默认 90 秒）
    .\restart-dsh.ps1 -Background      # 强制后台启动（最小化、不抢焦点）

  全屏保护：检测到前台有应用占满整个屏幕（全屏游戏/视频）时，
  自动以「最小化 + 不抢焦点」方式启动 DSH，不打断你正在看的东西。

  静默运行（不弹终端窗口）：wscript //nologo restart-dsh-hidden.vbs
  从 DSH 会话 / 插件 / Agent 内部触发：restart-dsh-launch.ps1 -Hidden
  日志：同目录 restart.log
  ============================================================================
#>
param(
  [switch]$NoStart,
  [switch]$VerifyOnly,
  [int]$TimeoutSec = 90,
  [switch]$Background
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

# ---------- 全屏检测（前台窗口是否盖满整个显示器） ----------
function Test-ForegroundFullscreen {
  try {
    if (-not ('BrFullscreen' -as [type])) {
      Add-Type @'
using System;
using System.Runtime.InteropServices;
public class BrFullscreen {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);
  [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
  public static bool IsFullscreen() {
    IntPtr h = GetForegroundWindow();
    if (h == IntPtr.Zero) return false;
    RECT r;
    if (!GetWindowRect(h, out r)) return false;
    MONITORINFO mi = new MONITORINFO();
    mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
    IntPtr mon = MonitorFromWindow(h, 2);
    if (!GetMonitorInfo(mon, ref mi)) return false;
    return r.Left <= mi.rcMonitor.Left && r.Top <= mi.rcMonitor.Top
        && r.Right >= mi.rcMonitor.Right && r.Bottom >= mi.rcMonitor.Bottom;
  }
}
'@
    }
    return [BrFullscreen]::IsFullscreen()
  } catch { return $false }
}

# 把窗口最小化但不激活（不抢前台焦点）
function Set-WindowMinimized([IntPtr]$hWnd) {
  if ($hWnd -eq [IntPtr]::Zero) { return }
  try {
    if (-not ('BrShowWin' -as [type])) {
      Add-Type @'
using System;
using System.Runtime.InteropServices;
public class BrShowWin {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
}
'@
    }
    [void][BrShowWin]::ShowWindow($hWnd, 6)   # SW_MINIMIZE：最小化、不激活
  } catch { }
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

  # 全屏保护：全屏时自动后台最小化
  $fs = Test-ForegroundFullscreen
  $bg = $Background -or $fs
  if ($fs) { Write-RestartLog '检测到前台全屏应用 → 后台最小化启动（不抢焦点）' }
  elseif ($Background) { Write-RestartLog '后台模式（-Background）→ 最小化启动' }

  Write-RestartLog '启动 DSH…'
  if ($bg) {
    Start-Process -FilePath $exe -WindowStyle Minimized
    # 窗口句柄要过几秒才出现：等它出现后立刻最小化（Electron 不认 -WindowStyle，必须 ShowWindow）
    $winDeadline = (Get-Date).AddSeconds(20)
    $winDone = $false
    $lastHwnd = [IntPtr]::Zero
    while ((Get-Date) -lt $winDeadline) {
      Start-Sleep -Milliseconds 700
      $winProc = Get-Process 'DeepSeek Harness' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
      if ($winProc) {
        $lastHwnd = $winProc.MainWindowHandle
        Set-WindowMinimized $lastHwnd
        Start-Sleep -Milliseconds 300
        $winDone = $true
        break
      }
    }
    if ($winDone) { Write-RestartLog 'DSH 窗口已最小化（不激活）' }
    else { Write-RestartLog 'DSH 主窗口 20 秒内没出现（会继续在后台完成启动）' }
  } else {
    Start-Process -FilePath $exe
  }
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
