# cap-nhat.ps1 — chép cấu hình đang dùng trên máy vào repo này (để commit + push sao lưu).
# Chạy sau mỗi lần sửa WezTerm / thanh trạng thái / lệnh tắt / quy tắc chung:
#   powershell -ExecutionPolicy Bypass -File .\cap-nhat.ps1
# Sau đó: quét khoá bí mật rồi git commit + push (AI làm giúp được).
$here = $PSScriptRoot
$copies = @(
    @("$HOME\.wezterm.lua", 'wezterm\.wezterm.lua'),
    @("$HOME\.claude\statusline.js", 'claude\statusline.js'),
    @($PROFILE, 'powershell\Microsoft.PowerShell_profile.ps1'),
    @("$HOME\.claude\CLAUDE.md", 'quy-tac\claude-CLAUDE.md'),
    @("$HOME\.codex\AGENTS.md", 'quy-tac\codex-AGENTS.md'),
    @("$HOME\.gemini\GEMINI.md", 'quy-tac\gemini-GEMINI.md')
)
foreach ($c in $copies) { Copy-Item $c[0] (Join-Path $here $c[1]) -Force; Write-Host "  ✓ $($c[1])" }
foreach ($n in 'wez.ps1', 'wez-alert.js', 'mo-tai-lieu.js', 'can-duyet-view.ps1') {
    Copy-Item "E:\AI\_Hub\cai-dat\$n" (Join-Path $here "scripts\$n") -Force; Write-Host "  ✓ scripts\$n"
}
# Chỉ lấy phần statusLine + hooks của settings.json Claude (phần còn lại là cài đặt riêng máy)
$s = Get-Content "$HOME\.claude\settings.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$part = [ordered]@{ statusLine = $s.statusLine; hooks = $s.hooks }
[IO.File]::WriteAllText((Join-Path $here 'claude\settings.phan-them.json'), ($part | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding $false))
Write-Host "  ✓ claude\settings.phan-them.json"
git -C $here status --short
