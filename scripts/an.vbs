' Chạy một script PowerShell mà không nháy cửa sổ đen.
' Dùng: wscript.exe an.vbs <file.ps1> [tham số...]
Set sh = CreateObject("WScript.Shell")
args = ""
For Each a In WScript.Arguments
  args = args & " """ & Replace(a, """", "'") & """"
Next
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File" & args, 0, False
