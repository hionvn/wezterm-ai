# Đăng ký link wezai-o: cho tài khoản Windows hiện tại (HKCU, không cần quyền Administrator).
# Bấm thông báo của đội AI → chạy chuyen-o.ps1 → nhảy về đúng ô WezTerm.
# Gỡ: .\dang-ky-thong-bao.ps1 -Go
param([switch]$Go)
$key = 'HKCU:\Software\Classes\wezai-o'
if ($Go) { Remove-Item $key -Recurse -Force -ErrorAction SilentlyContinue; Write-Host 'Đã gỡ link wezai-o:'; return }
$dir = $PSScriptRoot
New-Item "$key\shell\open\command" -Force | Out-Null
Set-ItemProperty $key '(default)' 'URL:WezTerm AI - nhay ve o'
Set-ItemProperty $key 'URL Protocol' ''
Set-ItemProperty "$key\shell\open\command" '(default)' ('wscript.exe "{0}\an.vbs" "{0}\chuyen-o.ps1" "%1"' -f $dir)
Write-Host "Đã đăng ký link wezai-o: → $dir\chuyen-o.ps1"
