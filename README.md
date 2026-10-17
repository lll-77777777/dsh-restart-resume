# restart-dsh —— 重启 DeepSeek Harness（全局工具）

不属于任何插件，DSH 全量通用。放在 `C:\Users\ireina\.dsh\tools\restart-dsh\`。

## 用法

| 场景 | 命令 |
| --- | --- |
| 双击（最省事） | `restart-dsh.vbs` —— 静默重启，不闪窗口 |
| 命令行手动 | `powershell -NoProfile -ExecutionPolicy Bypass -File restart-dsh.ps1` |
| 只停不启 | `restart-dsh.ps1 -NoStart` |
| 只检查、不重启 | `restart-dsh.ps1 -VerifyOnly` |
| 自定义等待时长（等 web 端口就绪的上限） | `restart-dsh.ps1 -TimeoutSec 120`（默认 90 秒） |
| **从 DSH 会话 / 插件 / Agent 内部触发** | `powershell -File restart-dsh-launch.ps1` —— 走计划任务，脱离 DSH 进程树，不会被连带杀掉 |
| 延迟 N 秒再重启（等手头任务跑完） | `powershell -File restart-dsh-launch.ps1 -DelaySec 30` |

### 能调的三个时间

| 时间 | 参数 | 默认 | 说明 |
| --- | --- | --- | --- |
| 重启前延迟 | `restart-dsh-launch.ps1 -DelaySec N` | 0（立即） | 先等 N 秒再触发重启 |
| 等 DSH 起来的上限 | `restart-dsh.ps1 -TimeoutSec N` | 90 秒 | 超过就记 ❌；DSH 冷启动一般 10~40 秒，别设太小 |
| 重启后自动继续的提醒延迟 | 改 `resume-delay.txt` 里的数字（秒） | 30 秒 | 设得比重启耗时略短，重启一完成就补发、几乎无缝；90/180 秒反而要干等 |

> 原理：提醒在 DSH 关闭期间到期 → 重启恢复后立即补发。所以「设短」不是更危险，而是更快。
> 自定义：用记事本打开同目录 `resume-delay.txt`，改里面的秒数（如 45 / 60），保存即可；技能 `dsh-restart-resume` 会读它。

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
