# Chia đều các ô trong tab đang xem của WezTerm (phím Ctrl+Shift+E gọi script này).
# Cột: chia đều chiều ngang các ô ở hàng trên cùng. Trong mỗi cột: chia đều chiều cao các ô xếp chồng.
# Lệnh `wezterm cli adjust-pane-size` dời đường ranh gần nhất của ô ĐANG CHỌN, nên mỗi lần chỉnh phải chọn ô trước,
# rồi thử 1 ô xem đúng đường ranh cần dời chưa; sai thì trả lại và dùng ô bên kia đường ranh.
param([int]$Pane = [int]$env:WEZTERM_PANE)

$cfg = Join-Path $HOME '.wez-ai.json'
$WezExe = 'C:\Program Files\WezTerm\wezterm.exe'
if (Test-Path $cfg) { try { $j = Get-Content $cfg -Raw | ConvertFrom-Json; if ($j.wezExe) { $WezExe = $j.wezExe } } catch {} }
if (-not (Test-Path $WezExe)) { $WezExe = (Get-Command wezterm -ErrorAction SilentlyContinue).Source }

function All { $r = & $WezExe cli list --format json | ConvertFrom-Json; $r }   # gán rồi trả: PS 5.1 mới tách mảng ra từng ô
$all = All
$me = $all | Where-Object { $_.pane_id -eq $Pane } | Select-Object -First 1
if (-not $me) { Write-Host "Khong thay o $Pane"; exit 1 }
$tabId = $me.tab_id
function TabPanes { All | Where-Object { $_.tab_id -eq $tabId } }
function Get-P($id) { TabPanes | Where-Object { $_.pane_id -eq $id } | Select-Object -First 1 }
function Adjust($id, $dir, $n) {
    if ($n -le 0) { return }
    & $WezExe cli activate-pane --pane-id $id | Out-Null
    & $WezExe cli adjust-pane-size --pane-id $id --amount $n $dir | Out-Null
}

# Dời đường ranh nằm ngay trước ô $after (cạnh trái nếu $axis='x', cạnh trên nếu 'y') tới vị trí $want.
function Move-Edge($before, $after, $axis, $want) {
    $pos = { param($id) $p = Get-P $id; if ($axis -eq 'x') { $p.left_col } else { $p.top_row } }
    $cur = & $pos $after
    $delta = $want - $cur
    if ($delta -eq 0) { return }
    $dir = if ($axis -eq 'x') { if ($delta -gt 0) { 'Right' } else { 'Left' } } else { if ($delta -gt 0) { 'Down' } else { 'Up' } }
    $back = @{ Right = 'Left'; Left = 'Right'; Down = 'Up'; Up = 'Down' }[$dir]
    $n = [math]::Abs($delta)
    foreach ($id in @($before, $after)) {
        Adjust $id $dir 1
        $now = & $pos $after
        if ($now -ne $cur) { Adjust $id $dir ($n - 1); return }   # đúng đường ranh: dời nốt
        Adjust $id $back 1                                       # sai đường ranh: trả lại
    }
}

# 1) Cột: các ô ở hàng trên cùng, xếp trái → phải
$panes = TabPanes
$top = ($panes | Measure-Object top_row -Minimum).Minimum
$cols = @($panes | Where-Object { $_.top_row -eq $top } | Sort-Object left_col)
if ($cols.Count -gt 1) {
    $first = $cols[0].left_col
    $last = $cols[-1]
    $usable = ($last.left_col + $last.size.cols - $first) - ($cols.Count - 1)   # trừ đường ranh 1 ký tự
    $x = $first
    for ($i = 0; $i -lt $cols.Count - 1; $i++) {
        $w = [math]::Floor($usable / $cols.Count) + $(if ($i -lt ($usable % $cols.Count)) { 1 } else { 0 })
        $x += $w + 1
        Move-Edge $cols[$i].pane_id $cols[$i + 1].pane_id 'x' $x
    }
}

# 2) Trong mỗi cột: các ô xếp chồng cùng cạnh trái, trên → dưới
$panes = TabPanes
foreach ($left in ($panes | Select-Object -ExpandProperty left_col -Unique)) {
    $stack = @($panes | Where-Object { $_.left_col -eq $left } | Sort-Object top_row)
    if ($stack.Count -lt 2) { continue }
    $firstY = $stack[0].top_row
    $lastP = $stack[-1]
    $usable = ($lastP.top_row + $lastP.size.rows - $firstY) - ($stack.Count - 1)
    $y = $firstY
    for ($i = 0; $i -lt $stack.Count - 1; $i++) {
        $h = [math]::Floor($usable / $stack.Count) + $(if ($i -lt ($usable % $stack.Count)) { 1 } else { 0 })
        $y += $h + 1
        Move-Edge $stack[$i].pane_id $stack[$i + 1].pane_id 'y' $y
    }
}

& $WezExe cli activate-pane --pane-id $Pane | Out-Null
