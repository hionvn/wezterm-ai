# khoi-phuc.ps1 — cài lại toàn bộ "đội AI trên WezTerm" lên một máy Windows mới.
# Chạy trong PowerShell, đứng ở thư mục repo này:
#   powershell -ExecutionPolicy Bypass -File .\khoi-phuc.ps1            # cài cấu hình
#   powershell -ExecutionPolicy Bypass -File .\khoi-phuc.ps1 -CaiAI     # cài thêm Claude Code, Codex, Gemini CLI
# File nào đã có trên máy đều được sao lưu thành <tên>.bak-<ngày giờ> trước khi ghi đè.
# Không chứa API key / mật khẩu: sau khi chạy, tự đăng nhập từng AI (claude, codex, gemini).
param([switch]$CaiAI)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$hubScripts = 'E:\AI\_Hub\cai-dat'   # các script được gọi theo đường dẫn này (xem .wezterm.lua, settings)

function Copy-Safe($src, $dst) {
    $dir = Split-Path $dst -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if (Test-Path $dst) { Copy-Item $dst "$dst.bak-$stamp" }
    Copy-Item $src $dst -Force
    Write-Host "  ✓ $dst" -ForegroundColor Green
}

Write-Host "`n[1/5] Cài phần mềm (winget)" -ForegroundColor Cyan
foreach ($id in 'wez.wezterm', 'charmbracelet.glow', 'OpenJS.NodeJS.LTS', 'Git.Git') {
    winget install --id $id -e --silent --accept-source-agreements --accept-package-agreements | Out-Null
    Write-Host "  ✓ $id"
}
if ($CaiAI) {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    npm install -g @anthropic-ai/claude-code @openai/codex @google/gemini-cli
}

Write-Host "`n[2/5] WezTerm" -ForegroundColor Cyan
Copy-Safe "$here\wezterm\.wezterm.lua" "$HOME\.wezterm.lua"

Write-Host "`n[3/5] Script điều khiển ô, báo động, tài liệu ($hubScripts)" -ForegroundColor Cyan
Get-ChildItem "$here\scripts" -File | ForEach-Object { Copy-Safe $_.FullName (Join-Path $hubScripts $_.Name) }

Write-Host "`n[4/5] Claude: thanh trạng thái + hooks báo động" -ForegroundColor Cyan
Copy-Safe "$here\claude\statusline.js" "$HOME\.claude\statusline.js"
$setPath = "$HOME\.claude\settings.json"
$add = Get-Content "$here\claude\settings.phan-them.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$add.statusLine.command = "node `"$($HOME -replace '\\','/')/.claude/statusline.js`""   # đúng thư mục người dùng máy mới
if (Test-Path $setPath) {
    Copy-Item $setPath "$setPath.bak-$stamp"
    $cur = Get-Content $setPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else { $cur = New-Object PSObject }
$cur | Add-Member -NotePropertyName statusLine -NotePropertyValue $add.statusLine -Force
$cur | Add-Member -NotePropertyName hooks -NotePropertyValue $add.hooks -Force
[IO.File]::WriteAllText($setPath, ($cur | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding $false))
Write-Host "  ✓ $setPath (giữ nguyên các cài đặt khác)" -ForegroundColor Green

Write-Host "`n[5/5] Lệnh tắt PowerShell (ai, hub, bot...) + quy tắc chung của 3 AI" -ForegroundColor Cyan
Copy-Safe "$here\powershell\Microsoft.PowerShell_profile.ps1" $PROFILE
Copy-Safe "$here\quy-tac\claude-CLAUDE.md" "$HOME\.claude\CLAUDE.md"
Copy-Safe "$here\quy-tac\codex-AGENTS.md" "$HOME\.codex\AGENTS.md"
Copy-Safe "$here\quy-tac\gemini-GEMINI.md" "$HOME\.gemini\GEMINI.md"

Write-Host "`nXong. Việc còn lại:" -ForegroundColor Yellow
Write-Host "  1. Clone các dự án về E:\AI (gh repo clone hionvn/ai-hub E:\AI\_Hub ...)."
Write-Host "  2. Mở WezTerm. Đăng nhập từng AI: gõ claude, codex, gemini và làm theo hướng dẫn."
Write-Host "  3. Gemini cần API key: đặt trong biến môi trường, không ghi vào file trong dự án."
