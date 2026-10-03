# Đẩy key trong file .env của một dự án lên 1Password (kho "Chatbot" hoặc kho tự chọn) — KHÔNG in giá trị ra màn hình.
# Người dùng tự chạy (AI không đọc file .env). Cần: app 1Password đã bật Settings → Developer → "Integrate with 1Password CLI".
# Dùng:  E:\AI\Hion\cai-dat\env-len-1password.ps1 -File E:\AI\Chatbot\.env [-Vault Chatbot] [-Ten "Chatbot .env"]
# Kết quả: 1 mục (Secure Note / API Credential) tên "<Ten>", mỗi dòng KEY=giá trị thành 1 trường mật (concealed).
# Sau đó agent lấy key bằng: op read "op://Chatbot/Chatbot .env/BOTCAKE_TOKEN"  (1Password hỏi vân tay/mật khẩu mỗi phiên)
param(
    [Parameter(Mandatory)][string]$File,
    [string]$Vault = 'Chatbot',
    [string]$Ten
)
if (-not (Test-Path $File)) { Write-Host "Không thấy file $File" -ForegroundColor Red; exit 1 }
if (-not $Ten) { $Ten = "$(Split-Path (Split-Path $File -Parent) -Leaf) .env" }
if (-not (Get-Command op -ErrorAction SilentlyContinue)) { Write-Host 'Chưa có lệnh op (1Password CLI). Mở terminal mới rồi chạy lại.' -ForegroundColor Red; exit 1 }

# Kho chưa có thì tạo
op vault get $Vault *> $null
if ($LASTEXITCODE -ne 0) { op vault create $Vault | Out-Null; Write-Host "📁 Đã tạo kho $Vault" }

$fields = @()
$ten_key = @()
foreach ($line in Get-Content $File -Encoding UTF8) {
    if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
    $k, $v = $line -split '=', 2
    $k = $k.Trim(); $v = $v.Trim().Trim('"').Trim("'")
    if (-not $k -or -not $v) { continue }
    $fields += "$k[password]=$v"
    $ten_key += $k
}
if (-not $fields.Count) { Write-Host 'File không có key nào có giá trị.' -ForegroundColor Yellow; exit 0 }

op item get $Ten --vault $Vault *> $null
if ($LASTEXITCODE -eq 0) {
    op item edit $Ten --vault $Vault @fields | Out-Null
    $viec = 'Cập nhật'
} else {
    op item create --category 'API Credential' --title $Ten --vault $Vault @fields | Out-Null
    $viec = 'Tạo'
}
if ($LASTEXITCODE -ne 0) { Write-Host '❌ Lỗi khi ghi lên 1Password (chưa đăng nhập / chưa bật tích hợp CLI?)' -ForegroundColor Red; exit 1 }
Write-Host "✅ $viec mục '$Ten' trong kho $Vault với $($ten_key.Count) key: $($ten_key -join ', ')" -ForegroundColor Green
Write-Host "   Agent lấy key: op read `"op://$Vault/$Ten/<TÊN_KEY>`"   (giá trị KHÔNG in ở đây)"
Write-Host '   Giữ file .env cũ cho tới khi chắc mọi thứ chạy bằng 1Password, rồi mới xoá.'
