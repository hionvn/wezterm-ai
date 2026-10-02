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
#   .\wez.ps1 doi Chatbot                           # mở đội của dự án theo Hion\doi\Chatbot.json (Manager cạnh ô đang gọi + worker ở tab riêng);
#                                                   #   ô nào đã mở thì giữ, chỉ mở ô còn thiếu; tự ghi số ô mới vào sổ đội · `doi Chatbot tat` = tắt cả đội
#   .\wez.ps1 doi Chatbot xep                      # xếp lại bố cục chuẩn khi bị lệch (giữ nguyên phiên các ô)
#   Mọi lệnh nhận số ô cũng nhận TÊN VAI: send Chatbot.Engineer "việc" · cho Chatbot.Design,Chatbot.Marketing · read Chatbot.Manager
#   (tra sổ đội %LOCALAPPDATA%\wez-ai\doi\<dự án>.json; số ô cũ chết thì tự tìm lại theo tên ô → không phải nhớ số ô)
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
$doiDir = Join-Path $env:LOCALAPPDATA 'wez-ai\doi'   # sổ đội lúc chạy: số ô của Manager + từng worker
$utf8 = New-Object Text.UTF8Encoding $false

# PowerShell 5.1: ConvertFrom-Json trả cả mảng thành 1 phần tử → foreach để trải ra từng ô
function Get-Panes { $r = (& $exe cli --no-auto-start list --format json) -join "`n" | ConvertFrom-Json; foreach ($p in $r) { $p } }
# Đọc sổ đội; ô nào đã chết thì tìm lại theo tên ô (dự án + vai trong tiêu đề, vd sau Ctrl+Shift+O mở lại bố cục) rồi ghi lại sổ
function Sync-Doi($proj) {
    $f = Join-Path $doiDir "$proj.json"
    if (-not (Test-Path $f)) { return $null }
    $d = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
    $panes = @(Get-Panes)
    $doi = $false
    foreach ($m in @($d.manager) + @($d.worker)) {
        if (-not $m -or -not $m.vai) { continue }
        if ($m.o -and ($panes | Where-Object { "$($_.pane_id)" -eq "$($m.o)" })) { continue }
        $ten = if ($m.ten) { $m.ten } else { $m.vai }   # tiêu đề ô mang tên hiển thị (có dấu)
        $hit = $panes | Where-Object { $_.title -match [regex]::Escape($proj) -and $_.title -match "(^|[^\p{L}])$([regex]::Escape($ten))([^\p{L}]|$)" -and $_.title -notmatch 'ten-o' } | Select-Object -First 1
        $moi = if ($hit) { "$($hit.pane_id)" } else { '' }
        if ("$($m.o)" -ne $moi) { $m.o = $moi; $doi = $true }
    }
    if ($doi) { [IO.File]::WriteAllText($f, ($d | ConvertTo-Json -Depth 5), $utf8) }
    return $d
}
# "24" → 24 · "Chatbot.Engineer" / "chatbot/manager" → số ô theo sổ đội
function Resolve-Id($s) {
    $s = "$s"
    if ($s -match '^\d+$') { return $s }
    if ($s -notmatch '^([^./]+)[./](.+)$') { Write-Error "Không hiểu ô '$s' (dùng số ô hoặc DựÁn.Vai, vd Chatbot.Engineer)"; exit 1 }
    $proj = $Matches[1]; $vai = $Matches[2]
    $d = Sync-Doi $proj
    if (-not $d) { Write-Error "Chưa có sổ đội $proj — mở đội: wez.ps1 doi $proj"; exit 1 }
    $m = @($d.manager) + @($d.worker) | Where-Object { $_ -and ($_.vai -eq $vai -or $_.ten -eq $vai) } | Select-Object -First 1
    if (-not $m) { Write-Error "Đội $proj không có vai '$vai'"; exit 1 }
    if (-not $m.o) { Write-Error "$proj.$vai đang tắt — mở lại: wez.ps1 doi $proj"; exit 1 }
    return "$($m.o)"
}

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
function Read-Pane($id, $n) { & $exe cli --no-auto-start get-text --pane-id $id | Where-Object { $_.Trim() } | Select-Object -Last $n }

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
            $alive = @((& $exe cli --no-auto-start list --format json | Out-String | ConvertFrom-Json) | ForEach-Object { "$($_.pane_id)" })
            foreach ($id in @($left)) { if ($id -notin $alive) { Write-Host "❌ Ô $id đã đóng."; $left.Remove($id) | Out-Null; $code = [Math]::Max($code, 1) } }
        }
        Start-Sleep -Seconds 2
    }
    return $code
}

