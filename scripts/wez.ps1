# wez.ps1 — cho AI tổng quản điều khiển các ô WezTerm.
# Tự tìm cửa sổ WezTerm đang mở (mới nhất) rồi chuyển lệnh cho `wezterm cli`.
# Ví dụ:
#   .\wez.ps1 list                                  # xem các ô (PANEID) + trạng thái: ⏳ đang làm · 🟢 rảnh · 🔔 cần duyệt
#   .\wez.ps1 send 3 "Tìm giá Botcake mới nhất"     # gõ câu vào ô 3 và nhấn Enter (ô đang bận / chờ duyệt thì từ chối)
#   .\wez.ps1 send 3 "câu" -Ep                      # vẫn gửi dù ô đang bận (vd. trạng thái bị kẹt)
#   .\wez.ps1 cho 3 [số giây]                       # đợi ô 3 làm xong (mặc định tối đa 1800 giây) rồi in 40 dòng cuối
#   .\wez.ps1 read 3 40                             # đọc 40 dòng cuối của ô 3
#   .\wez.ps1 nen 3                                 # đẩy ô 3 ra tab nền
#   .\wez.ps1 chinh 3                               # kéo ô 3 về cạnh ô đang gọi lệnh
#   .\wez.ps1 mo E:\AI\Chatbot\tien-do-chatbot.md   # bật tài liệu lên cho người dùng xem
#   .\wez.ps1 cli <lệnh wezterm cli bất kỳ>
# Mã thoát của `cho`: 0 = xong · 1 = ô đang chờ bạn duyệt · 2 = hết giờ chờ · 3 = send bị từ chối vì ô bận
param([Parameter(Position = 0)][string]$Cmd = 'list', [switch]$Ep, [Parameter(ValueFromRemainingArguments)]$Rest)

# Cấu hình chung của máy (khoi-phuc.ps1 tạo): ~\.wez-ai.json = { aiRoot, wezterm }
$cfg = $null
if (Test-Path "$HOME\.wez-ai.json") { $cfg = Get-Content "$HOME\.wez-ai.json" -Raw -Encoding UTF8 | ConvertFrom-Json }
$exe = if ($cfg -and $cfg.wezterm) { $cfg.wezterm } else { 'C:\Program Files\WezTerm\wezterm.exe' }
if (-not (Test-Path $exe)) { $c = Get-Command wezterm -ErrorAction SilentlyContinue; if ($c) { $exe = $c.Source } }
$stateDir = Join-Path $env:LOCALAPPDATA 'wez-ai\state'

$sock = Get-ChildItem "$HOME\.local\share\wezterm\gui-sock-*" -ErrorAction SilentlyContinue |
    Where-Object { Get-Process -Id ($_.Name -replace 'gui-sock-', '') -ErrorAction SilentlyContinue } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $sock) { Write-Error 'Chưa mở WezTerm.'; exit 1 }
$env:WEZTERM_UNIX_SOCKET = $sock.FullName

