---
name: dsh-restart-resume
description: 需要重启 DeepSeek Harness（DSH）时使用——先在本会话埋一条 DSH 定时提醒，再触发重启；重启后错过的提醒会补发，agent 自动接着干上次没做完的任务，用户不用手动打「继续」。适用于「重启后继续」「重启别丢进度」「装/改插件要重启」等场景。
---

# dsh-restart-resume —— 重启 DSH 且重启后自动继续

## 什么时候用
- 要重启 DSH（装/改 host 插件、升级、进程卡住），且当前会话还有没做完的任务
- 用户说「重启后接着干」「重启别丢进度」「继续上次的活」

## 步骤

1. **先埋提醒**（在当前会话里）：
   ```
   schedule_create(after_seconds=180, title="重启后继续", prompt="重启已完成，请继续上次未完成的任务")
   ```
   180 秒足够覆盖重启（约 15 秒）+ 会话恢复；太短可能在 DSH 起来前就过期。

2. **触发重启**（走计划任务，脱离 DSH 进程树，不会被连带杀掉）：
   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\ireina\.dsh\tools\restart-dsh\restart-dsh-launch.ps1"
   ```

3. **等补发**：DSH 重启后，到点时那条错过的提醒会补发到原会话，agent 自动被叫醒，继续干活。

## 原理

DSH 的定时提醒持久化在会话里；重启后错过的那次会补发（DSH 文档：「After downtime, a recurring reminder delivers only its latest missed occurrence」）。补发会触发新的一轮 agent turn，等于自动「继续」。

## 注意

- 提醒只对**创建它的会话**有效，换会话不会补发。
- 手动双击 `C:\Users\ireina\.dsh\tools\restart-dsh\restart-dsh.vbs` **不会**埋提醒；要自动继续就用本流程。
- 任务提前完成时，用 `schedule_delete` 删掉提醒，避免之后多余地叫醒。
- 重启后已打开的 GUI 页面需要刷新（`dsh web` 会打印新 URL）。