switch ($Cmd) {
    'list' {
        $panes = & $exe cli --no-auto-start list --format json | Out-String | ConvertFrom-Json
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
        $id = Resolve-Id $Rest[0]; $text = ($Rest[1..($Rest.Count - 1)] -join ' ')
        $s = Get-PaneState $id
        if (-not $Ep -and $s -and $s.state -in 'work', 'need') {
            Write-Host "Ô ${id}: $($label[$s.state]) → chưa gửi (tránh gõ chen vào giữa chừng)." -ForegroundColor Yellow
            Write-Host "Đợi xong: wez.ps1 cho $id  ·  Vẫn gửi: thêm -Ep" -ForegroundColor Yellow
            exit 3
        }
        # PowerShell 5.1 làm vỡ tham số có dấu ngoặc kép khi gọi chương trình ngoài → thêm \ trước mỗi "
        & $exe cli --no-auto-start send-text --pane-id $id -- ($text -replace '"', '\"')   # dán nguyên câu (kể cả tiếng Việt)
        Start-Sleep -Milliseconds 300
        & $exe cli --no-auto-start send-text --pane-id $id --no-paste "`r"   # nhấn Enter
        Set-PaneState $id 'work'   # để `cho` biết là vừa giao việc
    }
    # cho <id>[,<id>...] [giây]: đợi một hoặc nhiều ô làm xong (ô nào xong trước in trước)
    'cho' {
        $ids = @("$($Rest[0])" -split ',' | ForEach-Object { Resolve-Id $_ }); $max = if ($Rest.Count -gt 1) { [int]$Rest[1] } else { 1800 }
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
        $bangTk = Join-Path $HOME '.codex-tai-khoan.json'   # bảng tài khoản: thuMuc, ten, gmail từng tài khoản + duAn → số tài khoản
        if ($ai -eq 'codex' -and (Test-Path $bangTk)) {
            $bang = Get-Content -Raw -Encoding UTF8 $bangTk | ConvertFrom-Json
            $so = $bang.duAn.($proj.Name)
            $tk = $bang.taiKhoan | Where-Object { $_.so -eq $so } | Select-Object -First 1
            if ($tk) { $codexHome = "`$env:CODEX_HOME='$($tk.thuMuc)'; "; $tenTk = $tk.ten; Write-Host "🔑 $tenTk (tài khoản $so) cho $($proj.Name)" }
        }
        $psCmd = "Get-ChildItem Env:CLAUDE* -ErrorAction SilentlyContinue | Remove-Item; $codexHome$start (Get-Content -Raw -Encoding UTF8 '$taskFile')"
        if ($Canh -and $env:WEZTERM_PANE) {
            $new = & $exe cli --no-auto-start split-pane --pane-id $env:WEZTERM_PANE --right --percent 50 --cwd $proj.FullName -- powershell -NoLogo -NoExit -Command $psCmd
        } else {
            $new = & $exe cli --no-auto-start spawn --cwd $proj.FullName -- powershell -NoLogo -NoExit -Command $psCmd
            $tieuDe = if ($tenTk) { "$tenTk · $($proj.Name)" } else { "$($proj.Name) · việc giao" }
            if ($new) { & $exe cli --no-auto-start set-tab-title --pane-id $new.Trim() $tieuDe }
        }
        if (-not $new) { Write-Error 'Không mở được ô mới.'; exit 1 }
        $new = $new.Trim()
        if ($env:WEZTERM_PANE) { & $exe cli --no-auto-start activate-pane --pane-id $env:WEZTERM_PANE }   # giữ màn hình ở ô đang làm
        Set-PaneState $new 'work'
        Write-Host "📨 Đã giao cho $ai ở $($proj.Name) → ô $new" -ForegroundColor Cyan
        Write-Output $new
        if ($Cho) {
            $code = Wait-Panes @($new) 1800
            if ($Ra) {
                & $exe cli --no-auto-start get-text --pane-id $new --start-line -300 | Out-File -FilePath $Ra -Encoding utf8
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
        $id = Resolve-Id $Rest[0]; $n = if ($Rest.Count -gt 1) { [int]$Rest[1] } else { 40 }
        Read-Pane $id $n
    }
    # doi <dự án> [tat]: mở / tắt đội agent theo Hion\doi\<dự án>.json — Manager cạnh ô đang gọi, worker đứng cạnh nhau ở tab riêng.
    #   Ô nào của đội đang mở thì giữ nguyên, chỉ mở ô còn thiếu; số ô mới tự ghi vào sổ đội (thanh tên + statusline đọc sổ này).
    'doi' {
        $proj = "$($Rest[0])"
        $defF = Join-Path (Split-Path $PSScriptRoot) "doi\$proj.json"
        if (-not (Test-Path $defF)) { Write-Error "Chưa có định nghĩa đội: $defF"; exit 1 }
        $def = Get-Content $defF -Raw -Encoding UTF8 | ConvertFrom-Json
        $aiRoot = if ($cfg -and $cfg.aiRoot) { $cfg.aiRoot } else { 'E:\AI' }
        $projDir = Join-Path $aiRoot $def.du_an
        New-Item -ItemType Directory -Force $doiDir | Out-Null
        $soF = Join-Path $doiDir "$($def.du_an).json"
        $cu = Sync-Doi $def.du_an
        if ("$($Rest[1])" -eq 'tat') {
            if ($cu) { foreach ($m in @($cu.manager) + @($cu.worker)) { if ($m -and $m.o) { & $exe cli --no-auto-start kill-pane --pane-id $m.o } } }
            Write-Host "🛑 Đã tắt đội $($def.du_an)"; break
        }
        $oCu = @{}
        if ($cu) { foreach ($m in @($cu.manager) + @($cu.worker)) { if ($m -and $m.vai -and $m.o) { $oCu[$m.vai] = "$($m.o)" } } }
        $launchDir = Join-Path $doiDir $def.du_an
        New-Item -ItemType Directory -Force $launchDir | Out-Null
        $bom = New-Object Text.UTF8Encoding $true
        $ws = @($def.worker)
        $tenWorker = ($ws | ForEach-Object { "$($def.du_an).$($_.vai)" }) -join ', '
        # Lời nhắn đầu tiên cho từng vai — gọi nhau bằng TÊN (DựÁn.Vai), không dùng số ô
        # tên hiển thị (có dấu, vd "Số liệu") khác tên gọi lệnh (không dấu, vd Sino.SoLieu) khi định nghĩa có trường "ten"
        function TenVai($m) { if ($m.ten) { $m.ten } else { $m.vai } }
        function Loi($m, $laManager) {
            $quyen = if ($m.quyen) { " QUYỀN CỦA BẠN: $($m.quyen)" } else { '' }
            if ($laManager) {
                return "Bạn là $($m.icon) $(TenVai $m) dự án $($def.du_an): $($m.viec). Đội của bạn: $tenWorker (cùng tab '$($def.logo) $($def.du_an) · đội' với bạn: bạn nửa trái, worker nửa phải; vai + quyền từng worker: E:\AI\Hion\doi\$($def.du_an).json).$quyen " +
                    "Giao việc bằng TÊN, không dùng số ô: E:\AI\Hion\cai-dat\wez.ps1 send $($def.du_an).<Vai> `"việc`" rồi wez.ps1 cho $($def.du_an).<Vai> (đợi xong, đọc kết quả). " +
                    "Việc chạm khách/tiền/giá/đăng bài → duyet.js them, không tự làm. Bây giờ: đọc AGENTS.md + tien-do của dự án + dòng [$($def.du_an)] trong E:\AI\Hion\quyet-dinh.md, báo ngắn việc đang làm / kẹt / đề xuất giao gì cho từng worker. CHƯA giao việc khi người dùng chưa đồng ý."
            }
            return "Bạn là worker $($def.logo) $($def.du_an) · $($m.icon) $(TenVai $m). Phụ trách: $($m.viec). Manager của bạn: $($def.du_an).Manager.$quyen " +
                "Luật chung: chỉ nhận việc từ Manager $($def.du_an) hoặc Tổng quản Hion; làm đúng phần mình; khoá file trước khi sửa; không tự commit nếu không được dặn; không gửi tin/đăng bài/chạm tiền khi chưa được duyệt. " +
                "Bây giờ: đọc AGENTS.md + tien-do của dự án, trả lời 3 dòng (bạn là ai, quyền của bạn tóm 1 dòng, sẵn sàng) rồi CHỜ việc. Chưa sửa file nào."
        }
        # Mở 1 ô; Claude đặt tên bằng -n (hiện trên statusline + tiêu đề ô), Codex đổi tên bằng /rename sau khi mở
        function Mo($m, $laManager, $splitFrom, $huong, $pct) {
            $ten = "$($def.logo) $($def.du_an) · $($m.icon) $(TenVai $m)"
            $loiF = Join-Path $launchDir "$($m.vai).txt"
            [IO.File]::WriteAllText($loiF, (Loi $m $laManager), $bom)
            $l = "Get-ChildItem Env:CLAUDE* -ErrorAction SilentlyContinue | Remove-Item`r`n"
            if ($m.ai -eq 'codex') {
                $bang = Join-Path $HOME '.codex-tai-khoan.json'
                if (Test-Path $bang) {
                    $b = Get-Content -Raw -Encoding UTF8 $bang | ConvertFrom-Json
                    $tk = $b.taiKhoan | Where-Object { $_.so -eq $b.duAn.($def.du_an) } | Select-Object -First 1
                    if ($tk) { $l += "`$env:CODEX_HOME = '$($tk.thuMuc)'`r`n" }
                }
                $l += "codex.cmd --no-daemon`r`n"
            } else {
                # "chan" = khoá cứng công cụ (vd Kiểm soát/Security chỉ đọc: không Edit/Write được dù lỡ được bảo)
                $chan = if ($m.chan) { " '--disallowedTools=$(($m.chan -split ' ') -join ',')'" } else { '' }   # dạng = để cờ không nuốt lời nhắn phía sau
                $l += "claude --remote-control '$($def.du_an)-$($m.vai)' -n '$ten'$chan (Get-Content -Raw -Encoding UTF8 '$loiF')`r`n"
            }
            $lf = Join-Path $launchDir "mo-$($m.vai).ps1"
            [IO.File]::WriteAllText($lf, $l, $bom)
            $a = @('powershell', '-NoLogo', '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', $lf)
            $id = if ($splitFrom) { & $exe cli --no-auto-start split-pane --pane-id $splitFrom $huong --percent $pct --cwd $projDir -- @a }
                  else { & $exe cli --no-auto-start spawn --cwd $projDir -- @a }
            $id = "$id".Trim()
            if ($m.ai -eq 'codex' -and $id) {
                # đợi Codex sẵn sàng (bỏ qua hộp hỏi cập nhật bằng Esc) → /rename → gửi lời nhắn
                for ($i = 0; $i -lt 40; $i++) {
                    Start-Sleep -Milliseconds 750
                    $t = (& $exe cli --no-auto-start get-text --pane-id $id) -join "`n"
                    if ($t -match 'Update available|Skip until next') { & $exe cli --no-auto-start send-text --no-paste --pane-id $id ([string][char]27); continue }
                    if ($t -match 'Ask Codex|for shortcuts') { break }
                }
                & $exe cli --no-auto-start send-text --no-paste --pane-id $id '/rename'; Start-Sleep -Milliseconds 600
                & $exe cli --no-auto-start send-text --no-paste --pane-id $id "`r"; Start-Sleep -Milliseconds 900
                & $exe cli --no-auto-start send-text --pane-id $id $ten; Start-Sleep -Milliseconds 400
                & $exe cli --no-auto-start send-text --no-paste --pane-id $id "`r"; Start-Sleep -Milliseconds 900
                & $exe cli --no-auto-start send-text --pane-id $id (Get-Content -Raw -Encoding UTF8 $loiF); Start-Sleep -Milliseconds 400
                & $exe cli --no-auto-start send-text --no-paste --pane-id $id "`r"
            }
            return $id
        }
        $so = [ordered]@{ du_an = $def.du_an; logo = $def.logo; cap_nhat = (Get-Date -Format 'yyyy-MM-dd HH:mm'); manager = $null; worker = @() }
        # Bố cục (người dùng chốt 03/10): cả đội chung 1 tab — Manager nửa trái, worker nửa phải chia lưới 2 cột
        #   (4 worker = 2×2: trên-trái, trên-phải, dưới-trái, dưới-phải). Ô đã mở ở chỗ khác thì CHUYỂN vào đúng chỗ (giữ nguyên phiên),
        #   ô thiếu thì mở mới. Cả đội đã đứng chung 1 tab rồi thì để nguyên, không xếp lại.
        $panes = @(Get-Panes)
        $tabOf = @{}; foreach ($p in $panes) { $tabOf["$($p.pane_id)"] = "$($p.tab_id)" }
        $mg = $def.manager
        $idsCu = @($oCu[$mg.vai]) + @($ws | ForEach-Object { $oCu[$_.vai] })
        $chungTab = ($idsCu | Where-Object { -not $_ }).Count -eq 0 -and (@($idsCu | ForEach-Object { $tabOf[$_] } | Select-Object -Unique)).Count -eq 1
        if ("$($Rest[1])" -eq 'xep') { $chungTab = $false }   # doi <dự án> xep: ép xếp lại bố cục chuẩn (vd sau khi bị lệch)
        $moMoi = 0
        # Đặt 1 vai vào chỗ: tách từ ô $from theo $huong; ô cũ còn sống thì chuyển nó vào (--move-pane-id), không thì mở mới
        function Dat($m, $laManager, $from, $huong, $pct) {
            $cuId = $oCu[$m.vai]
            if ($cuId) {
                & $exe cli --no-auto-start split-pane --pane-id $from $huong --percent $pct --move-pane-id $cuId | Out-Null
                return $cuId
            }
            $script:moMoi++
            return (Mo $m $laManager $from $huong $pct)
        }
        $ids = @{}
        if ($chungTab) {
            $mo = $oCu[$mg.vai]
            foreach ($w in $ws) { $ids[$w.vai] = $oCu[$w.vai] }
        } else {
            # 1) Manager mở tab mới (ô cũ thì đẩy sang tab mới)
            if ($oCu[$mg.vai]) { $mo = $oCu[$mg.vai]; & $exe cli --no-auto-start move-pane-to-new-tab --pane-id $mo | Out-Null }
            else { $mo = Mo $mg $true $null $null 0; $moMoi++ }
            # 2) Đầu 2 cột worker: cột 1 chiếm nửa phải, cột 2 tách đôi cột 1
            $c1 = @(); $c2 = @()
            for ($i = 0; $i -lt $ws.Count; $i++) { if ($i % 2 -eq 0) { $c1 += $ws[$i] } else { $c2 += $ws[$i] } }
            $h1 = Dat $c1[0] $false $mo '--right' 50; $ids[$c1[0].vai] = $h1
            if ($c2.Count) { $h2 = Dat $c2[0] $false $h1 '--right' 50; $ids[$c2[0].vai] = $h2 }
            # 3) Xếp chồng trong từng cột, cao bằng nhau
            foreach ($cot in @(@{ ds = $c1; dau = $h1 }, @{ ds = $c2; dau = $h2 })) {
                $cuoi = $cot.dau; $n = $cot.ds.Count
                for ($k = 1; $k -lt $n; $k++) {
                    $pct = [int](100 * ($n - $k) / ($n - $k + 1))   # 2 ô: 50 · 3 ô: 67, 50
                    $cuoi = Dat $cot.ds[$k] $false $cuoi '--bottom' $pct
                    $ids[$cot.ds[$k].vai] = $cuoi
                }
            }
        }
        $so.manager = [ordered]@{ o = $mo; vai = $mg.vai; ten = (TenVai $mg); icon = $mg.icon; ai = $mg.ai; mau = $mg.mau }
        foreach ($w in $ws) { $so.worker += [ordered]@{ o = $ids[$w.vai]; vai = $w.vai; ten = (TenVai $w); icon = $w.icon; ai = $w.ai; mau = $w.mau; viec = $w.viec } }
        [IO.File]::WriteAllText($soF, ($so | ConvertTo-Json -Depth 5), $utf8)
        & $exe cli --no-auto-start set-tab-title --pane-id $mo "$($def.logo) $($def.du_an) · đội"
        & $exe cli --no-auto-start activate-pane --pane-id $mo
        $ghiChu = if ($chungTab) { 'cả đội đã chung 1 tab, giữ nguyên' } else { "xếp lại: Manager trái, worker lưới bên phải · mở mới $moMoi ô" }
        Write-Host ("👥 Đội $($def.du_an): Manager ô $mo · " + (($so.worker | ForEach-Object { "$($_.vai) ô $($_.o)" }) -join ' · ') + " ($ghiChu)") -ForegroundColor Cyan
        Write-Host "   Gọi bằng tên: wez.ps1 send $($def.du_an).$($ws[0].vai) `"việc`""
    }
    'cli' { & $exe cli --no-auto-start @Rest }
    # nen <id>: đẩy ô ra một tab nền riêng (agent chạy ngầm, không chiếm chỗ tab chính)
    'nen' { & $exe cli --no-auto-start move-pane-to-new-tab --pane-id (Resolve-Id $Rest[0]) }
    # chinh <id> [id-đích]: kéo ô về tab chính, đặt bên phải ô đích (mặc định: ô đang gọi lệnh)
    'chinh' {
        $dest = if ($Rest.Count -gt 1) { Resolve-Id $Rest[1] } else { $env:WEZTERM_PANE }
        & $exe cli --no-auto-start split-pane --pane-id $dest --right --percent 50 --move-pane-id (Resolve-Id $Rest[0])
        & $exe cli --no-auto-start activate-pane --pane-id $dest
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
