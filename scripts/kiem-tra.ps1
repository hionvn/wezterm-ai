# kiem-tra.ps1 — tự chẩn đoán bộ "đội AI trong WezTerm": thiếu gì, cài sai chỗ nào, sửa thế nào.
# Chạy trong PowerShell:
#   powershell -ExecutionPolicy Bypass -File E:\AI\_Hub\cai-dat\kiem-tra.ps1
# Chỉ đọc, không sửa gì trên máy. Mã thoát = số lỗi ❌.
$loi = 0; $canhBao = 0
function Ok($m) { Write-Host "  ✅ $m" -ForegroundColor Green }
function Warn($m, $fix) { $script:canhBao++; Write-Host "  ⚠️  $m" -ForegroundColor Yellow; if ($fix) { Write-Host "      👉 $fix" -ForegroundColor DarkYellow } }
function Bad($m, $fix) { $script:loi++; Write-Host "  ❌ $m" -ForegroundColor Red; if ($fix) { Write-Host "      👉 $fix" -ForegroundColor DarkYellow } }
function Has($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
$repoFix = 'chạy lại khoi-phuc.ps1 trong thư mục repo wezterm-ai'

Write-Host "`n[1] Cấu hình chung của máy" -ForegroundColor Cyan
$AIRoot = 'E:\AI'; $WezExe = 'C:\Program Files\WezTerm\wezterm.exe'
if (Test-Path "$HOME\.wez-ai.json") {
    try {
        $cfg = Get-Content "$HOME\.wez-ai.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.aiRoot) { $AIRoot = $cfg.aiRoot }; if ($cfg.wezterm) { $WezExe = $cfg.wezterm }
        Ok "~\.wez-ai.json: thư mục dự án = $AIRoot"
    } catch { Bad '~\.wez-ai.json bị hỏng (không đọc được JSON)' $repoFix }
} else { Warn "Chưa có ~\.wez-ai.json → dùng mặc định $AIRoot" 'chỉ cần nếu dự án không nằm ở E:\AI; khoi-phuc.ps1 -AIRoot <thư mục> sẽ tạo' }
$Hub = Join-Path $AIRoot '_Hub'; $CaiDat = Join-Path $Hub 'cai-dat'
if (Test-Path $AIRoot) { Ok "Có thư mục dự án $AIRoot" } else { Bad "Không thấy $AIRoot" 'tạo thư mục hoặc sửa aiRoot trong ~\.wez-ai.json' }
if (Test-Path $Hub) { Ok "Có $Hub (Tổng quản)" } else { Bad "Không thấy $Hub" "clone dự án Hub về: gh repo clone hionvn/ai-hub $Hub" }
foreach ($f in 'wez.ps1', 'wez-alert.js', 'mo-tai-lieu.js', 'can-duyet-view.ps1', 'khoa.js') {
    if (-not (Test-Path (Join-Path $CaiDat $f))) { Bad "Thiếu script $CaiDat\$f" $repoFix }
}
if (Test-Path (Join-Path $CaiDat 'khoa.js')) { Ok "Đủ script trong $CaiDat" }

Write-Host "`n[2] Phần mềm" -ForegroundColor Cyan
if (-not (Test-Path $WezExe) -and (Has wezterm)) { $WezExe = (Get-Command wezterm).Source }
if (Test-Path $WezExe) {
    $v = (& $WezExe --version) -replace '^wezterm\s+', ''
    if ($v -match '^(\d{8})' -and [int]$Matches[1] -ge 20240203) { Ok "WezTerm $v" } else { Bad "WezTerm $v cũ quá (cần 20240203 trở lên)" 'winget upgrade wez.wezterm' }
} else { Bad 'Chưa cài WezTerm' 'winget install wez.wezterm' }
if (Test-Path "$HOME\.wezterm.lua") { Ok '~\.wezterm.lua' } else { Bad 'Thiếu ~\.wezterm.lua' $repoFix }
foreach ($p in @(@('node', 'OpenJS.NodeJS.LTS', 'bắt buộc: hooks, khoá file, tự bật tài liệu'), @('git', 'Git.Git', 'bắt buộc'), @('glow', 'charmbracelet.glow', 'để ô 📋/📄 hiện Markdown có màu'))) {
    if (Has $p[0]) { Ok "$($p[0])" }
    elseif ($p[0] -eq 'glow') { Warn "Chưa có glow ($($p[2]))" "winget install $($p[1])" }
    else { Bad "Chưa có $($p[0]) ($($p[2]))" "winget install $($p[1])" }
}
foreach ($a in @(@('claude', '@anthropic-ai/claude-code'), @('codex', '@openai/codex'), @('gemini', '@google/gemini-cli'))) {
    if (Has $a[0]) { Ok "$($a[0]) đã cài" } else { Warn "Chưa cài $($a[0])" "npm install -g $($a[1])" }
}

Write-Host "`n[3] Báo động + trạng thái từng AI" -ForegroundColor Cyan
$cs = "$HOME\.claude\settings.json"
if (Test-Path $cs) {
    $txt = Get-Content $cs -Raw -Encoding UTF8
    foreach ($need in @(@('wez-alert.js', 'báo động / trạng thái'), @('khoa.js', 'khoá file'), @('statusline.js', 'thanh trạng thái + ⛽'))) {
        if ($txt -match [regex]::Escape($need[0])) { Ok "Claude: hook $($need[1])" } else { Bad "Claude chưa nối $($need[1]) ($($need[0]))" $repoFix }
    }
    foreach ($m in [regex]::Matches($txt, 'node \\"([^"\\]+)\\"')) {
        $path = $m.Groups[1].Value
        if (-not (Test-Path $path)) { Bad "Hook Claude trỏ tới file không có: $path" $repoFix }
    }
} else { Warn 'Chưa có ~\.claude\settings.json (Claude chưa chạy lần nào?)' 'chạy claude một lần rồi chạy lại khoi-phuc.ps1' }
$ct = "$HOME\.codex\config.toml"
if (Test-Path $ct) {
    $line = Select-String -Path $ct -Pattern '^\s*terminal_title\s*=' | Select-Object -First 1
    if ($line -and $line.Line -match 'run-state') { Ok 'Codex: tiêu đề có run-state (WezTerm đoán được đang làm / xong)' }
    else { Bad 'Codex chưa bật run-state trên tiêu đề → không có báo động cho Codex' $repoFix }
} else { Warn 'Chưa có ~\.codex\config.toml' 'chạy codex một lần rồi chạy lại khoi-phuc.ps1' }
$gs = "$HOME\.gemini\settings.json"
if ((Test-Path $gs) -and (Select-String -Path $gs -Pattern '"dynamicWindowTitle"\s*:\s*true' -Quiet)) { Ok 'Gemini: tiêu đề động (✦ ✋ ◇)' }
else { Bad 'Gemini chưa bật dynamicWindowTitle → không có báo động cho Gemini' $repoFix }
if ($env:GEMINI_API_KEY -or [Environment]::GetEnvironmentVariable('GEMINI_API_KEY', 'User')) { Ok 'Có biến môi trường GEMINI_API_KEY' }
else { Warn 'Chưa thấy GEMINI_API_KEY (bỏ qua nếu Gemini đăng nhập cách khác)' "đặt: [Environment]::SetEnvironmentVariable('GEMINI_API_KEY','<khoá>','User')" }

Write-Host "`n[4] Quy tắc chung + lệnh tắt" -ForegroundColor Cyan
$rules = "$HOME\.claude\CLAUDE.md", "$HOME\.codex\AGENTS.md", "$HOME\.gemini\GEMINI.md"
$missing = $rules | Where-Object { -not (Test-Path $_) }
if ($missing) { Bad "Thiếu file quy tắc: $($missing -join ', ')" $repoFix }
else {
    $h = $rules | ForEach-Object { (Get-FileHash $_).Hash } | Select-Object -Unique
    if (@($h).Count -eq 1) { Ok '3 file quy tắc (Claude / Codex / Gemini) giống nhau' }
    else { Warn '3 file quy tắc đang khác nhau' 'sửa ~\.claude\CLAUDE.md rồi chép đè sang 2 file kia (hoặc chạy cap-nhat.ps1 để xem file nào khác)' }
}
if ((Test-Path $PROFILE) -and (Select-String -Path $PROFILE -Pattern 'function ai\b' -Quiet)) { Ok 'Lệnh tắt PowerShell (ai, ai3, hub...)' }
else { Bad 'Profile PowerShell chưa có lệnh ai / hub...' $repoFix }
$pol = Get-ExecutionPolicy -Scope CurrentUser
if ($pol -in 'Restricted', 'AllSigned') { Warn "ExecutionPolicy = $pol → profile không chạy" 'Set-ExecutionPolicy -Scope CurrentUser RemoteSigned' } else { Ok "ExecutionPolicy = $pol" }

Write-Host "`n[5] Đang chạy" -ForegroundColor Cyan
$sock = Get-ChildItem "$HOME\.local\share\wezterm\gui-sock-*" -ErrorAction SilentlyContinue |
    Where-Object { Get-Process -Id ($_.Name -replace 'gui-sock-', '') -ErrorAction SilentlyContinue }
if ($sock) { Ok 'WezTerm đang mở (wez.ps1 điều khiển được)' } else { Warn 'WezTerm chưa mở' 'mở WezTerm rồi chạy lại để kiểm tra phần này' }
$aidir = Join-Path $env:LOCALAPPDATA 'wez-ai'
foreach ($d in 'alerts', 'state') { if (-not (Test-Path (Join-Path $aidir $d))) { Warn "Chưa có $aidir\$d" 'tự tạo khi mở lại WezTerm hoặc khi Claude chạy lần đầu' } }

Write-Host ''
if ($loi -eq 0 -and $canhBao -eq 0) { Write-Host '✅ Mọi thứ ổn.' -ForegroundColor Green }
else { Write-Host "Kết quả: $loi lỗi ❌ · $canhBao cảnh báo ⚠️" -ForegroundColor $(if ($loi) { 'Red' } else { 'Yellow' }) }
exit $loi
