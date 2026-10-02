# kiem-cau-hinh.ps1 — chạy thử mọi file cấu hình / script của đội AI trước khi lưu (03/10/2026).
# Lỗi ở đâu báo đúng file. Mã thoát: 0 = ổn · 1 = có lỗi (cap-nhat.ps1 dừng, không chép sang repo).
# Sinh ra sau 2 lần trong 03/10 sửa hỏng ~\.wezterm.lua (nhân đôi nửa file, lỗi goto) mà chỉ phát hiện khi WezTerm báo lỗi.
#   powershell -ExecutionPolicy Bypass -File E:\AI\Hion\cai-dat\kiem-cau-hinh.ps1
$loi = 0
function Ok($m) { Write-Host "  ✅ $m" }
function Hong($m) { Write-Host "  ❌ $m" -ForegroundColor Red; $script:loi++ }

$cfg = $null; if (Test-Path "$HOME\.wez-ai.json") { $cfg = Get-Content "$HOME\.wez-ai.json" -Raw -Encoding UTF8 | ConvertFrom-Json }
$exe = if ($cfg -and $cfg.wezterm) { $cfg.wezterm } else { 'C:\Program Files\WezTerm\wezterm.exe' }
$caiDat = $PSScriptRoot

# 1) WezTerm Lua: cho WezTerm nạp thử cấu hình (không ảnh hưởng cửa sổ đang chạy)
$lua = "$HOME\.wezterm.lua"
$out = & $exe --config-file $lua show-keys 2>&1 | Out-String
if ($out -match 'Configuration Error|syntax error|runtime error') { Hong ("~\.wezterm.lua: " + (($out -split "`n" | Select-String 'error' | Select-Object -First 1).Line.Trim())) } else { Ok '~\.wezterm.lua nạp được' }
$soReturn = @(Select-String -Path $lua -Pattern '^return config').Count
if ($soReturn -ne 1) { Hong "~\.wezterm.lua có $soReturn dòng 'return config' (phải đúng 1 — dấu hiệu file bị nhân đôi)" }
# các file con (nếu đã tách module) cũng nằm trong lần nạp thử ở trên

# 2) JavaScript: node --check
$js = @(Get-ChildItem $caiDat -Filter *.js -File | Where-Object { $_.Name -notmatch '\.bak' }) + @(Get-Item "$HOME\.claude\statusline.js" -ErrorAction SilentlyContinue)
$jsLoi = 0
foreach ($f in $js) { $r = node --check $f.FullName 2>&1; if ($LASTEXITCODE) { Hong "$($f.Name): $(($r | Select-Object -First 3) -join ' ')"; $jsLoi++ } }
if (-not $jsLoi) { Ok "$($js.Count) file JS đúng cú pháp" }

# 3) PowerShell: phân tích cú pháp (không chạy)
$ps = @(Get-ChildItem $caiDat -Filter *.ps1 -File | Where-Object { $_.Name -notmatch '\.bak' }) + @(Get-Item $PROFILE -ErrorAction SilentlyContinue)
$psLoi = 0
foreach ($f in $ps) {
    $e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$e)
    if ($e.Count) { Hong "$($f.Name) dòng $($e[0].Extent.StartLineNumber): $($e[0].Message)"; $psLoi++ }
    # PowerShell 5.1 đọc file không BOM theo mã ANSI → chữ Việt hỏng; file có tiếng Việt phải có BOM
    $b = [IO.File]::ReadAllBytes($f.FullName)
    $coBom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
    if (-not $coBom -and ([Text.Encoding]::UTF8.GetString($b) -match '[À-ỹ]')) { Hong "$($f.Name): có tiếng Việt mà thiếu BOM (PowerShell 5.1 sẽ đọc sai chữ)"; $psLoi++ }
}
if (-not $psLoi) { Ok "$($ps.Count) file PowerShell đúng cú pháp" }

# 4) JSON định nghĩa đội
$jLoi = 0
foreach ($f in Get-ChildItem (Join-Path (Split-Path $caiDat) 'doi') -Filter *.json -File -ErrorAction SilentlyContinue) {
    try { $null = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Hong "doi\$($f.Name): JSON hỏng"; $jLoi++ }
}
if (-not $jLoi) { Ok 'định nghĩa đội (Hion\doi\*.json) đọc được' }

if ($loi) { Write-Host "❌ Có $loi lỗi — sửa xong rồi mới lưu / commit." -ForegroundColor Red; exit 1 }
Write-Host '✅ Cấu hình ổn.' -ForegroundColor Green
exit 0
