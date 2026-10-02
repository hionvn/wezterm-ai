# chay-thu.ps1 — chạy BÊN TRONG Windows Sandbox (mo-may-ao.ps1 tự gọi). Không chạy trên máy thật.
# Cài thử 2 lần liên tiếp (lần 2 kiểm tra chạy lại có an toàn không), rồi chạy kiem-tra.ps1, ghi tóm tắt.
$box = 'C:\Users\WDAGUtilityAccount\Desktop'
if ($env:USERNAME -ne 'WDAGUtilityAccount') { Write-Error 'Script này chỉ chạy trong Windows Sandbox.'; exit 1 }
$out = "$box\ket-qua"
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Start-Transcript -Path "$out\log-$stamp.txt" | Out-Null
$ketQua = New-Object System.Collections.Generic.List[string]
function Ghi($m) { $ketQua.Add($m); Write-Host $m }

# Chép repo sang chỗ ghi được (bản gắn vào là chỉ đọc)
New-Item -ItemType Directory -Force -Path 'C:\thu' | Out-Null
Copy-Item "$box\wezterm-ai-goc" 'C:\thu\wezterm-ai' -Recurse -Force
$kp = 'C:\thu\wezterm-ai\khoi-phuc.ps1'

foreach ($lan in 1, 2) {
    Write-Host "`n===== LẦN CÀI $lan =====" -ForegroundColor Magenta
    & powershell -NoProfile -ExecutionPolicy Bypass -File $kp -AIRoot 'C:\AI'
    Ghi "Lần cài ${lan}: mã thoát $LASTEXITCODE (0 = chạy hết, không bị dừng giữa chừng)"
}

# Các file đáng lẽ phải có sau khi cài
$can = "$HOME\.wez-ai.json", "$HOME\.wezterm.lua", "$HOME\.claude\settings.json", "$HOME\.claude\statusline.js",
    "$HOME\.claude\CLAUDE.md", "$HOME\.codex\AGENTS.md", "$HOME\.codex\config.toml", $PROFILE,
    'C:\AI\Hion\cai-dat\wez.ps1', 'C:\AI\Hion\cai-dat\khoa.js', 'C:\AI\Hion\cai-dat\kiem-tra.ps1', 'C:\AI\Hion\cai-dat\wez-alert.js',
    'C:\AI\Hion\AGENTS.md', 'C:\AI\Hion\doi-agent.md', 'C:\AI\Hion\can-duyet.md', 'C:\AI\Hion\quyet-dinh.md', 'C:\AI\Hion\kho-kien-thuc.md', 'C:\AI\Hion\cai-dat\mau\du-an\AGENTS.md'
foreach ($f in $can) { Ghi ("{0}  {1}" -f $(if (Test-Path $f) { '✅' } else { '❌ THIẾU' }), $f) }

# Nội dung phải đúng theo máy (ổ C:\AI chứ không phải E:\AI)
$cfg = Get-Content "$HOME\.wez-ai.json" -Raw | ConvertFrom-Json
Ghi "aiRoot trong ~\.wez-ai.json = $($cfg.aiRoot)  $(if ($cfg.aiRoot -eq 'C:\AI') { '✅' } else { '❌' })"
$hooks = Get-Content "$HOME\.claude\settings.json" -Raw
Ghi "Hooks Claude trỏ C:/AI/Hion/cai-dat: $(if ($hooks -match 'C:/AI/Hion/cai-dat' -and $hooks -notmatch 'E:/AI') { '✅' } else { '❌' })"
$rules = Get-Content "$HOME\.claude\CLAUDE.md" -Raw
Ghi "Quy tắc đổi E:\AI → C:\AI: $(if ($rules -notmatch 'E:\\AI\\' -and $rules -match 'C:\\AI\\') { '✅' } else { '❌' })"
Ghi "Codex có run-state: $(if (Select-String "$HOME\.codex\config.toml" -Pattern 'run-state' -Quiet) { '✅' } else { '❌' })"
$bak = @(Get-ChildItem $HOME, "$HOME\.claude" -Filter '*.bak-*' -Force -ErrorAction SilentlyContinue).Count
Ghi "Lần 2 có sao lưu file cũ (*.bak-*): $bak file $(if ($bak -gt 0) { '✅' } else { '❌' })"
$e = $null; [void][Management.Automation.Language.Parser]::ParseFile($PROFILE, [ref]$null, [ref]$e)
Ghi "Profile PowerShell không lỗi cú pháp: $(if (-not $e) { '✅' } else { '❌' })"

Stop-Transcript | Out-Null
[IO.File]::WriteAllLines("$out\tom-tat.txt", [string[]](@("Thử cài trên máy sạch — $stamp", '(Máy ảo không có winget nên WezTerm/Node/Git báo thiếu là bình thường.)', '') + $ketQua), (New-Object Text.UTF8Encoding $true))
Write-Host "`nXong. Tóm tắt ở thu-cai\ket-qua\tom-tat.txt trên máy thật. Đóng máy ảo là mất hết, không ảnh hưởng máy thật." -ForegroundColor Green
