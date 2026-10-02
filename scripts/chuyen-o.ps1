# Bấm thông báo → Windows mở link wezai-o:<PANEID> → script này: chọn đúng ô (kể cả ở tab khác) và đưa WezTerm lên trước.
param([string]$Uri = '')
$id = [regex]::Match($Uri, '\d+').Value
if (-not $id) { exit 1 }

$WezExe = 'C:\Program Files\WezTerm\wezterm.exe'
$cfg = Join-Path $HOME '.wez-ai.json'
if (Test-Path $cfg) { try { $j = Get-Content $cfg -Raw | ConvertFrom-Json; if ($j.wezExe) { $WezExe = $j.wezExe } } catch {} }
if (-not (Test-Path $WezExe)) { $WezExe = (Get-Command wezterm -ErrorAction SilentlyContinue).Source }

& $WezExe cli activate-pane --pane-id $id 2>$null | Out-Null

Add-Type @'
using System; using System.Runtime.InteropServices;
public static class WinFront {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
}
'@
foreach ($p in Get-Process wezterm-gui -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }) {
    $h = $p.MainWindowHandle
    if ([WinFront]::IsIconic($h)) { [void][WinFront]::ShowWindowAsync($h, 9) }   # 9 = khôi phục khi đang thu nhỏ
    [void][WinFront]::SetForegroundWindow($h)
}
