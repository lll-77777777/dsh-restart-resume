<#
  watchdog.ps1 - restart watchdog: a "remote switch" for DSH sessions
  ============================================================================
  Run by the scheduled task DSH-RestartWatchdog once per minute.
  No request file -> exit immediately, do nothing.

  How a DSH session uses it:
    create restart-request.txt in this folder -> DSH restarts within a minute

  Why this exists:
    The Windows token of a process started inside a DSH session is denied by
    ACL on the Task Scheduler store (create/query/delete all fail with
    "The system cannot find the path specified", which is really access
    denied on C:\Windows\System32\Tasks). A session process therefore cannot
    restart DSH itself; a scheduled task is the only channel that outlives
    the session. So the job lives here, and the session only drops a file.

  Re-entry guard: rename the request file to .working to claim it first.
  Heartbeat: drop watchdog-ping.txt -> proves the task runs, restarts nothing.
  Log: watchdog.log in this folder.

  NOTE: keep this file pure ASCII. Windows PowerShell 5.1 reads .ps1 as ANSI
  when there is no BOM, and non-ASCII text breaks the parser.
  ============================================================================
#>

$ErrorActionPreference = 'SilentlyContinue'

# Resolve this folder reliably; $MyInvocation alone can be empty under -File.
$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $here) { $here = 'C:\Users\ireina\.dsh\tools\restart-dsh' }

$req = Join-Path $here 'restart-request.txt'
$work = Join-Path $here 'restart-request.working'
$ping = Join-Path $here 'watchdog-ping.txt'
$logFile = Join-Path $here 'watchdog.log'

function Write-WatchLog([string]$text) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $text"
  Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

# Heartbeat self-check: proves the task is running, restarts nothing.
if (Test-Path -LiteralPath $ping) {
  Remove-Item -LiteralPath $ping -Force
  Write-WatchLog 'heartbeat ok: watchdog task is running; DSH not restarted'
  exit 0
}

# No request: nothing to do (this is the once-a-minute idle path).
if (-not (Test-Path -LiteralPath $req)) { exit 0 }

# Claim the request by renaming it; only the winner restarts DSH.
try {
  Move-Item -LiteralPath $req -Destination $work -Force -ErrorAction Stop
} catch {
  exit 0
}

Write-WatchLog 'restart requested (restart-request.txt found)'

if (-not (Test-Path -LiteralPath $work)) { exit 0 }

# Game guard: never restart DSH automatically while a game is running. Killing
# and respawning the Electron GPU context tears down exclusive-fullscreen
# games, so an automatic restart can close the game. Owner asked: ask first, he
# restarts himself. The automatic path just backs off and drops the request.
# NOTE: keep this text pure ASCII (see the header note).
$gameNames = @(
  'LeagueClient', 'LeagueClientUx', 'League of Legends', 'RiotClientServices',
  'VALORANT', 'VALORANT-Win64-Shipping', 'cs2', 'dota2',
  'GenshinImpact', 'YuanShen', 'StarRail', 'HonkaiStarRail', 'Overwatch', 'steam'
)
$games = @()
foreach ($n in $gameNames) {
  if (Get-Process -Name $n -ErrorAction SilentlyContinue) { $games += $n }
}
if ($games.Count -gt 0) {
  Write-WatchLog ("game running ({0}) -> restart skipped, waiting for owner" -f ($games -join ', '))
  Remove-Item -LiteralPath $work -Force -ErrorAction SilentlyContinue
  exit 0
}

Write-WatchLog 'running restart-dsh.ps1'
try {
  # Capture the child script's output as Unicode text and write it through
  # Write-WatchLog, so the whole log stays UTF-8. Plain ">> $logFile"
  # redirection encodes the child's text in the console code page (GBK on
  # this box), which is what garbled the Chinese lines.
  $out = & (Join-Path $here 'restart-dsh.ps1') *>&1 | Out-String
  $exit = $LASTEXITCODE
  foreach ($line in ($out -split "`r?`n")) {
    if ($line.Trim().Length -gt 0) { Write-WatchLog $line.TrimEnd() }
  }
  Write-WatchLog "restart-dsh.ps1 exit code = $exit"
} catch {
  Write-WatchLog "restart-dsh.ps1 threw: $($_.Exception.Message)"
}

Remove-Item -LiteralPath $work -Force
Write-WatchLog 'restart flow finished'
exit 0
