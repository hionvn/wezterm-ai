# doi-ca.ps1 — Đội AI trực ca: nhiều tài khoản Codex chạy song song, Codex hết lượt thì Claude tự vào làm tiếp.
# Dùng trên Windows + WezTerm + Codex CLI + Claude Code. Gõ:  doi-ca help
param([Parameter(Position = 0)][string]$Lenh = 'help', [Parameter(Position = 1)][string]$Thu1, [switch]$KhongHoi)
$ErrorActionPreference = 'Continue'
$NHA = Join-Path $env:USERPROFILE '.doi-ca'
$CFG = Join-Path $NHA 'cau-hinh.json'
$TT = Join-Path $NHA 'ca'            # trạng thái ca của từng ô Codex
$LOG = Join-Path $NHA 'nhat-ky.log'
New-Item -ItemType Directory -Force -Path $NHA, $TT | Out-Null

# ───────────────────────── cấu hình ─────────────────────────
function Doc-CauHinh {
    if (-not (Test-Path $CFG)) { return $null }
    try { Get-Content -Raw -Encoding UTF8 $CFG | ConvertFrom-Json } catch { Write-Host "❌ cau-hinh.json bị lỗi: $($_.Exception.Message)" -ForegroundColor Red; $null }
}
function Luu-CauHinh($c) { [IO.File]::WriteAllText($CFG, ($c | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false)) }
$C = Doc-CauHinh
function Can-CauHinh { if (-not $script:C) { Write-Host '⚠️ Chưa có cấu hình. Chạy:  doi-ca cai' -ForegroundColor Yellow; exit 1 } }
function Ng($ten, $macDinh) { if ($C -and $C.nguong -and $null -ne $C.nguong.$ten) { [int]$C.nguong.$ten } else { $macDinh } }

function Ghi($msg) { $l = "{0}  {1}" -f (Get-Date -Format 'dd/MM HH:mm'), $msg; Add-Content -Path $LOG -Value $l -Encoding UTF8; Write-Host $l
    if ($C -and $C.ntfy -and $msg -match '❌|🆘') { try { Invoke-RestMethod -Method Post -Uri "https://ntfy.sh/$($C.ntfy)" -Body ([Text.Encoding]::UTF8.GetBytes($msg)) | Out-Null } catch {} } }

# ───────────────────────── WezTerm ─────────────────────────
function Tim-WezExe {
    if ($C -and $C.wezterm -and (Test-Path $C.wezterm)) { return $C.wezterm }
    $g = Get-Command wezterm -ErrorAction SilentlyContinue; if ($g) { return $g.Source }
    foreach ($p in "$env:ProgramFiles\WezTerm\wezterm.exe", "$env:LOCALAPPDATA\Programs\WezTerm\wezterm.exe") { if (Test-Path $p) { return $p } }
    $null
}
$WEZ = Tim-WezExe
function Noi-Wez {
    $s = Get-ChildItem "$HOME\.local\share\wezterm\gui-sock-*" -ErrorAction SilentlyContinue |
        Where-Object { Get-Process -Id ($_.Name -replace 'gui-sock-', '') -ErrorAction SilentlyContinue } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($s) { $env:WEZTERM_UNIX_SOCKET = $s.FullName; return $true }; $false
}
function W { & $WEZ cli @args 2>$null }
function Cac-O { @(W list --format json | Out-String | ConvertFrom-Json | ForEach-Object { $_ }) }   # PS 5.1: ConvertFrom-Json trả mảng lồng → trải ra
function Con-Mo($id) { "$id" -in @(Cac-O | ForEach-Object { "$($_.pane_id)" }) }
function Doc-O($id, $n = 60) { @(W get-text --pane-id $id) | Where-Object { $_.Trim() } | Select-Object -Last $n }
function Go($id, $text) {   # dán câu rồi nhấn Enter
    W send-text --pane-id $id -- ($text -replace '"', '\"') | Out-Null; Start-Sleep -Milliseconds 400
    W send-text --pane-id $id --no-paste "`r" | Out-Null
}
function Esc($id) { W send-text --pane-id $id --no-paste "$([char]27)" | Out-Null; Start-Sleep -Milliseconds 500 }

