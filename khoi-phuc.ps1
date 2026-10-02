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

Write-Host "`n[1/8] Cài phần mềm (winget)" -ForegroundColor Cyan
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

Write-Host "`n[2/8] Cấu hình chung của máy (~\.wez-ai.json)" -ForegroundColor Cyan
$wezExe = 'C:\Program Files\WezTerm\wezterm.exe'
if (-not (Test-Path $wezExe)) { $c = Get-Command wezterm -ErrorAction SilentlyContinue; if ($c) { $wezExe = $c.Source } }
New-Item -ItemType Directory -Force -Path $AIRoot, (Join-Path $AIRoot 'Hion'), "$env:LOCALAPPDATA\wez-ai\alerts", "$env:LOCALAPPDATA\wez-ai\state" | Out-Null
[IO.File]::WriteAllText("$HOME\.wez-ai.json", ([ordered]@{ aiRoot = $AIRoot; wezterm = $wezExe } | ConvertTo-Json), $utf8)
Write-Host "  ✓ dự án ở $AIRoot · WezTerm: $wezExe" -ForegroundColor Green

Write-Host "`n[3/8] WezTerm" -ForegroundColor Cyan
Copy-Safe "$here\wezterm\.wezterm.lua" "$HOME\.wezterm.lua"

Write-Host "`n[4/8] Script điều khiển ô, báo động, khoá file, tài liệu ($hubScripts)" -ForegroundColor Cyan
Get-ChildItem "$here\scripts" -File | ForEach-Object { Copy-Safe $_.FullName (Join-Path $hubScripts $_.Name) }
# Link wezai-o: — bấm thông báo của đội AI là nhảy về đúng ô (HKCU, không cần Administrator)
$dk = Join-Path $hubScripts 'dang-ky-thong-bao.ps1'
if (Test-Path $dk) { & $dk }

Write-Host "`n[5/8] Claude: thanh trạng thái + hooks (báo động, trạng thái, khoá file)" -ForegroundColor Cyan
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

Write-Host "`n[6/8] Codex: bật run-state trên tiêu đề để WezTerm báo động được" -ForegroundColor Cyan
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

Write-Host "`n[7/8] Lệnh tắt PowerShell (ai, ai2, hion, bot...) + quy tắc chung của Claude và Codex" -ForegroundColor Cyan
Copy-Safe "$here\powershell\Microsoft.PowerShell_profile.ps1" $PROFILE
$rules = (Get-Content "$here\quy-tac\chung.md" -Raw -Encoding UTF8).Replace('E:\AI\', "$AIRoot\")
foreach ($dst in "$HOME\.claude\CLAUDE.md", "$HOME\.codex\AGENTS.md") {
    Backup $dst
    [IO.File]::WriteAllText($dst, $rules, $utf8)
    Write-Host "  ✓ $dst" -ForegroundColor Green
}

Write-Host "`n[8/8] Repo: bật kiểm tra khoá bí mật trước mỗi commit" -ForegroundColor Cyan
if ((Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path "$here\.git")) {
    git -C $here config core.hooksPath .githooks
    Write-Host '  ✓ git hook pre-commit → quet-bi-mat.ps1' -ForegroundColor Green
} else { Write-Host '  - bỏ qua (chưa có git hoặc thư mục này không phải bản clone git)' }

Write-Host "`nKiểm tra lại toàn bộ:" -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hubScripts 'kiem-tra.ps1')

Write-Host "`nXong. Việc còn lại:" -ForegroundColor Yellow
Write-Host "  1. Clone các dự án về $AIRoot (gh repo clone hionvn/ai-hub $AIRoot\Hion ...)."
Write-Host "  2. Mở WezTerm. Đăng nhập từng AI: gõ claude, codex và làm theo hướng dẫn."
