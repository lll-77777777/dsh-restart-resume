' 静默重启 DSH（全局工具）：wscript //nologo restart-dsh.vbs
' 双击即可；会调用同目录 restart-dsh.ps1（隐藏窗口），日志见 restart.log
Set sh = CreateObject("WScript.Shell")
here = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
sh.Run "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & here & "restart-dsh.ps1""", 0, False
