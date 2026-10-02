# wez.ps1 — cho AI tổng quản điều khiển các ô WezTerm.
# Tự tìm cửa sổ WezTerm đang mở (mới nhất) rồi chuyển lệnh cho `wezterm cli`.
# Ví dụ:
#   .\wez.ps1 list                                  # xem các ô (PANEID) + trạng thái: ⏳ đang làm · 🟢 rảnh · 🔔 cần duyệt
#   .\wez.ps1 send 3 "Tìm giá Botcake mới nhất"     # gõ câu vào ô 3 và nhấn Enter (ô đang bận / chờ duyệt thì từ chối)
#   .\wez.ps1 send 3 "câu" -Ep                      # vẫn gửi dù ô đang bận (vd. trạng thái bị kẹt)
#   .\wez.ps1 cho 3 [số giây]                       # đợi ô 3 làm xong (mặc định tối đa 1800 giây) rồi in 40 dòng cuối
#   .\wez.ps1 cho 3,5,7                             # đợi nhiều ô cùng lúc (giao việc song song)
#   .\wez.ps1 giao Sino codex "Viết bài đăng FB…"    # mở Codex mới ở E:\AI\Sino (tab nền) với việc đó, in PANEID
#   .\wez.ps1 giao Sino claude "…" -Cho -Ra E:\AI\Hion\ket-qua.txt   # … rồi đợi xong và lưu kết quả
#   .\wez.ps1 review Chatbot [codex|claude]         # nhờ AI kia review chéo thay đổi chưa commit (kết quả bật lên)
#   .\wez.ps1 read 3 40                            # đọc 40 dòng cuối của ô 3
#   .\wez.ps1 nen 3                                 # đẩy ô 3 ra tab nền
#   .\wez.ps1 chinh 3                               # kéo ô 3 về cạnh ô đang gọi lệnh
#   .\wez.ps1 mo E:\AI\Chatbot\tien-do-chatbot.md   # bật tài liệu lên cho người dùng xem
#   .\wez.ps1 dienthoai bat                         # báo sang điện thoại (app ntfy) khi ô cần duyệt quá 5 phút · tat · thu
#   .\wez.ps1 cli <lệnh wezterm cli bất kỳ>
# Mã thoát của `cho`: 0 = xong · 1 = ô đang chờ bạn duyệt · 2 = hết giờ chờ · 3 = send bị từ chối vì ô bận
param([Parameter(Position = 0)][string]$Cmd = 'list', [switch]$Ep, [switch]$Cho, [string]$Ra, [switch]$Canh,
    [Parameter(ValueFromRemainingArguments)]$Rest)
if (-not $Rest) { $Rest = @() }

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

# Trạng thái một ô: Claude ghi qua hooks (wez-alert.js), Codex do ~/.wezterm.lua đoán từ tiêu đề
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

