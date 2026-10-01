# quet-bi-mat.ps1 — quét khoá bí mật (API key, token, mật khẩu) trong repo trước khi commit / push.
#   powershell -ExecutionPolicy Bypass -File .\quet-bi-mat.ps1           # quét mọi file git đang theo dõi + file mới
#   powershell -ExecutionPolicy Bypass -File .\quet-bi-mat.ps1 -Staged   # chỉ quét file sắp commit (git hook pre-commit dùng)
# Tìm thấy thì in tên file + dòng (đã che bớt khoá) và trả mã thoát 1. Không in khoá đầy đủ ra màn hình.
param([switch]$Staged)
$here = $PSScriptRoot
$self = 'quet-bi-mat.ps1'

$mau = [ordered]@{
    'Khoá Anthropic'         = 'sk-ant-[A-Za-z0-9_\-]{20,}'
    'Khoá OpenAI'            = 'sk-(proj-|svcacct-)?[A-Za-z0-9_\-]{20,}'
    'Khoá Google / Gemini'   = 'AIza[0-9A-Za-z_\-]{35}'
    'Token GitHub'           = '(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})'
    'Token Slack'            = 'xox[abprs]-[A-Za-z0-9\-]{10,}'
    'Khoá AWS'               = 'AKIA[0-9A-Z]{16}'
    'Khoá riêng (private)'   = '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    'Token Facebook'         = 'EAA[A-Za-z0-9]{60,}'
    'Gán khoá / mật khẩu'    = '(?i)(api[_-]?key|secret|token|password|passwd|mat[_-]?khau)["'']?\s*[:=]\s*["''][^"''\s<>]{12,}["'']'
}

$files = if ($Staged) { git -C $here diff --cached --name-only --diff-filter=ACM }
         else { @(git -C $here ls-files) + @(git -C $here ls-files --others --exclude-standard) }
$thay = 0
foreach ($rel in $files | Where-Object { $_ -and $_ -ne $self } | Sort-Object -Unique) {
    $path = Join-Path $here $rel
    if (-not (Test-Path $path -PathType Leaf)) { continue }
    if ((Get-Item $path).Length -gt 2MB) { continue }
    $n = 0
    foreach ($line in [IO.File]::ReadAllLines($path)) {
        $n++
        foreach ($k in $mau.Keys) {
            $m = [regex]::Match($line, $mau[$k])
            if ($m.Success) {
                $thay++
                $che = $m.Value.Substring(0, [Math]::Min(6, $m.Value.Length)) + '…(đã che)'
                Write-Host "  ⚠️  ${rel}:$n  $k  →  $che" -ForegroundColor Red
            }
        }
    }
}
if ($thay) {
    Write-Host "`n❌ Thấy $thay chỗ nghi là khoá bí mật. Xoá khỏi file (để trong biến môi trường) rồi chạy lại." -ForegroundColor Red
    Write-Host '   Chắc chắn không phải khoá thật mà vẫn muốn commit: git commit --no-verify' -ForegroundColor DarkYellow
    exit 1
}
Write-Host '✅ Không thấy khoá bí mật.' -ForegroundColor Green
exit 0
