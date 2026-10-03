# cap-nhat-tu-github.ps1 — kéo bản mới nhất của "đội AI trên WezTerm" từ GitHub về máy rồi cài lại.
# Đây là việc của nút "⬆ Cập nhật đội AI" (Ctrl+Shift+P). Chạy tay:
#   powershell -ExecutionPolicy Bypass -File E:\AI\wezterm-ai\cap-nhat-tu-github.ps1          # kiểm → có bản mới thì kéo + cài
#   ... -Kiem    chỉ kiểm có bản mới không, ghi %LOCALAPPDATA%\wez-ai\ban-moi.json (WezTerm đọc để báo)
#   ... -Ep      chạy cả trên máy chủ ("chuNhan": true trong ~\.wez-ai.json)
# Cài lại = khoi-phuc.ps1 -CapNhat: file giống hệt thì bỏ qua, file khác thì sao lưu .bak-<giờ> rồi ghi đè;
# cài đặt riêng trong ~\.wez-ai.json và file của Tổng quản (Hion\*.md) giữ nguyên.
param([switch]$Kiem, [switch]$Ep)
$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot
$utf8 = New-Object Text.UTF8Encoding $false
$stateDir = Join-Path $env:LOCALAPPDATA 'wez-ai'
$state = Join-Path $stateDir 'ban-moi.json'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

$may = $null
if (Test-Path "$HOME\.wez-ai.json") { try { $may = Get-Content "$HOME\.wez-ai.json" -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
$chuNhan = $may -and $may.chuNhan -eq $true

function Ghi($moi, $ds, $dau) {
    $o = [ordered]@{ moi = $moi; ds = @($ds); dau = $dau; luc = (Get-Date -Format 'yyyy-MM-dd HH:mm') }
    [IO.File]::WriteAllText($state, ($o | ConvertTo-Json), $utf8)
}

if (-not (Get-Command git -ErrorAction SilentlyContinue) -or -not (Test-Path "$here\.git")) {
    if (-not $Kiem) { Write-Host "⚠️  Thư mục $here không phải bản clone git → không cập nhật tự động được. Cài lại theo README (gh repo clone hionvn/wezterm-ai)." -ForegroundColor Yellow }
    exit 1
}

$nhanh = (git -C $here rev-parse --abbrev-ref HEAD 2>$null)
if (-not $nhanh -or $nhanh -eq 'HEAD') { $nhanh = 'main' }
git -C $here fetch -q origin $nhanh 2>$null
if ($LASTEXITCODE -ne 0) {
    if (-not $Kiem) { Write-Host '⚠️  Không kết nối được GitHub (mạng?). Thử lại sau.' -ForegroundColor Yellow }
    exit 1
}
$dau = (git -C $here rev-parse "origin/$nhanh" 2>$null)
$moi = [int](git -C $here rev-list --count "HEAD..origin/$nhanh" 2>$null)
$ds = @(git -C $here log --format='%ad · %s' --date=format:'%d/%m %H:%M' "HEAD..origin/$nhanh" 2>$null | Select-Object -First 15)
Ghi $moi $ds $dau
if ($Kiem) { exit 0 }

Write-Host "`n⬆ Cập nhật đội AI từ GitHub" -ForegroundColor Cyan
if ($chuNhan -and -not $Ep) {
    Write-Host '📌 Đây là máy chủ (bản gốc nằm ở máy này). Để phát hành bản mới cho đối tác:' -ForegroundColor Yellow
    Write-Host '   1) powershell -File E:\AI\wezterm-ai\cap-nhat.ps1   (chép cấu hình đang dùng vào repo + quét khoá)'
    Write-Host '   2) commit + push repo wezterm-ai  →  máy đối tác bấm "Cập nhật đội AI" là nhận.'
    exit 0
}
if ($moi -eq 0) { Write-Host '✅ Đang là bản mới nhất, không có gì để cập nhật.' -ForegroundColor Green; exit 0 }

Write-Host "Có $moi thay đổi mới:" -ForegroundColor Green
$ds | ForEach-Object { Write-Host "  • $_" }
if ($moi -gt $ds.Count) { Write-Host "  … và $($moi - $ds.Count) thay đổi khác" }

# File trong repo bị sửa tay → cất riêng (git stash) để kéo bản mới không bị chặn; lấy lại: git stash pop
if (git -C $here status --porcelain 2>$null) {
    $ten = 'truoc-cap-nhat-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    git -C $here stash push -u -q -m $ten 2>$null
    Write-Host "📦 Bạn có sửa file trong repo → đã cất riêng ($ten). Lấy lại: git -C `"$here`" stash pop" -ForegroundColor Yellow
}
git -C $here pull -q --ff-only origin $nhanh 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host '⚠️  Không kéo được bản mới (lịch sử repo trên máy khác GitHub). Gửi ảnh màn hình này cho người hỗ trợ.' -ForegroundColor Red
    exit 1
}
Write-Host '✓ Đã kéo bản mới. Cài lại cấu hình…' -ForegroundColor Green
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'khoi-phuc.ps1') -CapNhat
Ghi 0 @() $dau
