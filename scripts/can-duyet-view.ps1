# Ô tài liệu bên phải của "bàn làm việc Tổng quản" trong WezTerm (Ctrl+Shift+H / Ctrl+Shift+J).
# Hiển thị E:\AI\Hion\can-duyet.md + sổ tiến độ của mọi dự án (E:\AI\*\tien-do-*.md),
# tự vẽ lại khi một trong các file đó thay đổi.
# Mỗi việc "Đang chờ" có nút [✅ Duyệt] [✏️ Trả lời] [❌ Bỏ]: bấm chuột → ~/.wezterm.lua gọi duyet.js
# (nút là link wezai-duyet:<việc>/<mã>). Không có WezTerm thì dùng: node duyet.js ok|sua|bo <số>.
# -File <đường dẫn>: chỉ hiện đúng một tài liệu (dùng khi AI tự bật tài liệu vừa làm xong).
param([string]$File)
$AIRoot = 'E:\AI'   # mặc định; máy khác ổ đĩa thì lấy từ ~\.wez-ai.json (khoi-phuc.ps1 tạo)
if (Test-Path "$HOME\.wez-ai.json") { $c = Get-Content "$HOME\.wez-ai.json" -Raw -Encoding UTF8 | ConvertFrom-Json; if ($c.aiRoot) { $AIRoot = $c.aiRoot } }
$canDuyet = Join-Path $AIRoot 'Hion\can-duyet.md'
$tmp = Join-Path $env:TEMP 'ban-lam-viec-tong-quan.md'
$glow = Get-Command glow -ErrorAction SilentlyContinue
if (-not $glow) {
    $g = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter glow.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($g) { $glow = $g.FullName }
}
$host.UI.RawUI.WindowTitle = if ($File) { "📄 $(Split-Path $File -Leaf)" } else { '📋 Cần duyệt' }
$last = ''
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # đọc đúng tiếng Việt từ node + in đúng emoji trên nút
$duyetJs = Join-Path $PSScriptRoot 'duyet.js'
$E = [char]27
function Link($uri, $text) { "$E]8;;$uri$E\$text$E]8;;$E\" }

# Vẽ phần "Đang chờ" kèm nút bấm (glow không vẽ được link bấm)
function Show-Pending {
    $json = (& node $duyetJs json 2>$null) -join ''
    # PowerShell 5.1: ConvertFrom-Json trả cả mảng thành 1 phần tử → trải ra từng việc
    $items = @(); if ($json) { $items = @($json | ConvertFrom-Json | ForEach-Object { $_ }) }
    Write-Host ''
    if (-not $items.Count) { Write-Host "  ✅ Không có việc nào chờ bạn duyệt." -ForegroundColor Green; return }
    Write-Host "  🔔 $($items.Count) việc chờ bạn duyệt" -ForegroundColor Yellow
    foreach ($it in $items) {
        Write-Host ''
        $tag = if ($it.proj) { "[$($it.proj)] " } else { '' }
        Write-Host "  $($it.n). " -NoNewline -ForegroundColor White
        Write-Host $tag -NoNewline -ForegroundColor Cyan
        Write-Host $it.text
        $ok = Link "wezai-duyet:ok/$($it.id)" "$E[30;42m ✅ Duyệt $E[0m"
        $sua = Link "wezai-duyet:sua/$($it.id)" "$E[30;43m ✏️ Trả lời $E[0m"
        $bo = Link "wezai-duyet:bo/$($it.id)" "$E[37;41m ❌ Bỏ $E[0m"
        [Console]::Out.Write("     $ok  $sua  $bo`n")
    }
    Write-Host ''
    Write-Host "  Bấm chuột vào nút · điện thoại: nhắn Claude Hion `"duyệt 2`" / `"bỏ 1 vì …`"" -ForegroundColor DarkGray
}

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
            $txt = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
            if (-not $File -and $f.FullName -eq (Resolve-Path $canDuyet).Path) {
                # "Đang chờ" đã vẽ kèm nút ở trên → bỏ khỏi bản glow; "Đã xử lý" chỉ giữ 5 dòng mới nhất
                $txt = [regex]::Replace($txt, '(?ms)^## Đang chờ.*?(?=^## |\z)', '')
                $txt = [regex]::Replace($txt, '(?m)(^## Đã xử lý[ \t]*\r?\n(?:\r?\n)?)((?:- .*\r?\n?){5})(?:- .*\r?\n?)+', ('$1$2' + "_(cũ hơn: xem quyet-dinh.md)_`n"))
            }
            $parts += $txt
        }
        [IO.File]::WriteAllText($tmp, ($parts -join "`n"), (New-Object Text.UTF8Encoding $false))
        Clear-Host
        $w = [Math]::Max(40, $host.UI.RawUI.WindowSize.Width - 2)
        if (-not $File) { Show-Pending }
        if ($glow) { & $glow -s dark -w $w $tmp } else { Get-Content $tmp -Encoding UTF8 }
    }
    Start-Sleep -Seconds 3
}
