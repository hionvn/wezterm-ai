# Ô tài liệu bên phải của "bàn làm việc Tổng quản" trong WezTerm (Ctrl+Shift+H / Ctrl+Shift+J).
# Hiển thị E:\AI\_Hub\can-duyet.md + sổ tiến độ của mọi dự án (E:\AI\*\tien-do-*.md),
# tự vẽ lại khi một trong các file đó thay đổi. Chỉ để đọc, không sửa gì.
# -File <đường dẫn>: chỉ hiện đúng một tài liệu (dùng khi AI tự bật tài liệu vừa làm xong).
param([string]$File)
$AIRoot = 'E:\AI'
$canDuyet = Join-Path $AIRoot '_Hub\can-duyet.md'
$tmp = Join-Path $env:TEMP 'ban-lam-viec-tong-quan.md'
$glow = Get-Command glow -ErrorAction SilentlyContinue
if (-not $glow) {
    $g = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter glow.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($g) { $glow = $g.FullName }
}
$host.UI.RawUI.WindowTitle = if ($File) { "📄 $(Split-Path $File -Leaf)" } else { '📋 Cần duyệt' }
$last = ''

function Get-Files {
    if ($File) { return @(Get-Item -LiteralPath $File -ErrorAction SilentlyContinue) }
    $f = @()
    if (Test-Path $canDuyet) { $f += Get-Item $canDuyet }
    $f += Get-ChildItem $AIRoot -Directory | ForEach-Object { Get-ChildItem $_.FullName -Filter 'tien-do-*.md' -File -ErrorAction SilentlyContinue }
    return $f
}

while ($true) {
    $files = Get-Files
    $sig = ($files | ForEach-Object { "$($_.FullName)|$($_.LastWriteTimeUtc.Ticks)" }) -join ';'
    $sig += "|w=$($host.UI.RawUI.WindowSize.Width)"
    if ($sig -ne $last) {
        $last = $sig
        $head = if ($File) { "# 📄 $(Split-Path $File -Leaf) · $(Get-Date -Format 'HH:mm dd/MM')" } else { "# 📋 Bàn duyệt · cập nhật $(Get-Date -Format 'HH:mm dd/MM')" }
        $parts = @($head)
        if (-not $File -and -not (Test-Path $canDuyet)) { $parts += "`n> Chưa có ``can-duyet.md``, Tổng quản sẽ tạo khi có việc cần duyệt.`n" }
        foreach ($f in $files) {
            $proj = Split-Path (Split-Path $f.FullName -Parent) -Leaf
            $parts += "`n---`n`n<!-- $proj -->`n"
            $parts += [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
        }
        [IO.File]::WriteAllText($tmp, ($parts -join "`n"), (New-Object Text.UTF8Encoding $false))
        Clear-Host
        $w = [Math]::Max(40, $host.UI.RawUI.WindowSize.Width - 2)
        if ($glow) { & $glow -s dark -w $w $tmp } else { Get-Content $tmp -Encoding UTF8 }
    }
    Start-Sleep -Seconds 3
}