# Trạng thái một ô: Claude ghi qua hooks (wez-alert.js), Codex/Gemini do ~/.wezterm.lua đoán từ tiêu đề
function Get-PaneState($id) {
    $f = Join-Path $stateDir "$id.json"
    if (-not (Test-Path $f)) { return $null }
    try { return Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}
function Set-PaneState($id, $state) {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    $old = Get-PaneState $id
    $o = [ordered]@{ state = $state; ai = $(if ($old) { $old.ai } else { '' }); session = $(if ($old) { $old.session } else { '' })
        t = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); by = 'send' }
    [IO.File]::WriteAllText((Join-Path $stateDir "$id.json"), ($o | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
}
$label = @{ work = '⏳ đang làm'; idle = '🟢 rảnh'; need = '🔔 cần duyệt' }
function Read-Pane($id, $n) { & $exe cli get-text --pane-id $id | Where-Object { $_.Trim() } | Select-Object -Last $n }

switch ($Cmd) {
    'list' {
        $panes = & $exe cli list --format json | Out-String | ConvertFrom-Json
        $panes | ForEach-Object {
            $s = Get-PaneState $_.pane_id
            $dir = if ($_.cwd) { ([uri]$_.cwd).LocalPath.TrimEnd('\', '/') } else { '?' }
            [pscustomobject]@{
                PANEID = $_.pane_id; TAB = $_.tab_id
                'TRẠNG THÁI' = $(if ($s -and $label[$s.state]) { $label[$s.state] } else { '·' })
                'DỰ ÁN' = Split-Path $dir -Leaf
                'TIÊU ĐỀ' = $_.title
                'ĐANG CHỌN' = $(if ($_.is_active) { '●' } else { '' })
            }
        } | Format-Table -AutoSize | Out-String -Width 200
    }
    'send' {
        $id = $Rest[0]; $text = ($Rest[1..($Rest.Count - 1)] -join ' ')
        $s = Get-PaneState $id
        if (-not $Ep -and $s -and $s.state -in 'work', 'need') {
            Write-Host "Ô ${id}: $($label[$s.state]) → chưa gửi (tránh gõ chen vào giữa chừng)." -ForegroundColor Yellow
            Write-Host "Đợi xong: wez.ps1 cho $id  ·  Vẫn gửi: thêm -Ep" -ForegroundColor Yellow
            exit 3
        }
        # PowerShell 5.1 làm vỡ tham số có dấu ngoặc kép khi gọi chương trình ngoài → thêm \ trước mỗi "
        & $exe cli send-text --pane-id $id -- ($text -replace '"', '\"')   # dán nguyên câu (kể cả tiếng Việt)
        Start-Sleep -Milliseconds 300
        & $exe cli send-text --pane-id $id --no-paste "`r"   # nhấn Enter
        Set-PaneState $id 'work'   # để `cho` biết là vừa giao việc
    }
    'cho' {
        $id = $Rest[0]; $max = if ($Rest.Count -gt 1) { [int]$Rest[1] } else { 1800 }
        $alive = { (& $exe cli list --format json | Out-String | ConvertFrom-Json) | Where-Object { "$($_.pane_id)" -eq "$id" } }
        $sw = [Diagnostics.Stopwatch]::StartNew(); $nextCheck = 30
        while ($true) {
            $s = Get-PaneState $id
            if (-not $s) { Write-Host "Ô $id chưa có trạng thái (không phải ô AI, hoặc AI chưa chạy lần nào)."; Read-Pane $id 40; exit 0 }
            if ($s.state -ne 'work') { break }
            if ($sw.Elapsed.TotalSeconds -ge $max) { Write-Host "⌛ Hết $max giây, ô $id vẫn đang làm."; Read-Pane $id 20; exit 2 }
            if ($sw.Elapsed.TotalSeconds -ge $nextCheck) {   # thỉnh thoảng xem ô còn mở không
                $nextCheck += 30
                if (-not (& $alive)) { Write-Error "Ô $id đã đóng."; exit 1 }
            }
            Start-Sleep -Seconds 2
        }
        Write-Host "── Ô ${id}: $($label[$s.state]) sau $([int]$sw.Elapsed.TotalSeconds) giây ──"
        Read-Pane $id 40
        if ($s.state -eq 'need') { exit 1 } else { exit 0 }
    }
    'read' {
        $id = $Rest[0]; $n = if ($Rest.Count -gt 1) { [int]$Rest[1] } else { 40 }
        Read-Pane $id $n
    }
    'cli' { & $exe cli @Rest }
    # nen <id>: đẩy ô ra một tab nền riêng (agent chạy ngầm, không chiếm chỗ tab chính)
    'nen' { & $exe cli move-pane-to-new-tab --pane-id $Rest[0] }
    # chinh <id> [id-đích]: kéo ô về tab chính, đặt bên phải ô đích (mặc định: ô đang gọi lệnh)
    'chinh' {
        $dest = if ($Rest.Count -gt 1) { $Rest[1] } else { $env:WEZTERM_PANE }
        & $exe cli split-pane --pane-id $dest --right --percent 50 --move-pane-id $Rest[0]
        & $exe cli activate-pane --pane-id $dest
    }
    # mo <file>: bật tài liệu lên ô "📄" bên phải tab người dùng đang xem
    'mo' { node "$PSScriptRoot\mo-tai-lieu.js" $Rest[0] }
    default { Write-Error "Lệnh không rõ: $Cmd (dùng list | send | cho | read | nen | chinh | mo | cli)" }
}
