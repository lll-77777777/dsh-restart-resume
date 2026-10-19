---
name: dsh-restart-resume
description: 需要重启 DeepSeek Harness（DSH）时使用——先在本会话埋一条 DSH 定时提醒，再触发重启；重启后错过的提醒会补发，agent 自动接着干上次没做完的任务，用户不用手动打「继续」。适用于「重启后继续」「重启别丢进度」「装/改插件要重启」等场景。
---

# dsh-restart-resume —— 重启 DSH 且重启后自动继续

## 什么时候用
- 要重启 DSH（装/改 host 插件、升级、进程卡住），且当前会话还有没做完的任务
- 用户说「重启后接着干」「重启别丢进度」「继续上次的活」

## 步骤

1. **读「重启后继续」的等待时间**（可在文件里自己改，不用叫 agent）：
   ```
   C:\Users\ireina\.dsh\tools\restart-dsh\resume-delay.txt
   ```
   - 里面就一个数字（秒），默认 `30`
   - 读出来用它；文件不存在/不是数字 → 回退默认 30
   - 想改：用记事本打开改成 15 / 45 / 60 等，保存即可

2. **先埋提醒**（在当前会话里，`after_seconds` 用上一步读到的值）：
   ```
   schedule_create(after_seconds=30, title="重启后继续", prompt="重启已完成，请继续上次未完成的任务")
   ```
   **设短一点反而更快**：DSH 重启实测约 12~40 秒；把 `after_seconds` 设得**比重启耗时略短**（30 秒左右），提醒就会在 DSH 关闭期间到期，重启一完成立刻补发，几乎无缝继续。设成 90/180 秒反而要干等到点。想稳一点就 45~60 秒。

3. **触发重启**（走计划任务，脱离 DSH 进程树，不会被连带杀掉）：
   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\ireina\.dsh\tools\restart-dsh\restart-dsh-launch.ps1"
   ```
   想「先等手头任务跑完再重启」：加 `-DelaySec 30`（等 30 秒再触发）。

   > 备用通道：若本机装了看门狗计划任务（`DSH-RestartWatchdog`，见 README「看门狗」一节），也可以只往 `C:\Users\ireina\.dsh\tools\restart-dsh\restart-request.txt` 写一个文件，最长等 60 秒它就会动手。适合 `restart-dsh-launch.ps1` 被沙箱/权限挡住时。

4. **等补发**：DSH 重启后，到点时那条错过的提醒会补发到原会话，agent 自动被叫醒，继续干活。

## 原理

DSH 的定时提醒持久化在会话里；重启后错过的那次会补发（DSH 文档：「After downtime, a recurring reminder delivers only its latest missed occurrence」）。补发会触发新的一轮 agent turn，等于自动「继续」。

## 注意

- 提醒只对**创建它的会话**有效，换会话不会补发。
- 手动双击 `C:\Users\ireina\.dsh\tools\restart-dsh\restart-dsh.vbs` **不会**埋提醒；要自动继续就用本流程。
- 任务提前完成时，用 `schedule_delete` 删掉提醒，避免之后多余地叫醒。
- 重启后已打开的 GUI 页面需要刷新（`dsh web` 会打印新 URL）。