# Đợi các ô hết 'work'. Trả về: 0 = tất cả xong · 1 = có ô chờ duyệt / đã đóng · 2 = hết giờ
function Wait-Panes($ids, $max) {
    $left = [Collections.Generic.List[string]]@($ids | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    $code = 0; $sw = [Diagnostics.Stopwatch]::StartNew(); $nextCheck = 30
    while ($left.Count) {
        foreach ($id in @($left)) {
            $s = Get-PaneState $id
            if ($s -and $s.state -eq 'work') { continue }
            $left.Remove($id) | Out-Null
            if (-not $s) { Write-Host "── Ô ${id}: chưa có trạng thái (không phải ô AI?) ──" }
            else { Write-Host "── Ô ${id}: $($label[$s.state]) sau $([int]$sw.Elapsed.TotalSeconds) giây ──" }
            Read-Pane $id 40 | Out-Host
            if ($s -and $s.state -eq 'need') { $code = [Math]::Max($code, 1) }
        }
        if (-not $left.Count) { break }
        if ($sw.Elapsed.TotalSeconds -ge $max) {
            foreach ($id in $left) { Write-Host "⌛ Hết $max giây, ô $id vẫn đang làm."; Read-Pane $id 20 | Out-Host }
            return 2
        }
        if ($sw.Elapsed.TotalSeconds -ge $nextCheck) {   # thỉnh thoảng xem ô còn mở không
            $nextCheck += 30
            $alive = @((& $exe cli list --format json | Out-String | ConvertFrom-Json) | ForEach-Object { "$($_.pane_id)" })
            foreach ($id in @($left)) { if ($id -notin $alive) { Write-Host "❌ Ô $id đã đóng."; $left.Remove($id) | Out-Null; $code = [Math]::Max($code, 1) } }
        }
        Start-Sleep -Seconds 2
    }
    return $code
}

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
    # cho <id>[,<id>...] [giây]: đợi một hoặc nhiều ô làm xong (ô nào xong trước in trước)
    'cho' {
        $ids = "$($Rest[0])" -split ','; $max = if ($Rest.Count -gt 1) { [int]$Rest[1] } else { 1800 }
        exit (Wait-Panes $ids $max)
    }
    # giao <dự án> <claude|codex> "việc" [-Cho] [-Ra <file>] [-Canh]
    #   mở AI mới ở thư mục dự án (tab nền; -Canh = ô bên phải ô đang gọi) với câu giao việc làm lời nhắn đầu tiên.
    #   In PANEID của ô mới. -Cho: đợi xong rồi in kết quả. -Ra <file>: lưu 300 dòng cuối của ô vào file (kèm -Cho).
    #   Giao song song: gọi giao nhiều lần (không -Cho), rồi `cho 12,13,14`.
    'giao' {
        if ($Rest.Count -lt 3) { Write-Error 'Cách dùng: wez.ps1 giao <dự án> <claude|codex> "việc" [-Cho] [-Ra <file>] [-Canh]'; exit 1 }
        $projName = $Rest[0]; $ai = "$($Rest[1])".ToLower(); $task = ($Rest[2..($Rest.Count - 1)] -join ' ')
        $aiRoot = if ($cfg -and $cfg.aiRoot) { $cfg.aiRoot } else { 'E:\AI' }
        $proj = Get-ChildItem $aiRoot -Directory | Where-Object { $_.Name -eq $projName } | Select-Object -First 1
        if (-not $proj) { $proj = @(Get-ChildItem $aiRoot -Directory | Where-Object { $_.Name -like "$projName*" }) | Select-Object -First 1 }
        if (-not $proj) { Write-Error "Không thấy dự án '$projName' trong $aiRoot"; exit 1 }
        $start = @{ claude = 'claudeRC'; codex = 'codex' }[$ai]
        if (-not $start) { Write-Error "AI '$ai' không có (dùng claude hoặc codex)"; exit 1 }
        # Câu giao việc để trong file tạm rồi đọc lại: tránh lỗi dấu ngoặc kép / tiếng Việt khi truyền qua nhiều lớp lệnh
        $taskDir = Join-Path $env:LOCALAPPDATA 'wez-ai\giao'
        New-Item -ItemType Directory -Force -Path $taskDir | Out-Null
        $taskFile = Join-Path $taskDir ("{0}-{1}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $proj.Name)
        [IO.File]::WriteAllText($taskFile, $task, (New-Object Text.UTF8Encoding $false))
        # Codex: mỗi dự án một tài khoản (CODEX_HOME riêng) theo codex-tai-khoan.json → chạy song song không giẫm nhau
        $codexHome = ''; $tenTk = ''
        $bangTk = Join-Path $HOME '.doi-ca\cau-hinh.json'   # do `doi-ca cai` tạo (thuMuc, ten từng tài khoản + duAn)
        if ($ai -eq 'codex' -and (Test-Path $bangTk)) {
            $bang = Get-Content -Raw -Encoding UTF8 $bangTk | ConvertFrom-Json
            $so = $bang.duAn.($proj.Name)
            $tk = $bang.taiKhoan | Where-Object { $_.so -eq $so } | Select-Object -First 1
            if ($tk) { $codexHome = "`$env:CODEX_HOME='$($tk.thuMuc)'; "; $tenTk = $tk.ten; Write-Host "🔑 $tenTk (tài khoản $so) cho $($proj.Name)" }
        }
        $psCmd = "Get-ChildItem Env:CLAUDE* -ErrorAction SilentlyContinue | Remove-Item; $codexHome$start (Get-Content -Raw -Encoding UTF8 '$taskFile')"
        if ($Canh -and $env:WEZTERM_PANE) {
            $new = & $exe cli split-pane --pane-id $env:WEZTERM_PANE --right --percent 50 --cwd $proj.FullName -- powershell -NoLogo -NoExit -Command $psCmd
        } else {
            $new = & $exe cli spawn --cwd $proj.FullName -- powershell -NoLogo -NoExit -Command $psCmd
            $tieuDe = if ($tenTk) { "$tenTk · $($proj.Name)" } else { "$($proj.Name) · việc giao" }
            if ($new) { & $exe cli set-tab-title --pane-id $new.Trim() $tieuDe }
        }
        if (-not $new) { Write-Error 'Không mở được ô mới.'; exit 1 }
        $new = $new.Trim()
        if ($env:WEZTERM_PANE) { & $exe cli activate-pane --pane-id $env:WEZTERM_PANE }   # giữ màn hình ở ô đang làm
        Set-PaneState $new 'work'
        Write-Host "📨 Đã giao cho $ai ở $($proj.Name) → ô $new" -ForegroundColor Cyan
        Write-Output $new
        if ($Cho) {
            $code = Wait-Panes @($new) 1800
            if ($Ra) {
                & $exe cli get-text --pane-id $new --start-line -300 | Out-File -FilePath $Ra -Encoding utf8
                Write-Host "💾 Đã lưu kết quả vào $Ra"
            }
            exit $code
        }
    }
    # review <dự án> [codex|claude] [-Cho]: nhờ AI kia review chéo thay đổi chưa commit (mặc định Codex review việc Claude làm).
    #   Reviewer chỉ đọc, ghi kết quả vào Hion\bao-cao\review-<dự án>-<giờ>.md rồi bật lên.
    'review' {
        if ($Rest.Count -lt 1) { Write-Error 'Cách dùng: wez.ps1 review <dự án> [codex|claude] [-Cho]'; exit 1 }
        $who = if ($Rest.Count -gt 1) { "$($Rest[1])".ToLower() } else { 'codex' }
        $aiRoot = if ($cfg -and $cfg.aiRoot) { $cfg.aiRoot } else { 'E:\AI' }
        $outFile = Join-Path $aiRoot ("Hion\bao-cao\review-{0}-{1}.md" -f $Rest[0], (Get-Date -Format 'yyyyMMdd-HHmm'))
        New-Item -ItemType Directory -Force -Path (Split-Path $outFile) | Out-Null
        $task = "Bạn là agent REVIEW của dự án này: chỉ đọc, KHÔNG sửa file, KHÔNG commit. " +
            "Xem thay đổi chưa commit (git status, git diff HEAD); nếu không có thì xem commit gần nhất (git show HEAD). " +
            "Tìm lỗi thật: sai logic, hỏng chức năng đang chạy, lộ khoá bí mật/mật khẩu, trái quy ước trong AGENTS.md, việc chạm tiền/gửi tin khách mà không hỏi người dùng. " +
            "Ghi kết quả bằng tiếng Việt vào file $outFile : mỗi lỗi gồm file:dòng, mức độ (cao/vừa/thấp), vì sao sai, cách sửa; không có lỗi thì ghi 'Không thấy lỗi'. " +
            "Xong chạy: node $PSScriptRoot\mo-tai-lieu.js $outFile"
        & $PSCommandPath giao $Rest[0] $who $task -Cho:$Cho
        exit $LASTEXITCODE
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
    # dienthoai bat [kênh] [số phút] | tat | thu : báo sang điện thoại qua app ntfy khi ô cần duyệt mà bạn vắng máy
    #   bat: lưu kênh vào ~\.wez-ai.json (không đưa kênh thì tự tạo kênh bí mật ngẫu nhiên); mặc định chờ 5 phút mới báo
    'dienthoai' {
        $cfgFile = "$HOME\.wez-ai.json"
        $c = if (Test-Path $cfgFile) { Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { New-Object PSObject }
        $save = { [IO.File]::WriteAllText($cfgFile, ($c | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false)) }
        switch ("$($Rest[0])") {
            'bat' {
                $kenh = if ($Rest.Count -gt 1 -and $Rest[1] -notmatch '^\d+$') { $Rest[1] } else { 'wezai-' + ([guid]::NewGuid().ToString('N').Substring(0, 16)) }
                $phut = ($Rest | Where-Object { "$_" -match '^\d+$' } | Select-Object -First 1); if (-not $phut) { $phut = 5 }
                $c | Add-Member -NotePropertyName dienThoai -NotePropertyValue ([pscustomobject]@{ ntfy = $kenh; server = 'https://ntfy.sh'; sauPhut = [int]$phut; baoXong = $false }) -Force
                & $save
                Write-Host "📱 Đã bật. Kênh: $kenh  ·  báo khi ô cần duyệt quá $phut phút mà chưa bấm vào." -ForegroundColor Green
                Write-Host '   1. Cài app "ntfy" trên điện thoại (Android / iPhone, miễn phí).'
                Write-Host "   2. Trong app bấm + → Subscribe to topic (Theo dõi kênh) → gõ: $kenh"
                Write-Host '   3. Thử: wez.ps1 dienthoai thu'
                Write-Host '   ⚠️  Ai biết tên kênh đều đọc được tin → đừng chia sẻ tên kênh.' -ForegroundColor Yellow
            }
            'tat' {
                $c.PSObject.Properties.Remove('dienThoai'); & $save
                Write-Host '📵 Đã tắt báo sang điện thoại.'
            }
            'thu' {
                if (-not $c.dienThoai) { Write-Error 'Chưa bật. Chạy: wez.ps1 dienthoai bat'; exit 1 }
                $url = "$($c.dienThoai.server)/$($c.dienThoai.ntfy)"
                $body = [Text.Encoding]::UTF8.GetBytes('✅ Thử báo động từ WezTerm · đội AI')
                Invoke-RestMethod -Method Post -Uri $url -Body $body -Headers @{ Title = 'WezTerm AI'; Tags = 'bell' } -TimeoutSec 15 | Out-Null
                Write-Host '📨 Đã gửi tin thử. Điện thoại chưa nhận được thì xem lại tên kênh trong app ntfy.'
            }
            default {
                if ($c.dienThoai) { Write-Host "📱 Đang bật · kênh $($c.dienThoai.ntfy) · báo sau $($c.dienThoai.sauPhut) phút" }
                else { Write-Host '📵 Đang tắt. Bật: wez.ps1 dienthoai bat [kênh] [số phút]' }
            }
        }
    }
    default { Write-Error "Lệnh không rõ: $Cmd (dùng list | send | cho | giao | review | read | nen | chinh | mo | dienthoai | cli)" }
}
