# khoi-phuc.ps1 — cài lại toàn bộ "đội AI trên WezTerm" lên một máy Windows mới.
# Chạy trong PowerShell, đứng ở thư mục repo này:
#   powershell -ExecutionPolicy Bypass -File .\khoi-phuc.ps1                     # cài cấu hình (dự án ở E:\AI)
#   powershell -ExecutionPolicy Bypass -File .\khoi-phuc.ps1 -CaiAI              # cài thêm Claude Code, Codex
#   powershell -ExecutionPolicy Bypass -File .\khoi-phuc.ps1 -AIRoot D:\AI       # máy không có ổ E: → để dự án ở chỗ khác
# File nào đã có trên máy đều được sao lưu thành <tên>.bak-<ngày giờ> trước khi ghi đè.
# Không chứa API key / mật khẩu: sau khi chạy, tự đăng nhập từng AI (claude, codex).
#   -BoQuaPhanMem : không chạy winget (đã tự cài WezTerm, Node, Git, glow; hoặc chạy thử trong máy ảo)
param([switch]$CaiAI, [string]$AIRoot, [switch]$BoQuaPhanMem)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$utf8 = New-Object Text.UTF8Encoding $false

# Thư mục chứa dự án: tham số -AIRoot > lần cài trước (~\.wez-ai.json) > E:\AI (hỏi lại nếu máy không có ổ E:)
if (-not $AIRoot -and (Test-Path "$HOME\.wez-ai.json")) { $AIRoot = (Get-Content "$HOME\.wez-ai.json" -Raw -Encoding UTF8 | ConvertFrom-Json).aiRoot }
if (-not $AIRoot) { $AIRoot = 'E:\AI' }
if (-not (Test-Path (Split-Path $AIRoot -Qualifier))) {
    $AIRoot = Read-Host "Máy không có ổ $(Split-Path $AIRoot -Qualifier). Để các dự án AI ở thư mục nào? (vd. D:\AI)"
}
$AIRoot = $AIRoot.TrimEnd('\')
$hubScripts = Join-Path $AIRoot 'Hion\cai-dat'
$hubFwd = $hubScripts -replace '\\', '/'

function Copy-Safe($src, $dst) {
    $dir = Split-Path $dst -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if (Test-Path $dst) { Copy-Item $dst "$dst.bak-$stamp" }
    Copy-Item $src $dst -Force
    Write-Host "  ✓ $dst" -ForegroundColor Green
}
function Backup($f) { if (Test-Path $f) { Copy-Item $f "$f.bak-$stamp" } }

Write-Host "`n[1/9] Cài phần mềm (winget)" -ForegroundColor Cyan
if ($BoQuaPhanMem) { Write-Host '  - bỏ qua (-BoQuaPhanMem)' }
elseif (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host '  ⚠️  Máy không có winget → tự cài tay: WezTerm, Node.js LTS, Git, glow (rồi chạy lại script này)' -ForegroundColor Yellow
} else {
    foreach ($id in 'wez.wezterm', 'charmbracelet.glow', 'OpenJS.NodeJS.LTS', 'Git.Git') {
        winget install --id $id -e --silent --accept-source-agreements --accept-package-agreements | Out-Null
        # 0 = cài xong; -1978335189 = đã có sẵn, không cần cập nhật
        if ($LASTEXITCODE -in 0, -1978335189) { Write-Host "  ✓ $id" } else { Write-Host "  ⚠️  ${id}: winget báo lỗi $LASTEXITCODE (cài tay nếu kiem-tra.ps1 báo thiếu)" -ForegroundColor Yellow }
    }
}
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
if ($CaiAI) {
    if (Get-Command npm -ErrorAction SilentlyContinue) { npm install -g @anthropic-ai/claude-code @openai/codex }
    else { Write-Host '  ⚠️  Chưa có npm (Node.js) → chưa cài được Claude Code, Codex' -ForegroundColor Yellow }
}

Write-Host "`n[2/9] Cấu hình chung của máy (~\.wez-ai.json)" -ForegroundColor Cyan
$wezExe = 'C:\Program Files\WezTerm\wezterm.exe'
if (-not (Test-Path $wezExe)) { $c = Get-Command wezterm -ErrorAction SilentlyContinue; if ($c) { $wezExe = $c.Source } }
New-Item -ItemType Directory -Force -Path $AIRoot, (Join-Path $AIRoot 'Hion'), "$env:LOCALAPPDATA\wez-ai\alerts", "$env:LOCALAPPDATA\wez-ai\state" | Out-Null
[IO.File]::WriteAllText("$HOME\.wez-ai.json", ([ordered]@{ aiRoot = $AIRoot; wezterm = $wezExe } | ConvertTo-Json), $utf8)
Write-Host "  ✓ dự án ở $AIRoot · WezTerm: $wezExe" -ForegroundColor Green

Write-Host "`n[3/9] WezTerm" -ForegroundColor Cyan
Copy-Safe "$here\wezterm\.wezterm.lua" "$HOME\.wezterm.lua"

Write-Host "`n[4/9] Script điều khiển ô, báo động, khoá file, tài liệu ($hubScripts)" -ForegroundColor Cyan
Get-ChildItem "$here\scripts" -File | ForEach-Object { Copy-Safe $_.FullName (Join-Path $hubScripts $_.Name) }
# Link wezai-o: — bấm thông báo của đội AI là nhảy về đúng ô (HKCU, không cần Administrator)
$dk = Join-Path $hubScripts 'dang-ky-thong-bao.ps1'
if (Test-Path $dk) { & $dk }

Write-Host "`n[5/9] Claude: thanh trạng thái + hooks (báo động, trạng thái, khoá file)" -ForegroundColor Cyan
Copy-Safe "$here\claude\statusline.js" "$HOME\.claude\statusline.js"
$setPath = "$HOME\.claude\settings.json"
$addText = (Get-Content "$here\claude\settings.phan-them.json" -Raw -Encoding UTF8).Replace('E:/AI/Hion/cai-dat', $hubFwd)
$add = $addText | ConvertFrom-Json
$add.statusLine.command = "node `"$($HOME -replace '\\','/')/.claude/statusline.js`""   # đúng thư mục người dùng máy mới
if (Test-Path $setPath) {
    Backup $setPath
    $cur = Get-Content $setPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else { $cur = New-Object PSObject }
$cur | Add-Member -NotePropertyName statusLine -NotePropertyValue $add.statusLine -Force
$cur | Add-Member -NotePropertyName hooks -NotePropertyValue $add.hooks -Force
[IO.File]::WriteAllText($setPath, ($cur | ConvertTo-Json -Depth 20), $utf8)
Write-Host "  ✓ $setPath (giữ nguyên các cài đặt khác)" -ForegroundColor Green

Write-Host "`n[6/9] Codex: bật run-state trên tiêu đề để WezTerm báo động được" -ForegroundColor Cyan
$ct = "$HOME\.codex\config.toml"
$want = (Get-Content "$here\codex\config.phan-them.toml" -Encoding UTF8 | Where-Object { $_ -match '^\s*terminal_title\s*=' } | Select-Object -First 1)
New-Item -ItemType Directory -Force -Path "$HOME\.codex" | Out-Null
$lines = if (Test-Path $ct) { @(Get-Content $ct -Encoding UTF8) } else { @() }
$i = [Array]::FindIndex([string[]]$lines, [Predicate[string]] { param($l) $l -match '^\s*terminal_title\s*=' })
if ($i -ge 0 -and $lines[$i] -match 'run-state') { Write-Host '  ✓ Codex đã có run-state trên tiêu đề' -ForegroundColor Green }
else {
    Backup $ct
    if ($i -ge 0) { $lines[$i] = $want }
    else {
        $t = [Array]::IndexOf([string[]]$lines, '[tui]')
        if ($t -ge 0) { $lines = $lines[0..$t] + $want + $(if ($t + 1 -lt $lines.Count) { $lines[($t + 1)..($lines.Count - 1)] }) }
        else { $lines += @('', '[tui]', $want) }
    }
    [IO.File]::WriteAllLines($ct, [string[]]$lines, $utf8)
    Write-Host "  ✓ $ct" -ForegroundColor Green
}

Write-Host "`n[7/9] Lệnh tắt PowerShell (ai, ai2, hion, bot...) + quy tắc chung của Claude và Codex" -ForegroundColor Cyan
Copy-Safe "$here\powershell\Microsoft.PowerShell_profile.ps1" $PROFILE
# Quy tắc chung nằm giữa 2 dòng đánh dấu "wezterm-ai: bat-dau / het" → cài lại chỉ thay đoạn đó, ghi chú riêng của người dùng giữ nguyên
$rules = (Get-Content "$here\quy-tac\chung.md" -Raw -Encoding UTF8).Replace('E:\AI\', "$AIRoot\").Trim()
foreach ($dst in "$HOME\.claude\CLAUDE.md", "$HOME\.codex\AGENTS.md") {
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    if (-not (Test-Path $dst)) { [IO.File]::WriteAllText($dst, $rules + "`r`n", $utf8); Write-Host "  ✓ $dst (mới)" -ForegroundColor Green; continue }
    $cur = [IO.File]::ReadAllText($dst, [Text.Encoding]::UTF8)
    $m = [regex]::Match($cur, '(?s)<!-- wezterm-ai: bat-dau.*?<!-- wezterm-ai: het -->')
    if ($m.Success) { Backup $dst; $cur = $cur.Remove($m.Index, $m.Length).Insert($m.Index, $rules); Write-Host "  ✓ $dst (cập nhật đoạn quy tắc chung)" -ForegroundColor Green }
    elseif ($cur -match '## Làm việc trong WezTerm \(đội AI\)') { Write-Host "  - $dst đã có quy tắc đội AI riêng → giữ nguyên"; continue }
    else { Backup $dst; $cur = $cur.TrimEnd() + "`r`n`r`n" + $rules + "`r`n"; Write-Host "  ✓ $dst (thêm quy tắc chung vào cuối, nội dung cũ giữ nguyên)" -ForegroundColor Green }
    [IO.File]::WriteAllText($dst, $cur, $utf8)
}

Write-Host "`n[8/9] Tổng quản + bộ mẫu cho dự án ($AIRoot\Hion)" -ForegroundColor Cyan
# Bộ mẫu chép vào cai-dat\mau (newproj và Tổng quản dùng); file của Tổng quản chỉ tạo khi CHƯA có — không bao giờ ghi đè
$mauDst = Join-Path $hubScripts 'mau'
New-Item -ItemType Directory -Force -Path $mauDst | Out-Null
Copy-Item "$here\mau\*" $mauDst -Recurse -Force
Write-Host "  ✓ $mauDst" -ForegroundColor Green
foreach ($f in Get-ChildItem "$here\mau\Hion" -File) {
    $dst = Join-Path $AIRoot "Hion\$($f.Name)"
    if (Test-Path $dst) { Write-Host "  - giữ nguyên $dst (đã có)"; continue }
    [IO.File]::WriteAllText($dst, (Get-Content $f.FullName -Raw -Encoding UTF8).Replace('{{AIROOT}}', $AIRoot), $utf8)
    Write-Host "  ✓ $dst (mới)" -ForegroundColor Green
}

Write-Host "`n[9/9] Repo: bật kiểm tra khoá bí mật trước mỗi commit" -ForegroundColor Cyan
if ((Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path "$here\.git")) {
    git -C $here config core.hooksPath .githooks
    Write-Host '  ✓ git hook pre-commit → quet-bi-mat.ps1' -ForegroundColor Green
} else { Write-Host '  - bỏ qua (chưa có git hoặc thư mục này không phải bản clone git)' }

Write-Host "`nKiểm tra lại toàn bộ:" -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hubScripts 'kiem-tra.ps1')

Write-Host "`nXong. Việc còn lại:" -ForegroundColor Yellow
Write-Host "  1. Mở WezTerm. Đăng nhập từng AI: gõ claude, codex và làm theo hướng dẫn."
Write-Host "  2. Đặt các thư mục dự án vào $AIRoot (tạo mới: gõ newproj <tên>)."
Write-Host "  3. Bấm Ctrl+Shift+H (tab Tổng quản) rồi nói: khởi động đội — Tổng quản hỏi từng dự án và tự đặt vai cho cả đội."
Write-Host "  4. Có nhiều tài khoản ChatGPT dùng Codex: tạo ~\.codex-tai-khoan.json (xem README), rồi vào từng thư mục dự án gõ codex login. Xem bảng: codextk."
