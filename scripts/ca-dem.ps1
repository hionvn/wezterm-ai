# Ca đêm của đội agent (theo night plan thầy Sơn, BTO buổi 8) — Task Scheduler gọi theo giờ:
#   lap 22:00 · p1 23:00 · p2 01:00 · p3 03:00 · p4 05:00 · tongket 06:15
#   lap/tongket gửi cho 👑 Tổng quản (ô ghi trong %LOCALAPPDATA%\wez-ai\doi\Hion.json);
#   p1–p4 gửi cho Manager các dự án có trong kế hoạch đêm E:\AI\Hion\ca-dem\<ngày>.json {"du_an":[...]}.
# Chỉ việc 🟢 (luật: E:\AI\Hion\quy-trinh-lien-mach.md mục 9). Không push, không tiền, không gửi ra ngoài.
# Bật/tắt: "caDem": true|false trong ~\.wez-ai.json (mặc định tắt). Thử tay: ca-dem.ps1 p1 -Thu (chỉ in, không gửi).
# Nhật ký: E:\AI\Hion\ca-dem\nhat-ky-<ngày>.md
param([Parameter(Mandatory)][ValidateSet('lap', 'p1', 'p2', 'p3', 'p4', 'tongket')][string]$Pha, [switch]$Thu)

$HUB = 'E:\AI\Hion'
$WEZ = Join-Path $HUB 'cai-dat\wez.ps1'
$dir = Join-Path $HUB 'ca-dem'
New-Item -ItemType Directory -Force $dir | Out-Null
# "Ngày ca" = ngày bắt đầu ca lúc 22:00 (qua nửa đêm vẫn tính ngày hôm trước)
$now = Get-Date
$ngay = if ($now.Hour -lt 12) { $now.AddDays(-1).ToString('yyyy-MM-dd') } else { $now.ToString('yyyy-MM-dd') }
$sang = ([datetime]$ngay).AddDays(1).ToString('yyyy-MM-dd')
$log = Join-Path $dir "nhat-ky-$ngay.md"
function Ghi($s) { $l = "- $(Get-Date -Format 'HH:mm:ss') [$Pha] $s"; Add-Content -Path $log -Value $l -Encoding UTF8; Write-Host $l }

$cfg = $null; try { $cfg = Get-Content (Join-Path $HOME '.wez-ai.json') -Raw | ConvertFrom-Json } catch {}
if (-not $Thu -and -not ($cfg -and $cfg.caDem)) { Ghi 'caDem đang tắt trong ~\.wez-ai.json → bỏ qua'; exit 0 }

# Hạn mức Claude 5 giờ ≥ 85% → không giao thêm (để dành cho ban ngày)
try {
    $f = Get-Content (Join-Path $env:LOCALAPPDATA 'wez-ai\fuel-claude.json') -Raw | ConvertFrom-Json
    if ($f.five -ge 85 -and $Pha -ne 'tongket') { Ghi "Hạn mức Claude 5 giờ đang $($f.five)% → bỏ pha này"; exit 0 }
} catch {}

