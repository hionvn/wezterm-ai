# mo-may-ao.ps1 — thử khoi-phuc.ps1 trên một máy Windows SẠCH (Windows Sandbox: máy ảo dùng một lần, tắt là mất hết).
# Máy ảo không có ổ E: và không có winget → kiểm tra đúng tình huống máy học viên.
# Chạy (PowerShell thường, không cần Admin):
#   powershell -ExecutionPolicy Bypass -File E:\AI\wezterm-ai\thu-cai\mo-may-ao.ps1
# Kết quả ghi vào thu-cai\ket-qua\ (log đầy đủ + tom-tat.txt). Máy thật không bị đụng tới:
# repo được gắn vào máy ảo ở chế độ chỉ đọc.
# Lần đầu phải bật Windows Sandbox (PowerShell chạy Admin, xong khởi động lại máy):
#   Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All
$repo = Split-Path $PSScriptRoot -Parent
$out = Join-Path $PSScriptRoot 'ket-qua'
New-Item -ItemType Directory -Force -Path $out | Out-Null
if (-not (Test-Path "$env:windir\System32\WindowsSandbox.exe")) {
    Write-Host '⚠️  Chưa bật Windows Sandbox. Mở PowerShell bằng quyền Admin, chạy lệnh dưới rồi khởi động lại máy:' -ForegroundColor Yellow
    Write-Host '   Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All'
    exit 1
}
$box = 'C:\Users\WDAGUtilityAccount\Desktop'
$wsb = @"
<Configuration>
  <MappedFolders>
    <MappedFolder><HostFolder>$repo</HostFolder><SandboxFolder>$box\wezterm-ai-goc</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>$out</HostFolder><SandboxFolder>$box\ket-qua</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>powershell.exe -ExecutionPolicy Bypass -File $box\wezterm-ai-goc\thu-cai\chay-thu.ps1</Command>
  </LogonCommand>
</Configuration>
"@
$f = Join-Path $out 'may-ao.wsb'
[IO.File]::WriteAllText($f, $wsb, (New-Object Text.UTF8Encoding $false))
Write-Host "Đang mở máy ảo… chạy xong (khoảng 1-2 phút) xem: $out\tom-tat.txt" -ForegroundColor Cyan
Start-Process $f
