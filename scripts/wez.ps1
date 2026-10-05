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
# 04/10: worker "ai": "deepseek" — dòng PowerShell đặt biến cho Claude Code chạy bằng DeepSeek (giống hàm deepseek trong profile).
# Key lấy từ biến người dùng lúc ô chạy, không nằm trong file. Giữ giống DEEPSEEK_ENV trong ~\.wezterm\06-bo-cuc.lua.
$DEEPSEEK_ENV = "`$env:ANTHROPIC_AUTH_TOKEN = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', 'User'); `$env:ANTHROPIC_BASE_URL = 'https://api.deepseek.com/anthropic'; Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue; `$env:ANTHROPIC_MODEL = 'deepseek-flash[1m]'; `$env:ANTHROPIC_DEFAULT_OPUS_MODEL = 'deepseek-flash[1m]'; `$env:ANTHROPIC_DEFAULT_SONNET_MODEL = 'deepseek-flash[1m]'; `$env:ANTHROPIC_DEFAULT_HAIKU_MODEL = 'deepseek-flash'; `$env:CLAUDE_CODE_SUBAGENT_MODEL = 'deepseek-flash'; `$env:CLAUDE_CODE_AUTO_COMPACT_WINDOW = '786432'"

# PowerShell 5.1: ConvertFrom-Json trả cả mảng thành 1 phần tử → foreach để trải ra từng ô
# 05/10 (WezTerm treo / quay vòng): `wezterm cli list` bắt WezTerm hỏi Windows thư mục của MỌI ô ngay trên luồng giao diện
# (30 ô ≈ 1–3 giây, có lúc 35 giây khi máy bận). 4 Manager + Tổng quản gọi list/send/read/cho liên tục → giao diện đứng.
# Giờ mặc định đọc wez-ai\o-list.json (Lua ghi sẵn, ≤ 10 giây/lần; mới < 15 giây mới dùng). -Thuc = hỏi WezTerm thật (mở/xếp đội).
$oListF = Join-Path $env:LOCALAPPDATA 'wez-ai\o-list.json'
function Get-Panes([switch]$Thuc) {
    if (-not $Thuc) {
        try {
            $fi = Get-Item -LiteralPath $oListF -ErrorAction Stop
            if (((Get-Date) - $fi.LastWriteTime).TotalSeconds -lt 60) {
                $r = [IO.File]::ReadAllText($oListF, [Text.Encoding]::UTF8) | ConvertFrom-Json
                if (@($r).Count) { foreach ($p in $r) { $p }; return }
            }
        } catch {}
    }
    $r = (& $exe cli --no-auto-start list --format json) -join "`n" | ConvertFrom-Json; foreach ($p in $r) { $p }
}
# Ô người dùng đang nhìn trên màn hình (khác $env:WEZTERM_PANE = ô AI gọi lệnh, có thể ở tab nền).
# Mở/xếp ô xong thì trả màn hình về ô này — trước đây trả về ô AI gọi lệnh làm màn hình nhảy tab (03/10/2026).
function Get-Focus { try { $c = (& $exe cli --no-auto-start list-clients --format json) -join "`n" | ConvertFrom-Json; return "$(@($c)[0].focused_pane_id)" } catch { return '' } }
function Set-Focus($id) { if ("$id" -ne '') { & $exe cli --no-auto-start activate-pane --pane-id $id 2>$null | Out-Null } }
# Đọc sổ đội; ô nào đã chết thì tìm lại theo tên ô (dự án + vai trong tiêu đề, vd sau Ctrl+Shift+O mở lại bố cục) rồi ghi lại sổ
function Sync-Doi($proj) {
    $f = Join-Path $doiDir "$proj.json"
    if (-not (Test-Path $f)) { return $null }
    $d = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
    $panes = @(Get-Panes)
    # ô ghi trong sổ mà file danh sách chưa có (vừa mở < 10 giây) → hỏi WezTerm thật 1 lần, tránh tưởng ô đã chết
    $coO = @{}; foreach ($p in $panes) { $coO["$($p.pane_id)"] = $true }
    if (@(@($d.manager) + @($d.worker) | Where-Object { $_ -and "$($_.o)" -ne '' -and -not $coO["$($_.o)"] }).Count) { $panes = @(Get-Panes -Thuc) }
    $doi = $false
    $ds = @(@($d.manager) + @($d.worker) | Where-Object { $_ -and $_.vai })
    # tên vai đúng nguyên chữ: "Săn" KHÔNG khớp "Săn 2" (04/10: Aff.San và Aff.San2 cùng trỏ ô 47 vì "Săn" khớp tiêu đề "🔎 Săn 2")
    # 05/10: phân biệt hoa thường + tên dài thắng: "Bot" không lấy ô "🛠️ Áp bot" của ApBot (Sino.Bot từng chiếm ô 57 → ApBot bị mở trùng phiên)
    function KhopTen1($title, $m) { $t = if ($m.ten) { $m.ten } else { $m.vai }; "$title" -cmatch "(^|[^\p{L}])$([regex]::Escape($t))(?!\s*\p{N})([^\p{L}\p{N}]|$)" }
    function KhopTen($title, $m) {
        if (-not (KhopTen1 $title $m)) { return $false }
        $dai = $ds | Where-Object { KhopTen1 $title $_ } | Sort-Object { "$(if ($_.ten) { $_.ten } else { $_.vai })".Length } -Descending | Select-Object -First 1
        return ($dai -eq $m)
    }
    $daGiu = @{}   # ô đã thuộc một vai → không gán thêm cho vai khác
    foreach ($m in $ds) {
        # 04/10: số ô có thể đã bị dùng lại sau khởi động lại (sổ Aff ghi Manager = ô 22 trong khi ô 22 là Coolguy · Kiểm soát)
        # → chỉ tin ô cũ khi ô đó đúng là của dự án này (thư mục ô nằm trong E:\AI\<dự án>, hoặc tiêu đề có tên dự án)
        #   và tiêu đề không mang tên một vai KHÁC của đội
        $cuP = if ($m.o) { $panes | Where-Object { "$($_.pane_id)" -eq "$($m.o)" } | Select-Object -First 1 }
        if ($cuP -and -not $daGiu["$($m.o)"]) {
            $cwdP = [uri]::UnescapeDataString("$($cuP.cwd)") -replace '\\', '/'
            $vaiKhac = $ds | Where-Object { $_ -ne $m -and (KhopTen $cuP.title $_) } | Select-Object -First 1
            # 05/10: tiêu đề chỉ tính khi đúng dạng ô đội "<dự án> · <vai>" — ô Tổng quản (thư mục Hion) bị Claude tự đặt tên "Aff.Manager Ted's…" từng bị nhận là Manager Aff → báo cáo worker chạy nhầm sang Tổng quản
            if (($cwdP -match "/AI/$([regex]::Escape($proj))(/|$)" -or "$($cuP.title)" -match "$([regex]::Escape($proj))\s*·") -and (-not $vaiKhac -or (KhopTen $cuP.title $m))) {
                $daGiu["$($m.o)"] = $true; continue
            }
        }
        $hit = $panes | Where-Object { $_.title -match "$([regex]::Escape($proj))\s*·" -and (KhopTen $_.title $m) -and $_.title -notmatch 'ten-o' -and -not $daGiu["$($_.pane_id)"] } | Select-Object -First 1
        $moi = if ($hit) { "$($hit.pane_id)" } else { '' }
        if ($moi) { $daGiu[$moi] = $true }
        if ("$($m.o)" -ne $moi) { $m.o = $moi; $doi = $true }
    }
    if ($doi) { [IO.File]::WriteAllText($f, ($d | ConvertTo-Json -Depth 5), $utf8) }
    return $d
}
# Sổ việc đã giao (03/10/2026): %LOCALAPPDATA%\wez-ai\viec.json = [{ so, t, o, ai, viec, tu, xong, bo }]
#   send / giao ghi thêm 1 việc; bảng tổng quan (bang-doi.js) tự đánh dấu xong khi ô nhận việc chuyển sang rảnh.
$viecF = Join-Path $env:LOCALAPPDATA 'wez-ai\viec.json'
# PowerShell 5.1: ConvertFrom-Json trả cả mảng thành 1 phần tử, ghi lại thì bị lồng {"value":[…],"Count":n} (lỗi 03/10)
# → đọc thì trải phẳng mọi lớp, chỉ giữ object có "so"; ghi thì tự dựng chuỗi JSON từng việc
function Flat-Viec($x) {
    foreach ($e in @($x)) {
        if ($null -eq $e) { continue }
        if ($e -is [array]) { Flat-Viec $e; continue }
        if ($e.PSObject.Properties['so']) { $e; continue }
        if ($e.PSObject.Properties['value']) { Flat-Viec $e.value }
    }
}
function Read-Viec { if (Test-Path $viecF) { try { $r = Get-Content $viecF -Raw -Encoding UTF8 | ConvertFrom-Json; return @(Flat-Viec $r) } catch {} }; return @() }
function Save-Viec($vs) {
    $ds = @(Flat-Viec $vs) | Sort-Object { [int]$_.so } | Select-Object -Last 300
    $json = '[' + (($ds | ForEach-Object { $_ | ConvertTo-Json -Depth 3 -Compress }) -join ",`n") + ']'
    [IO.File]::WriteAllText($viecF, $json, (New-Object Text.UTF8Encoding $false))
}
function Add-Viec($id, $text) {
    $vs = @(Read-Viec | Where-Object { $_ -and $_.so })
    $so = if ($vs.Count) { [int](($vs | Measure-Object so -Maximum).Maximum) + 1 } else { 1 }
    # tên người nhận: theo sổ đội (vd "💬 Chatbot · ⚙️ Engineer"), không thì dự án + số ô
    $ai = "ô $id"
    foreach ($f in Get-ChildItem $doiDir -Filter *.json -ErrorAction SilentlyContinue) {
        $d = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($m in @($d.manager) + @($d.worker)) { if ($m -and "$($m.o)" -eq "$id") { $ai = "$($d.logo) $($d.du_an) · $($m.icon) $(if ($m.ten) { $m.ten } else { $m.vai })" } }
    }
    $mot = (($text -replace '\s+', ' ').Trim())
    if ($mot.Length -gt 90) { $mot = $mot.Substring(0, 89) + '…' }
    $vs += [pscustomobject]@{ so = $so; t = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); o = "$id"; ai = $ai; viec = $mot; tu = "$env:WEZTERM_PANE"; xong = $null; bo = $false }
    Save-Viec $vs
    Write-Host "📝 Việc số $so → $ai" -ForegroundColor DarkGray
}

