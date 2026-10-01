# wez.ps1 — cho AI tổng quản điều khiển các ô WezTerm.
# Tự tìm cửa sổ WezTerm đang mở (mới nhất) rồi chuyển lệnh cho `wezterm cli`.
# Ví dụ:
#   .\wez.ps1 list                                  # xem các ô (PANEID)
#   .\wez.ps1 send 3 "Tìm giá Botcake mới nhất"     # gõ câu vào ô 3 và nhấn Enter
#   .\wez.ps1 read 3 40                             # đọc 40 dòng cuối của ô 3
#   .\wez.ps1 nen 3                                 # đẩy ô 3 ra tab nền
#   .\wez.ps1 chinh 3                               # kéo ô 3 về cạnh ô đang gọi lệnh
#   .\wez.ps1 mo E:\AI\Chatbot\tien-do-chatbot.md   # bật tài liệu lên cho người dùng xem
#   .\wez.ps1 cli <lệnh wezterm cli bất kỳ>
param([Parameter(Position = 0)][string]$Cmd = 'list', [Parameter(ValueFromRemainingArguments)]$Rest)

$exe = 'C:\Program Files\WezTerm\wezterm.exe'
$sock = Get-ChildItem "$HOME\.local\share\wezterm\gui-sock-*" -ErrorAction SilentlyContinue |
    Where-Object { Get-Process -Id ($_.Name -replace 'gui-sock-', '') -ErrorAction SilentlyContinue } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $sock) { Write-Error 'Chưa mở WezTerm.'; exit 1 }
$env:WEZTERM_UNIX_SOCKET = $sock.FullName

switch ($Cmd) {
    'list' { & $exe cli list }
    'send' {
        $id = $Rest[0]; $text = ($Rest[1..($Rest.Count - 1)] -join ' ')
        & $exe cli send-text --pane-id $id -- $text   # dán nguyên câu (kể cả tiếng Việt)
        Start-Sleep -Milliseconds 300
        & $exe cli send-text --pane-id $id --no-paste "`r"   # nhấn Enter
    }
    'read' {
        $id = $Rest[0]; $n = if ($Rest.Count -gt 1) { [int]$Rest[1] } else { 40 }
        & $exe cli get-text --pane-id $id | Where-Object { $_.Trim() } | Select-Object -Last $n
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
    default { Write-Error "Lệnh không rõ: $Cmd (dùng list | send | read | nen | chinh | mo | cli)" }
}
