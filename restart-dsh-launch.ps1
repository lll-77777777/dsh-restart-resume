<#
  restart-dsh-launch.ps1 —— 安全地触发 DSH 重启（全局工具）
  为什么需要这个文件：
    从 DSH 会话（插件 / Agent 子进程）里直接跑 restart-dsh.ps1，
    重启脚本本身会处在 DSH 的进程树里，DSH 被杀时会被一起带走，
    结果只执行到「停止 DSH 主进程」就中断了。
  做法：
    用计划任务（任务计划程序启动的进程与 DSH 进程树无关）执行 restart-dsh.ps1。
  用法：
    powershell -NoProfile -ExecutionPolicy Bypass -File restart-dsh-launch.ps1
    （可选 -NoStart 只重启不等待；-VerifyOnly 只验证不重启）
#>
param(
  [switch]$NoStart,
  [switch]$VerifyOnly
)
$ErrorActionPreference = 'SilentlyContinue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ps1 = Join-Path $here 'restart-dsh.ps1'
$task = 'DSH-RestartOnce'
$extra = ''
if ($NoStart) { $extra = ' -NoStart' }
if ($VerifyOnly) { $extra = ' -VerifyOnly' }
$tr = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ps1`"$extra"
$at = (Get-Date).AddMinutes(5)

& schtasks.exe /Delete /TN $task /F 2>$null | Out-Null
& schtasks.exe /Create /TN $task /SC ONCE /ST $at.ToString('HH:mm') /SD $at.ToString('yyyy/MM/dd') /TR $tr /F | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host ("❌ 创建计划任务失败（schtasks 返回 {0}）" -f $LASTEXITCODE)
  exit 1
}
& schtasks.exe /Run /TN $task | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host '❌ 触发计划任务失败'
  exit 1
}
Write-Host "✅ 已通过计划任务触发重启（$task）——restart-dsh.ps1 会重启 DSH 并写日志"
