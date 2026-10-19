# restart-dsh —— 重启 DeepSeek Harness（全局工具）

不属于任何插件，DSH 全量通用。放在 `C:\Users\ireina\.dsh\tools\restart-dsh\`。

## 用法

| 场景 | 命令 |
| --- | --- |
| 双击（最省事） | `restart-dsh.vbs` —— 静默重启，不闪窗口 |
| 双击（全静默） | `restart-dsh-hidden.vbs` —— 完全无窗口，连终端都不闪 |
| 命令行手动 | `powershell -NoProfile -ExecutionPolicy Bypass -File restart-dsh.ps1` |
| 只停不启 | `restart-dsh.ps1 -NoStart` |
| 只检查、不重启 | `restart-dsh.ps1 -VerifyOnly` |
| 自定义等待时长（等 web 端口就绪的上限） | `restart-dsh.ps1 -TimeoutSec 120`（默认 90 秒） |
| 后台重启（最小化、不抢焦点） | `restart-dsh.ps1 -Background` |
| **从 DSH 会话 / 插件 / Agent 内部触发** | `powershell -File restart-dsh-launch.ps1` —— 走计划任务，脱离 DSH 进程树，不会被连带杀掉 |
| 从会话内部触发 + 全静默 | `restart-dsh-launch.ps1 -Hidden` —— 计划任务用 wscript 跑 vbs，连 PowerShell 窗口都不弹 |
| 延迟 N 秒再重启（等手头任务跑完） | `powershell -File restart-dsh-launch.ps1 -DelaySec 30` |

### 全屏保护（不会打断你正在看的东西）

重启时如果检测到**前台有应用占满整个屏幕**（全屏游戏 / 全屏视频），会自动按「最小化 + 不抢焦点」的方式启动 DSH：
你的全屏不会被踢出来，DSH 窗口出现在任务栏（最小化状态），点一下就能用。

- 检测方式：`GetForegroundWindow` 的窗口矩形 == 所在显示器的完整矩形（多屏按前台窗口那块屏判断）
- Electron 启动时不认 `-WindowStyle Minimized`，所以脚本会在窗口句柄出现后（最多等 20 秒）用 `ShowWindow(SW_MINIMIZE)` 补一次
- 不在全屏但你想强制后台：`-Background`
- 从 DSH 会话里自动重启：`restart-dsh-launch.ps1 -Hidden`（wscript 全静默，配合全屏保护就是「你干你的，DSH 自己默默重启」）


### 能调的三个时间

| 时间 | 参数 | 默认 | 说明 |
| --- | --- | --- | --- |
| 重启前延迟 | `restart-dsh-launch.ps1 -DelaySec N` | 0（立即） | 先等 N 秒再触发重启 |
| 等 DSH 起来的上限 | `restart-dsh.ps1 -TimeoutSec N` | 90 秒 | 超过就记 ❌；DSH 冷启动一般 10~40 秒，别设太小 |
| 重启后自动继续的提醒延迟 | 改 `resume-delay.txt` 里的数字（秒） | 30 秒 | 设得比重启耗时略短，重启一完成就补发、几乎无缝；90/180 秒反而要干等 |

> 原理：提醒在 DSH 关闭期间到期 → 重启恢复后立即补发。所以「设短」不是更危险，而是更快。
> 自定义：用记事本打开同目录 `resume-delay.txt`，改里面的秒数（如 45 / 60），保存即可；技能 `dsh-restart-resume` 会读它。

## 看门狗（watchdog）：让 DSH 会话自己触发重启

DSH 会话里 spawn 的进程被 Windows ACL 挡在任务计划存储之外（`schtasks` 全报「系统找不到指定的路径」，`Get-ScheduledTask`/`Start-ScheduledTask` 全报拒绝访问），所以会话**不能**自己建/触发计划任务。看门狗把这条通路倒过来：会话只负责**放一个文件**，真正动手的是计划任务。

1. 用户手动建一次计划任务（管理员 PowerShell，`/sc minute /mo 1` 每分钟一次）：
   ```
   schtasks /create /tn DSH-RestartWatchdog /sc minute /mo 1 ^
     /tr "wscript.exe \"C:\Users\ireina\.dsh\tools\restart-dsh\watchdog-hidden.vbs\""
   ```
2. 之后任何 DSH 会话只要往同目录写 `restart-request.txt`，**一分钟内**看门狗就会捡到并重启 DSH。

| 文件 | 作用 |
| --- | --- |
| `watchdog.ps1` | 计划任务每分钟跑一次；捡到请求 → 改名 `.working` 抢占（防重入）→ 跑 `restart-dsh.ps1` → 清 `.working` |
| `watchdog-hidden.vbs` | 用 wscript 以 `intWindowStyle=0` 启动 `watchdog.ps1`，**完全不闪窗口**（计划任务直接跑 powershell.exe 会每分钟闪一次黑框） |
| `watchdog-ping.txt` | 心跳自检：丢了它 → 看门狗只写日志 `heartbeat ok`，不重启（放完自动删） |
| `watchdog.log` | 看门狗日志（与 `restart.log` 分开） |

判定看门狗活着看 `watchdog.log` 里有没有 `restart requested`；轮询周期 60 秒，**写完请求至少等 90 秒再下结论**，别在周期内判死。

两个必须遵守的坑：

- `watchdog.ps1`、`watchdog-hidden.vbs` 必须保持**纯 ASCII**——PowerShell 5.1 读无 BOM 的 .ps1 时按 ANSI 解析，中文注释会直接把脚本解析失败。
- 子脚本（`restart-dsh.ps1`）的输出**不能**用 `*>> $logFile` 直接重定向：那样会按控制台代码页（简体中文 = GBK）写进 UTF-8 日志，中文全变 `\Pbk DSH` 这种乱码。正确做法是
  ```powershell
  $out = & (Join-Path $here 'restart-dsh.ps1') *>&1 | Out-String
  foreach ($line in ($out -split "`r?`n")) { if ($line.Trim()) { Write-WatchLog $line.TrimEnd() } }
  ```
  先捕获成 Unicode 字符串再逐行走 `Add-Content -Encoding UTF8`；`*>&1` 还能把 `Write-Host` 的 Information 流一起捞进来。

## 日志

同目录 `restart.log`，每次重启写：停止（PID）→ 启动 → web 端口就绪 → 主进程/进程数 → 完成。

## 重启后自动继续（配合 DSH 定时提醒）

重启会杀掉「正在跑的那一轮任务」，但 DSH 的定时提醒（schedule）**会持久化，并在重启后补发**。
所以只要在重启前埋一条提醒，重启后就被自动叫醒继续：

1. 重启前，在当前会话里调用 `schedule_create`（**延迟自己定**，推荐 30 秒——DSH 重启约 12~40 秒，设得比它略短，重启一完成就补发、几乎无缝），例如：
   ```json
   { "after_seconds": 30, "title": "重启后继续", "prompt": "重启已完成，请继续上次未完成的任务" }
   ```
2. 立刻执行 `restart-dsh-launch.ps1` 重启（想先等手头任务跑完就加 `-DelaySec 30`）
3. DSH 起来、会话恢复时，这条错过的提醒会被补发 → agent 自动接着干

注意：
- 提醒只对「创建它的那个会话」有效；换会话不会补发
- 任务提前完成的话，用 `schedule_delete` 删掉提醒
- 手动双击 `restart-dsh.vbs` 没有提醒可补发，需要重启后人工说一句「继续」
- 完整操作流程见技能 `dsh-restart-resume`（`C:\Users\ireina\.dsh\skills\dsh-restart-resume\SKILL.md`）

## 说明

- DSH 的主进程 = `DeepSeek Harness.exe` 里命令行不带 `--type=` 的那个
- DSH web 端口是随机的，脚本从 DSH 进程的监听端口里找、用 TCP 连接确认就绪
- 重启后已打开的 GUI 页面需要刷新才能用（`dsh web` 会打印新 URL）