$luat = 'Luật: E:\AI\Hion\quy-trinh-lien-mach.md mục 9 (ca đêm). CHỈ việc 🟢; việc 🔴 → duyet.js them rồi làm việc khác; không push, không deploy, không tiền, không gửi ra ngoài; 1Password đêm không có người mở khoá → việc cần key để sáng.'
$loi = @{
    lap     = "🌙 CA ĐÊM $ngay — LẬP KẾ HOẠCH (22:00). Đọc E:\AI\Hion\brain\hom-nay.md (Company Brain gom lúc 21:55: tiến độ, kẹt, cần duyệt, việc ☐ mọi dự án) — cần chi tiết mới mở brain\du-an\<DựÁn>.md. Chọn việc 🟢 đã rõ cho đêm nay (mỗi dự án ≤ 3, ưu tiên việc ra tiền). Ghi E:\AI\Hion\ca-dem\$ngay.md (bảng: dự án · việc · Xong khi · ai làm) và E:\AI\Hion\ca-dem\$ngay.json dạng {`"du_an`":[`"Chatbot`",…]}. Tạo ticket Linear cho từng việc: node E:\AI\Hion\cai-dat\linear.js tao <DựÁn> `"tiêu đề`" (lỗi 1Password thì nó tự xếp hàng, sáng đồng bộ). CHƯA giao — 23:00 các Manager tự nhận. $luat"
    p1      = "🌙 CA ĐÊM $ngay · PHA 1 (23:00–01:00) LÀM: đọc E:\AI\Hion\ca-dem\$ngay.md phần dự án của bạn, giao worker theo brief 6 mục, chạy tới xong, commit cục bộ. $luat"
    p2      = "🌙 CA ĐÊM $ngay · PHA 2 (01:00–03:00) NGHIÊN CỨU / NHÁP: làm nốt việc pha 1, rồi việc nghiên cứu, đối soát số liệu, viết nháp trong kế hoạch. $luat"
    p3      = "🌙 CA ĐÊM $ngay · PHA 3 (03:00–05:00) SOÁT CHÉO: cho Security/Kiểm soát soát mọi thay đổi từ 22:00 (git log --since=`"$ngay 22:00`"); việc code thì soát chéo Claude↔Codex (wez.ps1 review <dự án>); lỗi mức cao sửa ngay. Người làm không tự duyệt. $luat"
    p4      = "🌙 CA ĐÊM $ngay · PHA 4 (05:00–06:15) TEST + BÁO CÁO: chạy kiểm thử của dự án; cập nhật tien-do; ghi E:\AI\Hion\ca-dem\$ngay-<DựÁn>.md — mỗi việc 5 trường (Đầu ra · Xong chưa · Bằng chứng · Còn lại · Ai làm tiếp) + 'Đã tự chọn'; chuyển ticket: node E:\AI\Hion\cai-dat\linear.js xong|dang <HIO-x>. $luat"
    tongket = "☀️ CA ĐÊM $ngay — TỔNG KẾT + EVAL (06:15). 1) node E:\AI\Hion\cai-dat\eval-dem.js $ngay (ra learn\so-lieu-$ngay.json + learn\eval-$ngay.md phần số). 2) node E:\AI\Hion\cai-dat\brain.js rồi đọc brain\hom-nay.md + ca-dem\$ngay-*.md + nhat-ky-$ngay.md, viết E:\AI\Hion\ca-dem\bao-cao-$sang.md (≤ 1 trang: ✅ đã xong · 🧱 kẹt · 🔔 cần Hion · số liệu) — báo cáo sáng tự gắn vào. 3) Bổ sung learn\eval-$ngay.md: mỗi agent đúng đề không, bị trả lại không, lỗi gì; bài học mới → learn\bai-hoc.md (đếm số lần gặp); bài học gặp ≥ 2 lần → đề xuất đóng thành skill bằng duyet.js them Hion. 4) node E:\AI\Hion\cai-dat\linear.js dong-bo. $luat"
}

function Gui($dich, $text) {
    if ($Thu) { Ghi "THỬ → $dich : $text"; return }
    # Ô đang bận thì đợi (tối đa 20 phút, 60 giây hỏi một lần), quá thì vẫn gửi (-Ep: Claude xếp tin vào hàng chờ)
    for ($i = 0; $i -lt 20; $i++) {
        & $WEZ send $dich $text *> $null
        if ($LASTEXITCODE -ne 3) { break }
        Start-Sleep 60
    }
    if ($LASTEXITCODE -eq 3) { & $WEZ send $dich $text -Ep *> $null }
    if ($LASTEXITCODE -eq 0) { Ghi "đã giao → $dich" } else {
        # Manager chưa mở → mở đội rồi gửi lại
        Ghi "$dich chưa mở (mã $LASTEXITCODE) → mở đội rồi gửi lại"
        & $WEZ doi ($dich -split '\.')[0] *> $null; Start-Sleep 25
        & $WEZ send $dich $text -Ep *> $null
        if ($LASTEXITCODE -eq 0) { Ghi "đã giao → $dich (sau khi mở đội)" } else { Ghi "❌ không giao được → $dich" }
    }
}

if ($Pha -in 'lap', 'tongket') { Gui 'Hion.TongQuan' $loi[$Pha]; exit 0 }

$ke = Join-Path $dir "$ngay.json"
if (-not (Test-Path $ke)) { Ghi "Chưa có kế hoạch $ke → bỏ pha (Tổng quản chưa lập lúc 22:00?)"; exit 0 }
$ds = @((Get-Content $ke -Raw -Encoding UTF8 | ConvertFrom-Json).du_an) | Where-Object { $_ -and (Test-Path (Join-Path 'E:\AI' $_)) }
if (-not $ds.Count) { Ghi 'Kế hoạch đêm không có dự án nào → nghỉ'; exit 0 }
foreach ($p in $ds) { Gui "$p.Manager" $loi[$Pha] }
