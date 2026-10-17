' restart-dsh-hidden.vbs —— 静默重启 DSH（完全隐藏终端窗口）
' 用法：wscript //nologo restart-dsh-hidden.vbs [-Background] [-TimeoutSec 120]
Dim args, i, cmd
args = ""
For i = 0 To WScript.Arguments.Count - 1
  args = args & " " & WScript.Arguments(i)
Next
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\Users\ireina\.dsh\tools\restart-dsh\restart-dsh.ps1""" & args
CreateObject("WScript.Shell").Run cmd, 0, False
