# cap-nhat.ps1 — chép cấu hình đang dùng trên máy vào repo này (để commit + push sao lưu).
# Chạy sau mỗi lần sửa WezTerm / thanh trạng thái / lệnh tắt / quy tắc chung / script:
#   powershell -ExecutionPolicy Bypass -File .\cap-nhat.ps1
# Tự quét khoá bí mật ở cuối. Sau đó: git commit + push (AI làm giúp được).
$here = $PSScriptRoot
$AIRoot = 'E:\AI'
if (Test-Path "$HOME\.wez-ai.json") { $c = Get-Content "$HOME\.wez-ai.json" -Raw -Encoding UTF8 | ConvertFrom-Json; if ($c.aiRoot) { $AIRoot = $c.aiRoot } }
$caiDat = Join-Path $AIRoot '_Hub\cai-dat'
$utf8 = New-Object Text.UTF8Encoding $false

$copies = @(
    @("$HOME\.wezterm.lua", 'wezterm\.wezterm.lua'),
    @("$HOME\.claude\statusline.js", 'claude\statusline.js'),
    @($PROFILE, 'powershell\Microsoft.PowerShell_profile.ps1')
)
foreach ($c in $copies) { Copy-Item $c[0] (Join-Path $here $c[1]) -Force; Write-Host "  ✓ $($c[1])" }

# Script: chép mọi file repo đang theo dõi trong scripts\; báo file mới ở cai-dat chưa có trong repo
foreach ($f in Get-ChildItem "$here\scripts" -File) {
    $src = Join-Path $caiDat $f.Name
    if (Test-Path $src) { Copy-Item $src $f.FullName -Force; Write-Host "  ✓ scripts\$($f.Name)" }
    else { Write-Host "  ⚠️  scripts\$($f.Name): không còn trong $caiDat" -ForegroundColor Yellow }
}
$moi = Get-ChildItem $caiDat -File | Where-Object { $_.Name -notmatch '\.bak-' -and -not (Test-Path (Join-Path "$here\scripts" $_.Name)) }
foreach ($m in $moi) { Write-Host "  ℹ️  $caiDat\$($m.Name) chưa có trong repo (muốn sao lưu thì chép vào scripts\)" -ForegroundColor DarkCyan }

# Quy tắc chung: 1 file gốc (bản của Claude), cảnh báo nếu bản Codex / Gemini đã bị sửa khác đi
$rule = "$HOME\.claude\CLAUDE.md"
$text = [IO.File]::ReadAllText($rule, [Text.Encoding]::UTF8)
if ($AIRoot -ne 'E:\AI') { $text = $text.Replace("$AIRoot\", 'E:\AI\') }   # repo luôn ghi E:\AI, khoi-phuc.ps1 đổi theo máy
[IO.File]::WriteAllText((Join-Path $here 'quy-tac\chung.md'), $text, $utf8); Write-Host '  ✓ quy-tac\chung.md'
foreach ($o in "$HOME\.codex\AGENTS.md", "$HOME\.gemini\GEMINI.md") {
    if ((Get-FileHash $o).Hash -ne (Get-FileHash $rule).Hash) {
        Write-Host "  ⚠️  $o khác ~\.claude\CLAUDE.md → repo chỉ lưu bản của Claude. Chép đè cho giống nhau nếu cần." -ForegroundColor Yellow
    }
}

# Claude: chỉ lấy phần statusLine + hooks của settings.json (phần còn lại là cài đặt riêng máy)
$s = Get-Content "$HOME\.claude\settings.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$part = [ordered]@{ statusLine = $s.statusLine; hooks = $s.hooks }
$json = ($part | ConvertTo-Json -Depth 20).Replace(($caiDat -replace '\\', '/'), 'E:/AI/_Hub/cai-dat')
[IO.File]::WriteAllText((Join-Path $here 'claude\settings.phan-them.json'), $json, $utf8)
Write-Host '  ✓ claude\settings.phan-them.json'

# Codex / Gemini: chỉ lấy dòng tiêu đề động (phần còn lại có thông tin đăng nhập, đường dẫn riêng máy)
$tt = Select-String -Path "$HOME\.codex\config.toml" -Pattern '^\s*terminal_title\s*=' | Select-Object -First 1
if ($tt) {
    $f = Join-Path $here 'codex\config.phan-them.toml'
    $lines = Get-Content $f -Encoding UTF8 | ForEach-Object { if ($_ -match '^\s*terminal_title\s*=') { $tt.Line.Trim() } else { $_ } }
    [IO.File]::WriteAllLines($f, [string[]]$lines, $utf8); Write-Host '  ✓ codex\config.phan-them.toml'
}
if (-not (Select-String -Path "$HOME\.gemini\settings.json" -Pattern '"dynamicWindowTitle"\s*:\s*true' -Quiet)) {
    Write-Host '  ⚠️  Gemini đang tắt dynamicWindowTitle → không có báo động cho Gemini' -ForegroundColor Yellow
}

Write-Host "`nQuét khoá bí mật:" -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'quet-bi-mat.ps1')
git -C $here status --short
