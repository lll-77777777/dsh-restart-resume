' watchdog-hidden.vbs - start watchdog.ps1 with no console window at all
' ===========================================================================
' Called by the scheduled task DSH-RestartWatchdog once per minute.
'
' Why this wrapper exists:
'   Pointing the task straight at powershell.exe flashes a console window on
'   screen every run, because Windows still allocates a console for the
'   process even with -WindowStyle Hidden. WScript.Shell.Run with intWindowStyle
'   0 starts it with no window at all. The task itself then only ever launches
'   wscript.exe, which is a GUI-subsystem host and never shows a console.
'
' Keep this file pure ASCII.
' ===========================================================================

Dim sh, here, script, cmd

Set sh = CreateObject("WScript.Shell")

' Derive the folder from this script's own path; fall back to the fixed path.
here = ""
On Error Resume Next
here = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\") - 1)
On Error GoTo 0
If here = "" Then
  here = "C:\Users\ireina\.dsh\tools\restart-dsh"
End If

script = here & "\watchdog.ps1"
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & script & """"

' 0 = hidden window, False = do not wait for it to finish
sh.Run cmd, 0, False
