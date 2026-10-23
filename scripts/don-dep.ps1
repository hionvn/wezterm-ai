# Dọn hệ thống mỗi giờ (08/10, TongQuanAI: "cứ khoảng 1h làm việc thì dọn dẹp hệ thống 1 lần để máy nhẹ").
# Task Scheduler "WezAI-DonDep" gọi qua an.vbs. Log: %LOCALAPPDATA%\wez-ai\don-dep.log. -Thu = chỉ liệt kê, không đóng/xoá.
# 1) Chrome ẩn (headless) của Google Chrome chạy > 30 phút — script chụp/kiểm của AI chỉ chạy vài phút; 08/10 có 111 bản
#    bị bỏ quên ăn 41,7 GB (don-chrome-an.ps1 cũ bỏ sót vì xét "chương trình mẹ còn sống" mà số tiến trình bị tái dùng).
#    Không đụng Chrome thường (không --headless), GPM-Login (đường dẫn khác).
# 2) Thư mục hồ sơ Chrome tạm trong %TEMP% (có "Local State") cũ > 2 giờ.
# 3) Báo động: bộ nhớ cam kết > 85% thì ghi CẢNH BÁO vào log.
param([switch]$Thu)
$log = Join-Path $env:LOCALAPPDATA 'wez-ai\don-dep.log'
$os0 = Get-CimInstance Win32_OperatingSystem
$cut = (Get-Date).AddMinutes(-30)
$roots = @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object {
  $_.CommandLine -match '--headless' -and $_.CommandLine -notmatch '--type=' -and
  $_.ExecutablePath -like 'C:\Program Files\Google\Chrome\*' -and $_.CreationDate -lt $cut })
if (-not $Thu) { foreach ($r in $roots) { taskkill /PID $r.ProcessId /T /F *> $null } }
$dirCut = (Get-Date).AddHours(-2); $dirs = 0; $mb = 0
Get-ChildItem $env:TEMP -Directory -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $dirCut -and (Test-Path (Join-Path $_.FullName 'Local State')) } | ForEach-Object {
  $mb += ((Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB)
  if (-not $Thu) { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
  $dirs++ }
Start-Sleep -Seconds 3
$os = Get-CimInstance Win32_OperatingSystem
$cam = ($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / 1MB; $tong = $os.TotalVirtualMemorySize / 1MB
$dong = "{0:yyyy-MM-dd HH:mm} don-dep{1}: {2} Chrome ẩn > 30 phút · {3} hồ sơ tạm ({4:N0} MB) · cam kết {5:N1} -> {6:N1}/{7:N1} GB · RAM trống {8:N1} GB · {9} tiến trình" -f (Get-Date), $(if ($Thu) { ' (thử)' } else { '' }), $roots.Count, $dirs, $mb, (($os0.TotalVirtualMemorySize - $os0.FreeVirtualMemory) / 1MB), $cam, $tong, ($os.FreePhysicalMemory / 1MB), @(Get-Process).Count
if ($cam / $tong -gt 0.85) { $dong += ' · ⚠️ CẢNH BÁO cam kết > 85%' }
Add-Content -Path $log -Value $dong -Encoding utf8
$dong