# Rảnh hay bận — đoán từ màn hình (không cần cài hooks)
function Ranh-Codex($o) { $o.title -match '\|\s*Ready' }
function Trang-Claude($id) {
    $t = (Doc-O $id 25) -join "`n"
    if ($t -match '(?i)trust this folder|Do you want to|Would you like to|❯ 1\. Yes') { return 'hoi' }   # đang hỏi người dùng
    if ($t -match '(?i)esc to interrupt') { return 'ban' }
    'ranh'
}
function Doi-Claude($id, $giay = 900) {   # đợi Claude làm xong; trả 'ranh' | 'hoi' | 'het-gio' | 'dong'
    Start-Sleep 8; $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $giay) {
        if (-not (Con-Mo $id)) { return 'dong' }
        $s = Trang-Claude $id; if ($s -ne 'ban') { Start-Sleep 3; $s2 = Trang-Claude $id; if ($s2 -ne 'ban') { return $s2 } }
        Start-Sleep 5
    }
    'het-gio'
}
function Mo-Claude($thuMuc, $viec) {
    $f = Join-Path $NHA ("giao-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss')); [IO.File]::WriteAllText($f, $viec, (New-Object Text.UTF8Encoding $false))
    $lenh = if ($C -and $C.lenhClaude) { $C.lenhClaude } else { 'claude --permission-mode auto' }
    $id = W spawn --cwd $thuMuc -- powershell -NoLogo -NoExit -Command "$lenh (Get-Content -Raw -Encoding UTF8 '$f')"
    if ($id) { $id = "$id".Trim(); W set-tab-title --pane-id $id "🤖 Claude thay ca · $(Split-Path -Leaf $thuMuc)" | Out-Null }
    $id
}

# ───────────────────────── Codex: lượt dùng ─────────────────────────
function Doc-Luot($lines, [string]$SauDong) {
    $lines = @($lines)
    if ($SauDong) { for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -match [regex]::Escape($SauDong)) { $lines = $lines[$i..($lines.Count - 1)]; break } } }
    $txt = $lines -join "`n"; $r = [ordered]@{ h5 = $null; tuan = $null; het = $false }
    $m = [regex]::Matches($txt, '5h(?: limit:)?[^\n%]*?(\d+)% left'); if ($m.Count) { $r.h5 = [int]$m[$m.Count - 1].Groups[1].Value }
    $m = [regex]::Matches($txt, '(?i)weekly(?: limit:)?[^\n%]*?(\d+)% left'); if ($m.Count) { $r.tuan = [int]$m[$m.Count - 1].Groups[1].Value }
    if ((($lines | Select-Object -Last 12) -join "`n") -match "(?i)usage limit|hit your .{0,20}limit|reached your .{0,20}limit|rate limit reached|quota exceeded") { $r.het = $true }
    if ($r.h5 -eq 0 -or $r.tuan -eq 0) { $r.het = $true }
    $r
}
function Goc-DuAn { if ($C -and $C.thuMucDuAn) { $C.thuMucDuAn.TrimEnd('\') } else { 'C:\AI' } }
function Tim-Codex {
    $goc = [regex]::Escape((Goc-DuAn))
    foreach ($o in Cac-O) {
        if (-not $o.cwd) { continue }
        $cwd = ([uri]$o.cwd).LocalPath.TrimEnd('\', '/')
        if ($cwd -notmatch "^$goc\\([^\\]+)") { continue }; $duAn = $Matches[1]
        if ($o.title -notmatch '^[^|]+ \| [^|]+') { continue }   # tiêu đề kiểu Codex: "DuAn | Ready | …"
        [pscustomobject]@{ id = "$($o.pane_id)"; duAn = $duAn; thuMuc = $cwd; o = $o; luot = (Doc-Luot (Doc-O $o.pane_id)) }
    }
}
function Tk-CuaDuAn($duAn) { if (-not $C) { return $null }; $so = $C.duAn.$duAn; $C.taiKhoan | Where-Object { $_.so -eq $so } | Select-Object -First 1 }
function Ten-Codex($duAn) { $t = Tk-CuaDuAn $duAn; if ($t) { $t.ten } else { "Codex ($duAn)" } }
function Lay-Ca($id) { $f = Join-Path $TT "$id.json"; if (Test-Path $f) { $o = Get-Content -Raw $f | ConvertFrom-Json; foreach ($k in 'traLuc', 'daNhac') { if ($null -eq $o.PSObject.Properties[$k]) { $o | Add-Member $k 0 } }; $o } else { $null } }
function Luu-Ca($id, $o) { [IO.File]::WriteAllText((Join-Path $TT "$id.json"), ($o | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false)) }
function Bay-Gio { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

$LUAT_DEM = 'Luật khi không có người trông: KHÔNG nhắn tin cho khách, KHÔNG đăng bài, KHÔNG tiêu tiền, KHÔNG git push, KHÔNG gộp vào main, KHÔNG xoá file. Việc cần người dùng quyết thì ghi vào file CAN-DUYET.md của dự án rồi làm việc khác.'

# Một lượt quét: nhắc bàn giao / đổi ca / trả ca
function Quet([switch]$ChiXem, [int]$KiemLaiPhut = -1) {
    if ($KiemLaiPhut -lt 0) { $KiemLaiPhut = Ng 'kiemLaiPhut' 30 }
    foreach ($k in @(Tim-Codex)) {
        $ca = Lay-Ca $k.id
        if (-not $ca) { $ca = [pscustomobject]@{ ca = 'codex'; daNhac = 0; claude = ''; kiemLuc = 0; traLuc = 0; duAn = $k.duAn; thuMuc = $k.thuMuc } }
        $ten = Ten-Codex $k.duAn; $l = $k.luot
        if ($ChiXem) { Write-Host ("Ô {0} · {1} · {2} · 5h còn {3}% · tuần còn {4}% · hết lượt: {5} · đang ca: {6}" -f $k.id, $k.duAn, $ten, $l.h5, $l.tuan, $(if ($l.het) { 'CÓ' } else { 'không' }), $ca.ca); continue }

        if ($ca.ca -eq 'codex') {
            $dangCo = Get-ChildItem $TT -Filter '*.json' | Where-Object { $_.BaseName -ne $k.id } | ForEach-Object { Get-Content -Raw $_.FullName | ConvertFrom-Json } |
                Where-Object { $_.duAn -eq $k.duAn -and $_.ca -eq 'claude' -and (Con-Mo $_.claude) } | Select-Object -First 1
            $vuaTra = $ca.traLuc -and ((Bay-Gio) - $ca.traLuc) -lt 600
            if ($l.het -and $vuaTra) { }   # vừa trả ca: chữ "hết lượt" cũ có thể còn trên màn hình
            elseif ($l.het -and $dangCo) { $ca.ca = 'claude'; $ca.claude = $dangCo.claude; $ca.kiemLuc = Bay-Gio; Ghi "🔁 $($k.duAn): ô $($k.id) hết lượt — dùng chung Claude ô $($dangCo.claude)" }
            elseif ($l.het) {
                # dùng lại ô Claude thay ca cũ của dự án nếu còn mở và đang rảnh, không thì mở ô mới
                $cu = if ($ca.claude -and (Con-Mo $ca.claude) -and (Trang-Claude $ca.claude) -eq 'ranh') { $ca.claude } else { '' }
                $viec = "Đổi ca: $ten (ô $($k.id)) đã hết lượt. Bạn làm tiếp dự án $($k.duAn). Đọc AGENTS.md, các file tien-do*/TIEN-DO*, giao-viec* (nếu có) và git status, git diff để biết Codex đang dở gì, rồi làm tiếp đúng việc đó. $LUAT_DEM Xong mỗi phần thì ghi vào file tiến độ và commit."
                if ($cu) { Esc $cu; Go $cu $viec; $new = $cu } else { $new = Mo-Claude $k.thuMuc $viec }
                if (-not $new) { Ghi "❌ $($k.duAn): $ten hết lượt nhưng không mở được Claude"; continue }
                $ca.ca = 'claude'; $ca.claude = $new; $ca.kiemLuc = Bay-Gio
                Ghi "🔁 $($k.duAn): $ten hết lượt → Claude ở ô $new làm tiếp"
                Start-Sleep 12
                if ((Trang-Claude $new) -eq 'hoi') { Ghi "🆘 $($k.duAn): Claude ô $new đang đứng ở một câu hỏi (vd 'tin thư mục này?') — cần người bấm" }
            }
            elseif ($null -ne $l.h5 -and $l.h5 -le (Ng 'nhac' 10) -and -not $ca.daNhac -and (Ranh-Codex $k.o)) {
                Go $k.id "Sắp hết lượt dùng ($($l.h5)% còn lại). Ghi bàn giao vào file tiến độ của dự án: đang làm gì, tới bước nào, bước tiếp theo, file nào đang sửa dở. Commit phần đã xong. Rồi làm tiếp bình thường."
                $ca.daNhac = 1; Ghi "⚠️ $($k.duAn): $ten còn $($l.h5)% → đã nhắc ghi bàn giao"
            }
            elseif ($null -ne $l.h5 -and $l.h5 -gt (Ng 'tra' 30)) { $ca.daNhac = 0 }
        }
        elseif ($ca.ca -eq 'claude') {
            if (-not (Con-Mo $ca.claude)) { Ghi "ℹ️ $($k.duAn): ô Claude $($ca.claude) đã đóng → trả ca cho $ten"; $ca.ca = 'codex' }
            elseif ((Bay-Gio) - $ca.kiemLuc -ge $KiemLaiPhut * 60 -and (Ranh-Codex $k.o)) {
                $ca.kiemLuc = Bay-Gio
                Go $k.id '/status'; Start-Sleep 4
                $l2 = Doc-Luot (Doc-O $k.id 40) '/status'
                if (-not $l2.het -and $null -ne $l2.h5 -and $l2.h5 -ge (Ng 'tra' 30)) {
                    if ((Trang-Claude $ca.claude) -eq 'ranh') {
                        Esc $ca.claude
                        Go $ca.claude "Trả ca: $ten đã có lượt lại. Ghi bàn giao vào file tiến độ (đang làm gì, tới bước nào, bước tiếp), commit, rồi DỪNG, không sửa thêm gì."
                        $kq = Doi-Claude $ca.claude 900
                        Go $k.id 'Claude vừa thay ca và đã ghi bàn giao. Đọc file tiến độ của dự án + git log gần nhất, rồi làm tiếp phần đang dở.'
                        $ca.ca = 'codex'; $ca.daNhac = 0; $ca.traLuc = Bay-Gio
                        Ghi "✅ $($k.duAn): $ten có lượt lại ($($l2.h5)%) → Claude bàn giao ($kq), Codex làm tiếp"
                    }
                    else { Ghi "⏳ $($k.duAn): $ten có lượt lại, Claude đang dở → đợi lượt sau" }
                }
            }
        }
        Luu-Ca $k.id $ca
    }
}

# ───────────────────────── tài khoản Codex ─────────────────────────
function Codex-Status($home_) { $cu = $env:CODEX_HOME; $env:CODEX_HOME = $home_; $s = (codex login status 2>&1 | Out-String).Trim(); $env:CODEX_HOME = $cu; $s -match 'Logged in' }
function Chuan-Bi-Home($home_) {
    $goc = Join-Path $env:USERPROFILE '.codex'
    New-Item -ItemType Directory -Force -Path $home_ | Out-Null
    if ($home_ -eq $goc) { return }
    foreach ($f in 'config.toml', 'AGENTS.md') { $s = Join-Path $goc $f; $d = Join-Path $home_ $f; if ((Test-Path $s) -and -not (Test-Path $d)) { Copy-Item $s $d } }
    foreach ($d in 'skills', 'rules', 'plugins') { $s = Join-Path $goc $d; $t = Join-Path $home_ $d; if ((Test-Path $s) -and -not (Test-Path $t)) { New-Item -ItemType Junction -Path $t -Target $s | Out-Null } }
}
function Dang-Nhap($ai) {
    Can-CauHinh
    $so = if ($ai -match '^\d+$') { [int]$ai } else { $C.duAn.$ai }
    $tk = $C.taiKhoan | Where-Object { $_.so -eq $so } | Select-Object -First 1
    if (-not $tk) { Write-Host "❌ Không thấy tài khoản '$ai' (gõ số 1, 2, 3… hoặc tên dự án)" -ForegroundColor Red; return }
    Chuan-Bi-Home $tk.thuMuc
    Write-Host ""; Write-Host "  $($tk.ten)  (tài khoản $so)" -ForegroundColor Cyan
    Write-Host "  👉 Trên trình duyệt hãy đăng nhập bằng:  $(if ($tk.gmail) { $tk.gmail } else { '(chưa ghi Gmail trong cấu hình)' })" -ForegroundColor Yellow
    Write-Host "  ⚠️ Trình duyệt đang nhớ Gmail khác thì đăng xuất / chọn đúng Gmail ở trên." -ForegroundColor DarkYellow; Write-Host ""
    $cu = $env:CODEX_HOME; $env:CODEX_HOME = $tk.thuMuc; codex login; $env:CODEX_HOME = $cu
}
function Bang-TaiKhoan {
    Can-CauHinh
    $C.taiKhoan | ForEach-Object {
        $tk = $_; $duAn = ($C.duAn.PSObject.Properties | Where-Object { $_.Value -eq $tk.so } | ForEach-Object Name) -join ', '
        $a = Join-Path $tk.thuMuc 'auth.json'
        [pscustomobject]@{ TK = $tk.so; 'Tên' = $tk.ten; 'Dự án' = $duAn; Gmail = $tk.gmail
            'Đăng nhập' = $(if (Codex-Status $tk.thuMuc) { '✅ còn' } else { "❌ mất → doi-ca dang-nhap $($tk.so)" })
            'Lúc' = $(if (Test-Path $a) { (Get-Item $a).LastWriteTime.ToString('dd/MM HH:mm') } else { '-' }) }
    } | Format-Table -AutoSize
}
function Mo-Codex($duAn) {
    Can-CauHinh
    if (-not $duAn) { $duAn = Split-Path -Leaf (Get-Location) } else { Set-Location (Join-Path (Goc-DuAn) $duAn) }
    $tk = Tk-CuaDuAn $duAn
    if ($tk) { $env:CODEX_HOME = $tk.thuMuc; Write-Host "🔑 $($tk.ten) (tài khoản $($tk.so)) cho $duAn" -ForegroundColor Cyan }
    else { Write-Host "⚠️ Dự án '$duAn' chưa gán tài khoản (sửa mục duAn trong $CFG) → dùng tài khoản mặc định" -ForegroundColor Yellow }
    codex
}

# ───────────────────────── kiểm tra máy ─────────────────────────
function Kiem-Tra {
    $script:ok = $true
    function Dong($ten, $dat, $goiY) { if ($dat) { Write-Host "  ✅ $ten" } else { Write-Host "  ❌ $ten  → $goiY" -ForegroundColor Yellow; $script:ok = $false } }
    Write-Host "`nKiểm tra máy cho Đội AI trực ca:" -ForegroundColor Cyan
    Dong 'Windows PowerShell 5.1+' ($PSVersionTable.PSVersion.Major -ge 5) 'cập nhật Windows'
    Dong 'Node.js (cần để cài Codex, Claude Code)' ([bool](Get-Command node -ErrorAction SilentlyContinue)) 'cài từ https://nodejs.org (bản LTS)'
    Dong 'Git' ([bool](Get-Command git -ErrorAction SilentlyContinue)) 'cài từ https://git-scm.com'
    Dong 'Codex CLI' ([bool](Get-Command codex -ErrorAction SilentlyContinue)) 'npm install -g @openai/codex'
    Dong 'Claude Code' ([bool](Get-Command claude -ErrorAction SilentlyContinue)) 'npm install -g @anthropic-ai/claude-code'
    Dong 'WezTerm' ([bool]$WEZ) 'cài từ https://wezterm.org (bản Windows)'
    Dong 'WezTerm đang mở' ($WEZ -and (Noi-Wez)) 'mở WezTerm rồi chạy lại'
    Dong 'Đã có cấu hình' ([bool]$C) 'doi-ca cai'
    if ($C) {
        Dong "Thư mục dự án $($C.thuMucDuAn)" (Test-Path $C.thuMucDuAn) 'sửa thuMucDuAn trong cấu hình'
        foreach ($tk in $C.taiKhoan) { Dong "$($tk.ten): đăng nhập" (Codex-Status $tk.thuMuc) "doi-ca dang-nhap $($tk.so)" }
        foreach ($p in $C.duAn.PSObject.Properties) { Dong "Dự án $($p.Name) có thư mục" (Test-Path (Join-Path $C.thuMucDuAn $p.Name)) 'tạo thư mục hoặc sửa tên trong cấu hình' }
    }
    Write-Host $(if ($script:ok) { "`n✅ Máy đã sẵn sàng. Thử ngay:  doi-ca mo-phong`n" } else { "`n👉 Sửa các dòng ❌ ở trên rồi chạy lại:  doi-ca kiem-tra`n" })
}

# ───────────────────────── cài đặt lần đầu ─────────────────────────
function Cai {
    Write-Host "`nCài Đội AI trực ca — trả lời vài câu (Enter = dùng gợi ý trong ngoặc)`n" -ForegroundColor Cyan
    $goc = Read-Host 'Thư mục chứa các dự án của bạn (C:\AI)'; if (-not $goc) { $goc = 'C:\AI' }
    New-Item -ItemType Directory -Force -Path $goc | Out-Null
    $n = Read-Host 'Bạn có mấy tài khoản ChatGPT dùng Codex (1)'; if (-not ($n -match '^\d+$')) { $n = 1 }; $n = [int]$n
    $tks = @(); $duAn = [ordered]@{}
    $dsDuAn = @(Get-ChildItem $goc -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^[._]' } | ForEach-Object Name)
    for ($i = 1; $i -le $n; $i++) {
        $mail = Read-Host "Gmail của tài khoản Codex $i (để nhớ khi đăng nhập lại, không cần mật khẩu)"
        $da = Read-Host "Tài khoản $i làm dự án nào (tên thư mục trong $goc$(if ($dsDuAn) { ': ' + ($dsDuAn -join ', ') }))"
        $tks += [ordered]@{ so = $i; ten = "Codex-$i$(if ($da) { ' · ' + $da })"; gmail = $mail; thuMuc = (Join-Path $env:USERPROFILE ".codex-tk$i") }
        if ($da) { $duAn[$da] = $i }
    }
    $cfg = [ordered]@{ thuMucDuAn = $goc; wezterm = $WEZ; lenhClaude = 'claude --permission-mode auto'; ntfy = ''
        taiKhoan = $tks; duAn = $duAn; nguong = [ordered]@{ nhac = 10; tra = 30; kiemLaiPhut = 30; quetPhut = 2 } }
    Luu-CauHinh $cfg; $script:C = Doc-CauHinh
    Write-Host "`n✅ Đã lưu cấu hình: $CFG (sửa tay được bằng Notepad)" -ForegroundColor Green
    foreach ($tk in $C.taiKhoan) {
        Chuan-Bi-Home $tk.thuMuc
        if (-not (Codex-Status $tk.thuMuc)) { if ($KhongHoi -or (Read-Host "Đăng nhập $($tk.ten) ngay? (C/k)") -notmatch '^[kKnN]') { Dang-Nhap $tk.so } }
    }
    Kiem-Tra
}

# ───────────────────────── mô phỏng (tự kiểm chứng) ─────────────────────────
function Mo-Phong {
    Can-CauHinh; if (-not (Noi-Wez)) { Write-Host '❌ Mở WezTerm trước rồi chạy lại (trong WezTerm).' -ForegroundColor Red; return }
    $ten = '_doi-ca-thu'; $thu = Join-Path (Goc-DuAn) $ten; $kq = [ordered]@{}
    Write-Host "`n🧪 Mô phỏng đổi ca trong dự án nháp $thu (Claude thật + Codex giả, ~3 phút)`n" -ForegroundColor Cyan
    if (Test-Path $thu) { Remove-Item -Recurse -Force $thu }
    New-Item -ItemType Directory -Path $thu | Out-Null
    Set-Content -Encoding UTF8 (Join-Path $thu 'AGENTS.md') "# Dự án nháp của doi-ca mo-phong — chỉ sửa file trong thư mục này."
    Set-Content -Encoding UTF8 (Join-Path $thu 'tien-do.md') "# Tiến độ`n## Đang dở (Codex bàn giao)`n- Việc: tạo file ket-qua.txt chứa đúng 1 dòng: Claude da thay ca`n- Bước tiếp: tạo file, ghi 1 dòng vào mục Đã xong, rồi commit. Hết việc.`n## Đã xong"
    Push-Location $thu; git init -q; git add -A; git -c user.name=doi-ca -c user.email=doi-ca@localhost commit -qm 'khoi tao' | Out-Null; Pop-Location
    $co = Join-Path $NHA 'mo-phong-co-luot.flag'; Remove-Item $co -ErrorAction SilentlyContinue
    $gia = Join-Path $NHA 'codex-gia.ps1'
    @"
`$Host.UI.RawUI.WindowTitle = '$ten | Ready | codex gia'
Write-Host 'Codex gia dang lam...'; Write-Host "You've hit your usage limit. Try again later."; Write-Host '  $ten · 5h 0% left · weekly 30% left'
while (`$true) { `$l = Read-Host '>'
  if (`$l -eq '/status') { if (Test-Path '$co') { Write-Host '  5h limit: [####] 100% left'; Write-Host '  Weekly limit: [###] 80% left' } else { Write-Host '  5h limit: [    ] 0% left'; Write-Host '  Weekly limit: [###] 30% left' } }
  else { Write-Host "CODEX-NHAN: `$l" } }
"@ | Set-Content -Encoding UTF8 $gia
    $fake = "$(W spawn --cwd $thu -- powershell -NoLogo -NoExit -ExecutionPolicy Bypass -File $gia)".Trim(); Start-Sleep 4
    Remove-Item (Join-Path $TT "$fake.json") -ErrorAction SilentlyContinue

    Write-Host '1/3 Codex giả báo hết lượt → quét... (thư mục nháp mới nên Claude sẽ hỏi "tin thư mục?" — mô phỏng tự bấm Có)'
    Quet -KiemLaiPhut 0
    $ca = Lay-Ca $fake; $cl = if ($ca) { $ca.claude } else { '' }
    $kq['Hết lượt → mở Claude'] = [bool]$cl
    if ($cl) {
        if ((Trang-Claude $cl) -eq 'hoi' -and ((Doc-O $cl 25) -join ' ') -match '(?i)trust this folder') {   # chỉ dự án nháp: tự chọn "tin thư mục"
            W send-text --pane-id $cl --no-paste "$([char]27)[B" | Out-Null; Start-Sleep -Milliseconds 400; W send-text --pane-id $cl --no-paste "`r" | Out-Null
        }
        Write-Host '2/3 Đợi Claude làm tiếp việc dở...'
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt 360 -and -not ((Test-Path (Join-Path $thu 'ket-qua.txt')) -and @(git -C $thu log --oneline).Count -ge 2 -and (Trang-Claude $cl) -eq 'ranh')) { Start-Sleep 5 }
        $kq['Claude làm tiếp + commit'] = (Test-Path (Join-Path $thu 'ket-qua.txt')) -and @(git -C $thu log --oneline).Count -ge 2
        Write-Host '3/3 Codex giả có lượt lại → quét...'
        New-Item $co -Force | Out-Null
        Quet -KiemLaiPhut 0
        $ca = Lay-Ca $fake
        $kq['Trả ca cho Codex'] = $ca -and $ca.ca -eq 'codex'
        Start-Sleep 3
        $kq['Codex nhận lời bàn giao'] = ((Doc-O $fake 10) -join ' ') -match 'CODEX-NHAN: Claude'
        $kq['Claude ghi bàn giao + commit'] = @(git -C $thu log --oneline).Count -ge 3
        Quet -KiemLaiPhut 0; $ca = Lay-Ca $fake
        $kq['Không đổi ca lặp lại'] = $ca -and $ca.ca -eq 'codex'
        W kill-pane --pane-id $cl | Out-Null
    }
    W kill-pane --pane-id $fake | Out-Null
    Remove-Item (Join-Path $TT "$fake.json"), $co, $gia -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $thu -ErrorAction SilentlyContinue
    Write-Host "`n── Kết quả mô phỏng ──" -ForegroundColor Cyan
    $kq.GetEnumerator() | ForEach-Object { Write-Host ("  {0} {1}" -f $(if ($_.Value) { '✅' } else { '❌' }), $_.Key) }
    Write-Host $(if (@($kq.Values | Where-Object { -not $_ }).Count -eq 0) { "`n🎉 Đạt. Bật trực ca thật:  doi-ca bat`n" } else { "`n👉 Có bước chưa đạt — xem nhật ký: $LOG`n" })
}

# ───────────────────────── lệnh ─────────────────────────
switch ($Lenh) {
    'cai' { Cai }
    'kiem-tra' { Kiem-Tra }
    'tai-khoan' { Bang-TaiKhoan }
    'dang-nhap' { Dang-Nhap $Thu1 }
    'codex' { Mo-Codex $Thu1 }
    'thu' { Can-CauHinh; if (Noi-Wez) { Quet -ChiXem } else { Write-Host '❌ WezTerm chưa mở' } }
    'mo-phong' { Mo-Phong }
    'chay' { Can-CauHinh; $p = Ng 'quetPhut' 2; Ghi "▶️ Bật trực ca (quét mỗi $p phút)"
        while ($true) { if (Noi-Wez) { try { Quet } catch { Ghi "❌ Lỗi: $($_.Exception.Message)" } }; Start-Sleep -Seconds ($p * 60) } }
    'bat' { Can-CauHinh; if (-not (Noi-Wez)) { Write-Host '❌ Mở WezTerm trước.'; break }
        $f = Join-Path $NHA 'o-truc.txt'
        if ((Test-Path $f) -and (Con-Mo (Get-Content $f))) { Write-Host "Trực ca đang chạy ở ô $(Get-Content $f)."; break }
        $id = "$(W spawn -- powershell -NoLogo -NoExit -ExecutionPolicy Bypass -File $PSCommandPath chay)".Trim()
        W set-tab-title --pane-id $id '🔁 Trực ca' | Out-Null; Set-Content $f $id
        Write-Host "✅ Đã bật trực ca ở tab nền '🔁 Trực ca' (ô $id). Tắt: doi-ca tat" }
    'tat' { $f = Join-Path $NHA 'o-truc.txt'; if ((Test-Path $f) -and (Noi-Wez)) { W kill-pane --pane-id (Get-Content $f) | Out-Null; Remove-Item $f; Ghi '⏹️ Tắt trực ca' } else { Write-Host 'Trực ca đang không chạy.' } }
    'xem' { $f = Join-Path $NHA 'o-truc.txt'; $bat = (Test-Path $f) -and (Noi-Wez) -and (Con-Mo (Get-Content $f))
        Write-Host $(if ($bat) { "🔁 Trực ca: ĐANG BẬT (ô $(Get-Content $f))" } else { '🔁 Trực ca: đang tắt' })
        Get-ChildItem $TT -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object { $o = Get-Content -Raw $_.FullName | ConvertFrom-Json
            Write-Host ("  Ô Codex {0} · {1} · đang ca: {2}{3}" -f $_.BaseName, $o.duAn, $o.ca, $(if ($o.ca -eq 'claude') { " (Claude ô $($o.claude))" })) }
        if (Test-Path $LOG) { Write-Host '── Nhật ký ──'; Get-Content $LOG -Tail 15 -Encoding UTF8 } }
    default {
        Write-Host @"

Đội AI trực ca — doi-ca <lệnh>
  cai          Cài lần đầu: hỏi thư mục dự án, số tài khoản Codex, Gmail, rồi đăng nhập từng tài khoản
  kiem-tra     Soát máy: Node, Git, Codex, Claude, WezTerm, đăng nhập… thiếu gì chỉ cách sửa
  tai-khoan    Bảng các tài khoản Codex: Gmail, dự án, còn đăng nhập không
  dang-nhap N  Đăng nhập lại tài khoản N (in sẵn Gmail phải dùng)
  codex [dự án] Mở Codex bằng đúng tài khoản của dự án
  mo-phong     Tự kiểm chứng đổi ca trong 3 phút (Claude thật + Codex giả)
  thu          Quét 1 lần, chỉ xem: các ô Codex + lượt dùng còn lại
  bat / tat    Bật / tắt trực ca tự động (tab nền '🔁 Trực ca')
  xem          Ai đang giữ ca + nhật ký
Cấu hình: $CFG
"@
    }
}
