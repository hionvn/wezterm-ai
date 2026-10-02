# cap-nhat.ps1 — chép cấu hình đang dùng trên máy vào repo này (để commit + push sao lưu).
# Chạy sau mỗi lần sửa WezTerm / thanh trạng thái / lệnh tắt / quy tắc chung / script:
#   powershell -ExecutionPolicy Bypass -File .\cap-nhat.ps1
# Tự quét khoá bí mật ở cuối. Sau đó: git commit + push (AI làm giúp được).
$here = $PSScriptRoot
$AIRoot = 'E:\AI'
if (Test-Path "$HOME\.wez-ai.json") { $c = Get-Content "$HOME\.wez-ai.json" -Raw -Encoding UTF8 | ConvertFrom-Json; if ($c.aiRoot) { $AIRoot = $c.aiRoot } }
$caiDat = Join-Path $AIRoot 'Hion\cai-dat'
$utf8 = New-Object Text.UTF8Encoding $false

# Chạy thử mọi cấu hình / script trước (03/10/2026): có lỗi thì DỪNG, không chép bản hỏng vào repo
$kiem = Join-Path $caiDat 'kiem-cau-hinh.ps1'
if (Test-Path $kiem) {
    & $kiem
    if ($LASTEXITCODE) { Write-Host '⛔ Dừng: cấu hình đang có lỗi (xem dòng ❌ ở trên). Sửa xong chạy lại cap-nhat.ps1.' -ForegroundColor Red; exit 1 }
}

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

# Quy tắc chung: quy-tac\chung.md trong repo là BẢN CHUNG cho mọi người (sửa trực tiếp file đó), không chép từ máy
# vì ~\.claude\CLAUDE.md của bạn có thể chứa ghi chú riêng. Máy nào có đoạn đánh dấu "wezterm-ai" thì báo nếu lệch.
foreach ($o in @("$HOME\.claude\CLAUDE.md", "$HOME\.codex\AGENTS.md")) {
    if (-not (Test-Path $o)) { continue }
    $m = [regex]::Match([IO.File]::ReadAllText($o, [Text.Encoding]::UTF8), '(?s)<!-- wezterm-ai: bat-dau.*?<!-- wezterm-ai: het -->')
    if ($m.Success) {
        $repo = (Get-Content (Join-Path $here 'quy-tac\chung.md') -Raw -Encoding UTF8).Replace('E:\AI\', "$AIRoot\").Trim()
        if ($m.Value.Trim() -ne $repo) { Write-Host "  ⚠️  Đoạn quy tắc chung trong $o khác bản repo → sửa ở quy-tac\chung.md rồi chạy khoi-phuc.ps1" -ForegroundColor Yellow }
    }
}
# Bộ mẫu: mau\ trong repo là bản gốc; báo nếu bản đã cài trên máy bị sửa khác đi
$mauMay = Join-Path $caiDat 'mau'
if (Test-Path $mauMay) {
    foreach ($f in Get-ChildItem "$here\mau" -Recurse -File) {
        $m2 = Join-Path $mauMay ($f.FullName.Substring("$here\mau\".Length))
        if ((Test-Path $m2) -and (Get-FileHash $m2).Hash -ne (Get-FileHash $f.FullName).Hash) { Write-Host "  ⚠️  $m2 khác bản repo (mau\)" -ForegroundColor Yellow }
    }
}

# Claude: chỉ lấy phần statusLine + hooks của settings.json (phần còn lại là cài đặt riêng máy)
$s = Get-Content "$HOME\.claude\settings.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$part = [ordered]@{ statusLine = $s.statusLine; hooks = $s.hooks }
$json = ($part | ConvertTo-Json -Depth 20).Replace(($caiDat -replace '\\', '/'), 'E:/AI/Hion/cai-dat')
[IO.File]::WriteAllText((Join-Path $here 'claude\settings.phan-them.json'), $json, $utf8)
Write-Host '  ✓ claude\settings.phan-them.json'

# Codex: chỉ lấy dòng tiêu đề động (phần còn lại có thông tin đăng nhập, đường dẫn riêng máy)
$tt = Select-String -Path "$HOME\.codex\config.toml" -Pattern '^\s*terminal_title\s*=' | Select-Object -First 1
if ($tt) {
    $f = Join-Path $here 'codex\config.phan-them.toml'
    $lines = Get-Content $f -Encoding UTF8 | ForEach-Object { if ($_ -match '^\s*terminal_title\s*=') { $tt.Line.Trim() } else { $_ } }
    [IO.File]::WriteAllLines($f, [string[]]$lines, $utf8); Write-Host '  ✓ codex\config.phan-them.toml'
}

Write-Host "`nQuét khoá bí mật:" -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'quet-bi-mat.ps1')
git -C $here status --short