# "24" → 24 · "Chatbot.Engineer" / "chatbot/manager" → số ô theo sổ đội
function Resolve-Id($s, [switch]$Thuc) {
    $s = "$s"
    if ($s -match '^\d+$') { return $s }
    if ($s -notmatch '^([^./]+)[./](.+)$') { Write-Error "Không hiểu ô '$s' (dùng số ô hoặc DựÁn.Vai, vd Chatbot.Engineer)"; exit 1 }
    $proj = $Matches[1]; $vai = $Matches[2]
    $d = Sync-Doi $proj
    if (-not $d) { Write-Error "Chưa có sổ đội $proj — mở đội: wez.ps1 doi $proj"; exit 1 }
    $m = @($d.manager) + @($d.worker) | Where-Object { $_ -and ($_.vai -eq $vai -or $_.ten -eq $vai) } | Select-Object -First 1
    if (-not $m) { Write-Error "Đội $proj không có vai '$vai'"; exit 1 }
    if (-not $m.o) {
        # worker đang NGỦ (tự đóng khi rảnh lâu, 03/10/2026) → giao việc thì tự đánh thức: mở lại đúng phiên cũ, đợi sẵn sàng
        if (($m.ngu -or $m.session) -and $Thuc -and $m -ne $d.manager) {
            Write-Host "💤→⏰ $proj.$($m.vai) đang ngủ, đánh thức (mở lại đúng phiên cũ)…" -ForegroundColor DarkCyan
            & $PSCommandPath doi $proj "thuc:$($m.vai)" | Out-Host
            # 05/10: ô vừa mở chưa kịp có tiêu đề → tìm lại vài lần (trước báo "không đánh thức được" rồi lần gửi sau mở trùng ô thứ 2)
            $vaiThuc = $m.vai
            for ($k = 0; $k -lt 10; $k++) {
                $d = Sync-Doi $proj
                $m = @($d.worker) | Where-Object { $_.vai -eq $vaiThuc } | Select-Object -First 1
                if ($m.o) { break }; Start-Sleep 2
            }
            if (-not $m.o) { Write-Error "Không đánh thức được $proj.$vai"; exit 1 }
            for ($i = 0; $i -lt 120; $i++) {   # đợi tối đa ~90 giây tới khi AI sẵn sàng nhận lệnh
                Start-Sleep -Milliseconds 750
                $t = (& $exe cli --no-auto-start get-text --pane-id $m.o) -join "`n"
                if ($t -match 'Update available|Skip until next') { & $exe cli --no-auto-start send-text --no-paste --pane-id $m.o ([string][char]27); continue }
                # 05/10: phiên bỏ lâu → Claude hỏi "Resume / Start a new conversation" (dấu ❯ của hộp này từng bị tưởng là sẵn sàng → lời giao việc rơi vào hộp,
                # ô kẹt — Coolguy.Bot 04/10). Chọn 1. Resume (Enter) để giữ trí nhớ phiên — đúng mục đích đánh thức.
                if ($t -match 'Start a new conversation|Resuming it will use') { & $exe cli --no-auto-start send-text --no-paste --pane-id $m.o "`r"; Start-Sleep 2; continue }
                if ($t -match 'Ask Codex|for shortcuts|❯|auto mode|bypass permissions') { break }
            }
            Start-Sleep 2
            return "$($m.o)"
        }
        $goi = if ($m.ngu) { "đang ngủ 💤 — tự thức khi giao việc bằng wez.ps1 send $proj.$vai, hoặc mở ngay: wez.ps1 doi $proj" } else { "đang tắt — mở lại: wez.ps1 doi $proj" }
        Write-Error "$proj.$vai $goi"; exit 1
    }
    return "$($m.o)"
}

# ===== Codex trước, Claude dự phòng (04/10/2026, Hion: "ưu tiên dùng Codex trước") =====
# Vai định nghĩa ai=codex: giao việc lúc tài khoản Codex của vai đó ≥ 90% (5 giờ) hoặc ≥ 95% (tuần) → vai TẠM chạy Claude
# (cùng quyền, cùng khoá); Codex hồi lại (< 80% / < 90%) → về Codex. Ghi ở wez-ai\doi\ai-tam.json { "Sino.Bot": {ai, tu, ly} }.
# Chuyển AI khác loại theo vai — KHÔNG nhảy giữa các tài khoản Codex (luật 02/10). Ngưỡng: "codexChuyenClaude" trong ~\.wez-ai.json.
$aiTamF = Join-Path $env:LOCALAPPDATA 'wez-ai\ai-tam.json'   # ngoài thư mục doi\ (script khác đọc mọi *.json ở đó như sổ đội)
function Read-AiTam { if (Test-Path $aiTamF) { try { return (Get-Content $aiTamF -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {} }; return [pscustomobject]@{} }
function Save-AiTam($o) { New-Item -ItemType Directory -Force (Split-Path $aiTamF) | Out-Null; [IO.File]::WriteAllText($aiTamF, ($o | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false)) }
function Get-CodexFuel($proj, $w) {
    $bang = Join-Path $HOME '.codex-tai-khoan.json'; $fuelF = Join-Path $env:LOCALAPPDATA 'wez-ai\fuel-codex.json'
    if (-not (Test-Path $bang) -or -not (Test-Path $fuelF)) { return $null }
    $b = Get-Content -Raw -Encoding UTF8 $bang | ConvertFrom-Json
    $so = if ($w.tk) { [int]$w.tk } else { $b.duAn.$proj }
    $tk = $b.taiKhoan | Where-Object { $_.so -eq $so } | Select-Object -First 1
    if (-not $tk) { return $null }
    $ds = Get-Content -Raw -Encoding UTF8 $fuelF | ConvertFrom-Json   # PS 5.1: mảng JSON ra 1 khối → gán biến rồi mới lọc
    $f = $ds | Where-Object { $_.ten -eq $tk.ten } | Select-Object -First 1
    if ($f) { return [pscustomobject]@{ ten = $tk.ten; five = [double]$f.five; week = [double]$f.week } }; return $null
}
function Chon-AI($s) {
    if ("$s" -notmatch '^([^./]+)[./](.+)$') { return }
    $proj = $Matches[1]; $vai = $Matches[2]
    $defF = Join-Path $PSScriptRoot "..\doi\$proj.json"; if (-not (Test-Path $defF)) { return }
    $def = Get-Content $defF -Raw -Encoding UTF8 | ConvertFrom-Json
    $w = @($def.worker) | Where-Object { $_ -and ($_.vai -eq $vai -or $_.ten -eq $vai) } | Select-Object -First 1
    if (-not $w -or $w.ai -ne 'codex' -or $w.router) { return }
    $f = Get-CodexFuel $proj $w; if (-not $f) { return }
    $ng = if ($cfg -and $cfg.codexChuyenClaude) { $cfg.codexChuyenClaude } else { [pscustomobject]@{ nam = 90; tuan = 95 } }
    $key = "$proj.$($w.vai)"; $tam = Read-AiTam; $dangTam = $tam.PSObject.Properties[$key]
    $het = $f.five -ge $ng.nam -or $f.week -ge $ng.tuan
    $hoi = $f.five -lt ($ng.nam - 10) -and $f.week -lt ($ng.tuan - 5)
    if ($het -and -not $dangTam) { $muon = 'claude'; $ly = "$($f.ten) 5 giờ $([math]::Round($f.five))% · tuần $([math]::Round($f.week))%" }
    elseif ($dangTam -and $hoi) { $muon = 'codex'; $ly = "$($f.ten) đã hồi ($([math]::Round($f.five))%)" }
    else { return }
    if ($env:WEZ_CHON_AI_THU) { Write-Host "[thử] $proj.$($w.vai): $(if ($muon -eq 'claude') { '↪ Claude' } else { '↩ Codex' }) ($ly)"; return }
    # ô đang làm dở thì không đổi giữa chừng
    $d = Sync-Doi $proj; $m = if ($d) { @($d.worker) | Where-Object { $_.vai -eq $w.vai } | Select-Object -First 1 } else { $null }
    if ($m -and $m.o) { $st = Get-PaneState "$($m.o)"; if ($st -and $st.state -eq 'work') { return } }
    if ($muon -eq 'claude') { $tam | Add-Member -NotePropertyName $key -NotePropertyValue ([ordered]@{ ai = 'claude'; tu = (Get-Date -Format 'yyyy-MM-dd HH:mm'); ly = $ly }) -Force }
    else { $tam.PSObject.Properties.Remove($key) }
    Save-AiTam $tam
    Write-Host "🔀 $key → $(if ($muon -eq 'claude') { '↪ Claude dự phòng' } else { '↩ về Codex' }) ($ly)" -ForegroundColor Cyan
    if ($m -and $m.o) { & $exe cli --no-auto-start kill-pane --pane-id $m.o 2>$null | Out-Null }
    & $PSCommandPath doi $proj "thuc:$($w.vai)" | Out-Null
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
            $alive = @(Get-Panes | ForEach-Object { "$($_.pane_id)" })   # 05/10: đọc o-list.json, không hỏi WezTerm mỗi 30 giây
            foreach ($id in @($left)) { if ($id -notin $alive) { Write-Host "❌ Ô $id đã đóng."; $left.Remove($id) | Out-Null; $code = [Math]::Max($code, 1) } }
        }
        Start-Sleep -Seconds 2
    }
    return $code
}

switch ($Cmd) {
    'list' {
        $panes = @(Get-Panes)   # 05/10: đọc o-list.json (cột ĐANG CHỌN lấy từ file, có thể trống)
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
    # chon-ai <DựÁn.Vai>: chỉ chạy bước chọn AI (thử: đặt WEZ_CHON_AI_THU=1 để chỉ in quyết định, không đổi ô)
    'chon-ai' { Chon-AI $Rest[0] }
    'send' {
        Chon-AI $Rest[0]   # vai Codex mà tài khoản sắp hết → tạm chuyển Claude (và ngược lại khi Codex hồi)
        $id = Resolve-Id $Rest[0] -Thuc; $text = ($Rest[1..($Rest.Count - 1)] -join ' ')   # -Thuc: worker đang ngủ thì tự đánh thức
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
        # 04/10: câu dài → Enter đôi khi tới trước khi ô nhận xong chữ (Codex / Claude để nguyên chữ ở ô nhập,
        # ca đêm báo "đã giao" mà không chạy). Kiểm 3 lần: chữ đầu câu còn nằm ở dòng nhập (› hoặc ❯) → Enter lại.
        $dau = ($text -replace '\s+', ' ').Trim(); $dau = $dau.Substring(0, [Math]::Min(25, $dau.Length))
        for ($k = 0; $k -lt 3; $k++) {
            Start-Sleep -Milliseconds 1200
            $man = (& $exe cli --no-auto-start get-text --pane-id $id) -join "`n"
            $conNhap = $man -split "`n" | Where-Object { $_ -match '^\s*[›❯>]\s' -and ($_ -replace '\s+', ' ').Contains($dau) }
            if (-not $conNhap) { break }
            & $exe cli --no-auto-start send-text --pane-id $id --no-paste "`r"
        }
        Set-PaneState $id 'work'   # để `cho` biết là vừa giao việc
        Add-Viec $id $text
    }
    # viec: in checklist việc đã giao (☑ xong · ☐ chưa) · viec xong <số> : tự đánh dấu xong · viec bo <số> : bỏ việc
    'viec' {
        $vs = @(Read-Viec)
        if ("$($Rest[0])" -in 'xong', 'bo') {
            foreach ($so in ("$($Rest[1])" -split ',')) {
                $v = $vs | Where-Object { "$($_.so)" -eq $so.Trim() } | Select-Object -First 1
                if (-not $v) { Write-Host "Không có việc $so" -ForegroundColor Yellow; continue }
                if ($Rest[0] -eq 'xong') { $v.xong = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() } else { $v.bo = $true }
            }
            Save-Viec $vs; break
        }
        foreach ($v in $vs | Select-Object -Last 40) {
            $o = if ($v.bo) { '✖' } elseif ($v.xong) { '☑' } else { '☐' }
            Write-Host ("{0} {1,3}. {2} — {3}" -f $o, $v.so, $v.ai, $v.viec)
        }
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
        $focus = Get-Focus
        if ($Canh -and $env:WEZTERM_PANE) {
            $new = & $exe cli --no-auto-start split-pane --pane-id $env:WEZTERM_PANE --right --percent 50 --cwd $proj.FullName -- powershell -NoLogo -NoExit -Command $psCmd
        } else {
            $new = & $exe cli --no-auto-start spawn --cwd $proj.FullName -- powershell -NoLogo -NoExit -Command $psCmd
            $tieuDe = if ($tenTk) { "$tenTk · $($proj.Name)" } else { "$($proj.Name) · việc giao" }
            if ($new) { & $exe cli --no-auto-start set-tab-title --pane-id $new.Trim() $tieuDe }
        }
        if (-not $new) { Write-Error 'Không mở được ô mới.'; exit 1 }
        $new = $new.Trim()
        Set-Focus $(if ($focus) { $focus } else { $env:WEZTERM_PANE })   # giữ màn hình ở ô bạn đang xem
        Set-PaneState $new 'work'
        Add-Viec $new $task
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
        # vai đang tạm chạy Claude vì tài khoản Codex sắp hết (ai-tam.json) → mở bằng Claude, lời giao vai có ghi chú dự phòng
        $tamAi = Read-AiTam
        foreach ($w in @($def.worker)) {
            if ($w -and -not $w.router -and $tamAi.PSObject.Properties["$($def.du_an).$($w.vai)"]) {   # router: không dùng tài khoản Codex nào → không dự phòng
                $w.ai = 'claude'
                $w.viec = "$($w.viec) [ĐANG DỰ PHÒNG: bạn là bản Claude thay tạm bản Codex của vai này (Codex hết hạn mức) — không nhớ hội thoại của bản Codex: đọc brief + tien-do để nắm việc dở, ghi kết quả vào file như thường]"
            }
        }
        $aiRoot = if ($cfg -and $cfg.aiRoot) { $cfg.aiRoot } else { 'E:\AI' }
        $projDir = Join-Path $aiRoot $def.du_an
        New-Item -ItemType Directory -Force $doiDir | Out-Null
        $soF = Join-Path $doiDir "$($def.du_an).json"
        $cu = Sync-Doi $def.du_an
        if ("$($Rest[1])" -eq 'tat') {
            if ($cu) { foreach ($m in @($cu.manager) + @($cu.worker)) { if ($m -and $m.o) { & $exe cli --no-auto-start kill-pane --pane-id $m.o } } }
            Write-Host "🛑 Đã tắt đội $($def.du_an)"; break
        }
        # 04/10: báo WezTerm "đang xếp ô" → tạm dừng thanh tên 🏷 / bảng 📊 / tự ngủ / tự lưu cho tới khi xếp + bật AI xong
        # (trước đây chúng chen vào tách / đóng ô giữa lúc đang xếp đội → bố cục giành nhau, WezTerm đứng hình)
        $xepF = Join-Path $env:LOCALAPPDATA 'wez-ai\dang-xep.txt'
        function Giu-Xep($giay) { try { [IO.File]::WriteAllText($xepF, "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + $giay)") } catch {} }
        Giu-Xep 120
        $choBat = New-Object System.Collections.ArrayList   # ô AI đã dựng khung, chờ tới lượt bật (pha 2)
        $oCu = @{}
        if ($cu) { foreach ($m in @($cu.manager) + @($cu.worker)) { if ($m -and $m.vai -and $m.o) { $oCu[$m.vai] = "$($m.o)" } } }
        # Worker đang NGỦ (WezTerm tự đóng khi rảnh lâu, nhớ phiên trong sổ): "doi X" mở lại tất cả đúng phiên cũ;
        # "doi X thuc:<Vai>" (do send gọi) chỉ đánh thức vai đó, các vai khác ngủ tiếp (03/10/2026)
        $nguInfo = @{}
        # không có ô mà còn nhớ phiên (ngủ, hoặc đã đóng) → coi là đánh thức được, mở lại đúng phiên đó
        if ($cu) { foreach ($m in @($cu.worker)) { if ($m -and $m.vai -and -not $m.o -and ($m.ngu -or $m.session)) {
            # 04/10: vai đã đổi AI (vd Claude → Codex) thì phiên cũ không dùng được → mở mới, tránh "resume --last" vớ nhầm phiên vai khác
            $dn = @($def.worker) | Where-Object { $_.vai -eq $m.vai } | Select-Object -First 1
            if ($dn -and $m.ai -and $dn.ai -ne $m.ai) { continue }
            $nguInfo[$m.vai] = $m } } }
        # phiên theo VAI (nguồn chuẩn trong sổ đội) — giữ lại khi ghi sổ, để mở lại / ngủ / thức luôn đúng phiên
        $sesCu = @{}
        if ($cu) { foreach ($m in @($cu.manager) + @($cu.worker)) { if ($m -and $m.vai -and $m.session) { $sesCu[$m.vai] = "$($m.session)" } } }
        $thuc = if ("$($Rest[1])" -like 'thuc:*') { "$($Rest[1])".Substring(5) } else { $null }
        $focus = Get-Focus   # đánh thức worker (do send gọi) xong thì trả màn hình về đây, không nhảy sang tab đội
        $launchDir = Join-Path $doiDir $def.du_an
        New-Item -ItemType Directory -Force $launchDir | Out-Null
        $bom = New-Object Text.UTF8Encoding $true
        $ws = @($def.worker | Where-Object { -not ($thuc -and $nguInfo[$_.vai] -and $_.vai -ne $thuc) })   # bỏ các vai ngủ tiếp khỏi bố cục
        $tenWorker = ($ws | ForEach-Object { "$($def.du_an).$($_.vai)" }) -join ', '
        if (-not $tenWorker) { $tenWorker = "chưa có worker (tự làm; code dài giao lẻ bằng wez.ps1 giao $($def.du_an) codex; cần đội thì báo Tổng quản)" }
        # Lời nhắn đầu tiên cho từng vai — gọi nhau bằng TÊN (DựÁn.Vai), không dùng số ô
        # tên hiển thị (có dấu, vd "Số liệu") khác tên gọi lệnh (không dấu, vd Sino.SoLieu) khi định nghĩa có trường "ten"
        function TenVai($m) { if ($m.ten) { $m.ten } else { $m.vai } }
        function Loi($m, $laManager) {
            $quyen = if ($m.quyen) { " QUYỀN CỦA BẠN: $($m.quyen)" } else { '' }
            if ($laManager) {
                return "Bạn là $($m.icon) $(TenVai $m) dự án $($def.du_an): $($m.viec). Đội của bạn: $tenWorker (cùng tab '$($def.logo) $($def.du_an) · đội' với bạn: bạn nửa trái, worker nửa phải; vai + quyền từng worker: E:\AI\Hion\doi\$($def.du_an).json).$quyen " +
                    "Giao việc bằng TÊN, không dùng số ô: E:\AI\Hion\cai-dat\wez.ps1 send $($def.du_an).<Vai> `"việc`" rồi wez.ps1 cho $($def.du_an).<Vai> (đợi xong, đọc kết quả). " +
                    "LUẬT VẬN HÀNH: E:\AI\Hion\quy-trinh-lien-mach.md (3 vùng quyền, không hỏi lại người dùng việc 🟢, không đứng chờ, brief 6 mục, báo cáo 5 trường). Việc 🔴 (tiền/gửi ra ngoài/xoá/push/đổi giá) → duyet.js them rồi làm tiếp việc khác. " +
                    "Bây giờ: đọc file luật đó + AGENTS.md + tien-do của dự án + dòng [$($def.du_an)] trong E:\AI\Hion\quyet-dinh.md, báo 3 dòng việc đang làm / kẹt, rồi TỰ giao việc 🟢 tiếp theo cho worker và làm tiếp."
            }
            return "Bạn là worker $($def.logo) $($def.du_an) · $($m.icon) $(TenVai $m). Phụ trách: $($m.viec). Manager của bạn: $($def.du_an).Manager.$quyen " +
                "Luật chung: E:\AI\Hion\quy-trinh-lien-mach.md (làm việc 🟢 không hỏi lại; xong báo Manager đủ 5 trường: Đầu ra · Xong chưa · Bằng chứng · Còn lại · Ai làm tiếp). Chỉ nhận việc từ Manager $($def.du_an) hoặc Tổng quản Hion; làm đúng phần mình; khoá file trước khi sửa; không tự commit nếu không được dặn; không gửi tin/đăng bài/chạm tiền khi chưa được duyệt. " +
                "Bây giờ: đọc AGENTS.md + tien-do của dự án, trả lời 3 dòng (bạn là ai, quyền của bạn tóm 1 dòng, sẵn sàng) rồi CHỜ việc. Chưa sửa file nào."
        }
        # Mở 1 ô; Claude đặt tên bằng -n (hiện trên statusline + tiêu đề ô), Codex đổi tên bằng /rename sau khi mở
        function Mo($m, $laManager, $splitFrom, $huong, $pct) {
            $ten = "$($def.logo) $($def.du_an) · $($m.icon) $(TenVai $m)"
            $loiF = Join-Path $launchDir "$($m.vai).txt"
            [IO.File]::WriteAllText($loiF, (Loi $m $laManager), $bom)
            $l = "Get-ChildItem Env:CLAUDE* -ErrorAction SilentlyContinue | Remove-Item`r`n"
            # 04/10: PHA 1 chỉ dựng khung — ô đợi file .go (pha 2 thả lần lượt) rồi mới chạy AI. Ô AI mở sẵn mà bị tách / đổi cỡ
            # thì Claude/Codex vẽ lại cả hội thoại mỗi lần → mở đội 5 ô = hàng chục lần vẽ lại cùng lúc → WezTerm giật / đứng hình.
            $go = Join-Path $launchDir "mo-$($m.vai).go"
            Remove-Item -LiteralPath $go -ErrorAction SilentlyContinue
            $l += "Write-Host '⏳ Chờ tới lượt mở (đang xếp đội)…' -ForegroundColor DarkGray`r`n"
            $l += "`$go = '$go'; `$i = 0; while (-not (Test-Path -LiteralPath `$go) -and `$i -lt 1200) { Start-Sleep -Milliseconds 300; `$i++ }`r`n"   # tối đa 6 phút rồi tự chạy
            $l += "Remove-Item -LiteralPath `$go -ErrorAction SilentlyContinue; Clear-Host`r`n"
            $ngu = $nguInfo[$m.vai]   # đang ngủ → mở lại ĐÚNG phiên cũ (nhớ hết việc trước), không gửi lời giao vai lại
            if ($m.ai -eq 'codex') {
                $bang = Join-Path $HOME '.codex-tai-khoan.json'
                if (Test-Path $bang) {
                    $b = Get-Content -Raw -Encoding UTF8 $bang | ConvertFrom-Json
                    # 04/10: vai có "tk" → dùng đúng tài khoản đó (chia theo loại việc); không có → tài khoản của dự án
                    $soTk = if ($m.tk) { [int]$m.tk } else { $b.duAn.($def.du_an) }
                    $tk = $b.taiKhoan | Where-Object { $_.so -eq $soTk } | Select-Object -First 1
                    if ($tk) { $l += "`$env:CODEX_HOME = '$($tk.thuMuc)'`r`n" }
                }
                # 06/10: "router": true → Codex qua 9router (profile router trong ~\.codex\config.toml, cổng localhost:20128)
                if ($m.router) { $l += "`$env:CODEX_HOME = '$HOME\.codex'`r`n" }
                # "chan" (vai chỉ đọc: Kiểm soát / Security) → sandbox read-only; "timWeb" → bật tìm web (--search)
                $sb = if ("$($m.chan)" -match '\bWrite\b') { ' -s read-only' } else { '' }   # chỉ vai bị chặn ghi file (Kiểm soát/Security)
                $web = if ($m.timWeb) { ' --search' } else { '' }
                if ($m.router) { $sb += ' --profile router' }
                # 04/10: không tìm thấy phiên theo tên (vd vai đổi tài khoản) → mở MỚI kèm lời giao vai; KHÔNG dùng "resume --last" (vớ nhầm phiên vai khác cùng tài khoản)
                if ($ngu) { $l += "codex.cmd --no-daemon resume$sb '$ten'; if (`$LASTEXITCODE) { codex.cmd --no-daemon$sb$web (Get-Content -Raw -Encoding UTF8 '$loiF') }`r`n" }
                else { $l += "codex.cmd --no-daemon$sb$web`r`n" }
            } else {
                # "chan" = khoá cứng công cụ (vd Kiểm soát/Security chỉ đọc: không Edit/Write được dù lỡ được bảo)
                $ds = @("$($m.chan)" -split ' ' | Where-Object { $_ })
                # 05/10: DeepSeek báo "API Error 400 Invalid schema for function Artifact" (lược đồ có regex) → luôn chặn Artifact
                if ($m.ai -eq 'deepseek' -and $ds -notcontains 'Artifact') { $ds += 'Artifact' }
                $chan = if ($ds) { " '--disallowedTools=$($ds -join ',')'" } else { '' }   # dạng = để cờ không nuốt lời nhắn phía sau
                # 04/10: "ai": "deepseek" = Claude Code chạy bằng DeepSeek (cổng tương thích Anthropic). Key đọc từ biến người dùng
                # DEEPSEEK_API_KEY lúc chạy — KHÔNG ghi key vào file mở ô. Không --remote-control (cần đăng nhập claude.ai).
                $rc = " --remote-control '$($def.du_an)-$($m.vai)'"
                if ($m.ai -eq 'deepseek') { $l += $DEEPSEEK_ENV + "`r`n"; $rc = '' }
                if ($ngu -and $ngu.session) { $l += "claude --resume $($ngu.session)$rc -n '$ten'$chan`r`n" }
                else { $l += "claude$rc -n '$ten'$chan (Get-Content -Raw -Encoding UTF8 '$loiF')`r`n" }
            }
            $lf = Join-Path $launchDir "mo-$($m.vai).ps1"
            [IO.File]::WriteAllText($lf, $l, $bom)
            # ô đội gọi thẳng claude / codex.cmd (CODEX_HOME đặt sẵn) → không cần profile, mở nhanh hơn (03/10)
            $a = @('powershell', '-NoLogo', '-NoProfile', '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', $lf)
            $id = if ($splitFrom) { & $exe cli --no-auto-start split-pane --pane-id $splitFrom $huong --percent $pct --cwd $projDir -- @a }
                  else { & $exe cli --no-auto-start spawn --cwd $projDir -- @a }
            $id = "$id".Trim()
            if ($id) { [void]$choBat.Add(@{ id = $id; go = $go; codexMoi = ($m.ai -eq 'codex' -and -not $ngu); ten = $ten; loiF = $loiF }) }
            return $id
        }
        # PHA 2: Codex mới mở → đợi sẵn sàng, /rename, gửi lời giao vai (Claude nhận lời giao vai ngay trong lệnh mở)
        function KhoiDong-Codex($id, $ten, $loiF) {   # chỉ Codex MỚI (Codex thức dậy thì đã có tên + vai trong phiên cũ)
            & {
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
                # 04/10: lời dài bị Codex gom thành "[Pasted Content …]" và Enter đầu có khi trôi → kiểm, còn nằm ở ô nhập thì Enter lại
                for ($k = 0; $k -lt 4; $k++) {
                    Start-Sleep -Milliseconds 1200
                    $man = (& $exe cli --no-auto-start get-text --pane-id $id) -join "`n"
                    if ($man -notmatch '(?m)^\s*›\s*\S.*(Pasted Content|Bạn là)') { break }
                    & $exe cli --no-auto-start send-text --no-paste --pane-id $id "`r"
                }
            }
        }
        $so = [ordered]@{ du_an = $def.du_an; logo = $def.logo; cap_nhat = (Get-Date -Format 'yyyy-MM-dd HH:mm'); manager = $null; worker = @() }
        # Bố cục (người dùng chốt 03/10): cả đội chung 1 tab — Manager nửa trái, worker nửa phải chia lưới 2 cột
        #   (4 worker = 2×2: trên-trái, trên-phải, dưới-trái, dưới-phải). Ô đã mở ở chỗ khác thì CHUYỂN vào đúng chỗ (giữ nguyên phiên),
        #   ô thiếu thì mở mới. Cả đội đã đứng chung 1 tab rồi thì để nguyên, không xếp lại.
        $panes = @(Get-Panes -Thuc)
        $tabOf = @{}; foreach ($p in $panes) { $tabOf["$($p.pane_id)"] = "$($p.tab_id)" }
        $mg = $def.manager
        $idsCu = @($oCu[$mg.vai]) + @($ws | ForEach-Object { $oCu[$_.vai] })
        # đếm vai THIẾU ô tường minh (03/10: mảng có $null bị PowerShell bỏ qua khi đếm → tưởng đủ đội, không mở vai đang ngủ)
        $thieu = @($ws | Where-Object { -not $oCu[$_.vai] }).Count + $(if ($oCu[$mg.vai]) { 0 } else { 1 })
        $chungTab = $thieu -eq 0 -and (@($idsCu | ForEach-Object { if ($_) { $tabOf[$_] } } | Select-Object -Unique)).Count -eq 1
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
            if ($c1.Count) { $h1 = Dat $c1[0] $false $mo '--right' 50; $ids[$c1[0].vai] = $h1 }   # đội chưa có worker: chỉ Manager cả tab
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
        $so.manager = [ordered]@{ o = $mo; vai = $mg.vai; ten = (TenVai $mg); icon = $mg.icon; ai = $mg.ai; mau = $mg.mau; session = $sesCu[$mg.vai] }
        foreach ($w in @($def.worker)) {   # giữ thứ tự định nghĩa; vai đang ngủ tiếp thì ghi lại để lần sau đánh thức đúng phiên
            if ($ids.ContainsKey($w.vai)) { $so.worker += [ordered]@{ o = $ids[$w.vai]; vai = $w.vai; ten = (TenVai $w); icon = $w.icon; ai = $w.ai; mau = $w.mau; viec = $w.viec; session = $sesCu[$w.vai] } }
            elseif ($nguInfo[$w.vai]) { $n0 = $nguInfo[$w.vai]; $so.worker += [ordered]@{ o = ''; vai = $w.vai; ten = (TenVai $w); icon = $w.icon; ai = $w.ai; mau = $w.mau; viec = $w.viec; ngu = $true; session = $n0.session; ngu_luc = $n0.ngu_luc } }
        }
        [IO.File]::WriteAllText($soF, ($so | ConvertTo-Json -Depth 5), $utf8)
        & $exe cli --no-auto-start set-tab-title --pane-id $mo "$($def.logo) $($def.du_an) · đội"
        if ($thuc -and $focus) { Set-Focus $focus } else { Set-Focus $mo }   # mở đội bằng tay thì cho xem đội; tự thức thì giữ màn hình
        $ghiChu = if ($chungTab) { 'cả đội đã chung 1 tab, giữ nguyên' } else { "xếp lại: Manager trái, worker lưới bên phải · mở mới $moMoi ô" }
        Write-Host ("👥 Đội $($def.du_an): Manager ô $mo · " + (($so.worker | ForEach-Object { "$($_.vai) ô $($_.o)" }) -join ' · ') + " ($ghiChu)") -ForegroundColor Cyan
        if ($ws.Count) { Write-Host "   Gọi bằng tên: wez.ps1 send $($def.du_an).$($ws[0].vai) `"việc`"" } else { Write-Host "   Gọi Manager: wez.ps1 send $($def.du_an).Manager `"việc`"" }
        # PHA 2 (04/10): khung đã xếp xong → bật AI từng ô một, cách nhau ~2 giây (Codex mới thì đợi nó sẵn sàng rồi mới sang ô sau)
        if ($choBat.Count) {
            Write-Host "   ⏳ Bật AI lần lượt $($choBat.Count) ô…" -ForegroundColor DarkGray
            Start-Sleep -Milliseconds 800   # cho bố cục ổn định
            foreach ($c in $choBat) {
                Giu-Xep 90
                [IO.File]::WriteAllText($c.go, 'go')
                if ($c.codexMoi) { KhoiDong-Codex $c.id $c.ten $c.loiF } else { Start-Sleep -Seconds 2 }
            }
            Write-Host "   ✅ Đã bật xong $($choBat.Count) ô" -ForegroundColor Green
        }
        Giu-Xep 5   # xong: 5 giây nữa WezTerm dựng lại thanh tên / bảng như thường
    }
    # don: liệt kê ô / tab thừa có thể đóng (tài liệu 📄, phiên phụ đang rảnh, PowerShell trống) — KHÔNG tự đóng.
    # don dong 1,3 : đóng các mục số 1 và 3 trong danh sách vừa liệt kê (03/10/2026)
    'don' {
        $donF = Join-Path $env:LOCALAPPDATA 'wez-ai\don.json'
        if ("$($Rest[0])" -eq 'dong') {
            if (-not (Test-Path $donF)) { Write-Error 'Chạy "wez.ps1 don" để xem danh sách trước.'; exit 1 }
            $ds = @(Get-Content $donF -Raw -Encoding UTF8 | ConvertFrom-Json)
            foreach ($so in ("$($Rest[1])" -split ',')) {
                $m = $ds | Where-Object { "$($_.so)" -eq $so.Trim() } | Select-Object -First 1
                if (-not $m) { Write-Host "Không có mục $so" -ForegroundColor Yellow; continue }
                foreach ($o in @($m.o)) { & $exe cli --no-auto-start kill-pane --pane-id $o 2>$null }
                Write-Host "🧹 Đã đóng mục ${so}: $($m.ten)"
            }
            Remove-Item $donF -ErrorAction SilentlyContinue
            break
        }
        $panes = @(Get-Panes)
        # ô thuộc đội (không bao giờ đề xuất đóng)
        $trongDoi = @{}
        foreach ($f in Get-ChildItem $doiDir -Filter *.json -ErrorAction SilentlyContinue) {
            $d = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($m in @($d.manager) + @($d.worker)) { if ($m -and $m.o) { $trongDoi["$($m.o)"] = $true } }
        }
        $ds = @(); $so = 0
        foreach ($g in ($panes | Group-Object tab_id)) {
            $that = @($g.Group | Where-Object { $_.title -notmatch 'ten-o' })   # bỏ ô tên 🏷
            $tenO = @($g.Group | Where-Object { $_.title -match 'ten-o' } | ForEach-Object { "$($_.pane_id)" })
            $loai = $null
            if ($that.Count -eq 0) { continue }
            if (@($that | Where-Object { "$($_.pane_id)" -eq "$env:WEZTERM_PANE" -or $trongDoi["$($_.pane_id)"] -or $_.title -match '📊' }).Count) { continue }
            $t = $that[0].title
            if (@($that | Where-Object { $_.title -notmatch '📄' }).Count -eq 0) { $loai = '📄 tài liệu' }
            elseif ($that.Count -eq 1 -and ($t -match '^✳' -or $t -match '\| Ready \|')) { $loai = '🔹 phiên phụ đang rảnh' }
            elseif ($that.Count -eq 1 -and ($t -match 'powershell|^[A-Z]:\\' -or $t -eq '')) { $loai = '⌨️ PowerShell trống' }
            if (-not $loai) { continue }
            $so++
            $ds += [ordered]@{ so = $so; ten = "$loai · $($t -replace '^[✳◐◓◑◒]\s*', '')"; o = @(@($that | ForEach-Object { "$($_.pane_id)" }) + @($tenO)) }
        }
        if ($ds.Count -eq 0) { Write-Host '✨ Không có tab thừa nào.'; break }
        [IO.File]::WriteAllText($donF, (ConvertTo-Json @($ds) -Depth 4), $utf8)
        Write-Host '🧹 Tab có thể đóng (đội, ô đang làm và ô của bạn không bao giờ có trong danh sách):' -ForegroundColor Cyan
        foreach ($m in $ds) { Write-Host ("  {0}. {1}" -f $m.so, $m.ten) }
        Write-Host "Đóng: wez.ps1 don dong 1,2   (chọn số; không chạy thì không đóng gì)" -ForegroundColor DarkGray
    }
    # tat <dự án> : liệt kê mọi ô của dự án (đội, phiên phụ, tài liệu) · tat <dự án> dong : đóng hết (03/10/2026)
    #   Không bao giờ đóng ô đang gọi lệnh, ô Tổng quản, bảng 📊. Mở lại: doi <dự án> hoặc Ctrl+Shift+O. Phím tương ứng: Ctrl+Shift+F4.
    'tat' {
        $proj = "$($Rest[0])"
        if (-not $proj) { Write-Error 'Cách dùng: wez.ps1 tat <dự án> [dong]'; exit 1 }
        $doiSo = Sync-Doi $proj
        $trongDoi = @{}
        if ($doiSo) { foreach ($m in @($doiSo.manager) + @($doiSo.worker)) { if ($m -and $m.o) { $trongDoi["$($m.o)"] = $true } } }
        $giu = @{ "$env:WEZTERM_PANE" = $true }
        $hf = Join-Path $doiDir 'Hion.json'
        if (Test-Path $hf) { $h = Get-Content $hf -Raw -Encoding UTF8 | ConvertFrom-Json; if ($h.manager) { $giu["$($h.manager.o)"] = $true } }
        $ds = @(Get-Panes | Where-Object {
            $id = "$($_.pane_id)"
            if ($giu[$id] -or $_.title -match 'ten-o|📊 Tổng quan') { return $false }   # chỉ bỏ bảng tổng quan, KHÔNG bỏ worker 📊 Số liệu
            $cwd = [uri]::UnescapeDataString("$($_.cwd)") -replace '^file:///', '' -replace '/', '\'
            $trongDoi[$id] -or ($cwd -match "^[A-Za-z]:\\AI\\$([regex]::Escape($proj))(\\|$)")
        })
        if ($ds.Count -eq 0) { Write-Host "Không có ô nào của $proj đang mở."; break }
        if ("$($Rest[1])" -ne 'dong') {
            Write-Host "Các ô của ${proj} sẽ bị đóng:" -ForegroundColor Cyan
            foreach ($p in $ds) { Write-Host ("  ô {0,-4} {1}" -f $p.pane_id, ($p.title -replace '^[✳◐◓◑◒]\s*', '')) }
            Write-Host "Đóng thật: wez.ps1 tat $proj dong   (AI đang làm sẽ bị dừng)" -ForegroundColor DarkGray
            break
        }
        foreach ($p in $ds) { & $exe cli --no-auto-start kill-pane --pane-id $p.pane_id 2>$null }
        Write-Host "🛑 Đã đóng $($ds.Count) ô của $proj. Mở lại: wez.ps1 doi $proj"
    }
    # khoidonglai: khởi động lại toàn bộ WezTerm rồi tự mở lại mọi phiên (03/10/2026).
    #   Đợi bản tự lưu mới (≤ 35 giây) → chép làm bản lưu tay dự phòng → nhờ Task Scheduler (không thuộc WezTerm nên không bị tắt theo)
    #   tắt CẢ CÂY tiến trình WezTerm (taskkill /T: gồm Claude/Codex bên trong, tránh phiên cũ chạy mồ côi) → mở lại WezTerm.
    #   Lần 03/10 dùng Stop-Process: WezTerm cũ (chạy quyền admin) không tắt được → 2 WezTerm + 14 phiên AI cũ chạy song song.
    'khoidonglai' {
        $f = Join-Path $env:LOCALAPPDATA 'wez-ai\bo-cuc-tu-luu.json'
        $start = Get-Date
        while ((-not (Test-Path $f) -or (Get-Item $f).LastWriteTime -lt $start.AddSeconds(2)) -and ((Get-Date) - $start).TotalSeconds -lt 40) { Start-Sleep 2 }
        Copy-Item $f (Join-Path $env:LOCALAPPDATA 'wez-ai\bo-cuc-luu.json') -Force
        $dir = Join-Path $env:LOCALAPPDATA 'wez-ai\khoi-dong-lai'; New-Item -ItemType Directory -Force $dir | Out-Null
        $gui = Join-Path (Split-Path $exe) 'wezterm-gui.exe'
        $s = @"
`$log = '$dir\nhat-ky.txt'
"`$(Get-Date -Format 'HH:mm:ss') bắt đầu" | Out-File `$log -Encoding utf8
schtasks /delete /tn 'WezAI-KhoiDongLai' /f 2>&1 | Out-Null   # 04/10: tác vụ hẹn "once sau 5 phút" + /run ngay → không xoá thì 5 phút sau khởi động lại LẦN NỮA
Start-Sleep 3
taskkill /IM wezterm-gui.exe /T /F 2>&1 | Out-File `$log -Append -Encoding utf8
Start-Sleep 3
`$con = @(Get-Process wezterm-gui -ErrorAction SilentlyContinue)
if (`$con.Count) { "`$(Get-Date -Format 'HH:mm:ss') ⚠️ còn `$(`$con.Count) WezTerm không tắt được (chạy quyền admin?) — không mở thêm bản mới" | Out-File `$log -Append -Encoding utf8; exit 1 }
Start-Process '$gui'
"`$(Get-Date -Format 'HH:mm:ss') đã mở lại WezTerm" | Out-File `$log -Append -Encoding utf8
"@
        [IO.File]::WriteAllText("$dir\chay.ps1", $s, (New-Object Text.UTF8Encoding $true))
        $st = (Get-Date).AddMinutes(5).ToString('HH:mm')
        # 04/10: WezTerm chạy quyền Administrator → tác vụ quyền thường bị "Access is denied" khi taskkill → chạy tác vụ quyền cao nhất (người gọi cũng là admin)
        $laAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $rl = if ($laAdmin) { @('/rl', 'HIGHEST') } else { @() }
        schtasks /create /tn 'WezAI-KhoiDongLai' /sc once /st $st /tr "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dir\chay.ps1`"" @rl /f | Out-Null
        Write-Host "🔄 Bản lưu $((Get-Item $f).LastWriteTime.ToString('HH:mm:ss')) · khởi động lại sau ~3 giây; mở lên sẽ tự mở lại mọi phiên. Nhật ký: $dir\nhat-ky.txt" -ForegroundColor Cyan
        schtasks /run /tn 'WezAI-KhoiDongLai' | Out-Null
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
