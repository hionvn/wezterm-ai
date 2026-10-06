# Dọn Chrome chạy ẩn (headless) bị AI bỏ quên — 06/10/2026: 75 bản từ 04/10 ăn ~17 GB bộ nhớ, đẩy máy tới trần
# + làm WezTerm hỏi tiến trình chậm (1.295 tiến trình). Chỉ đóng Chrome ẩn của Google Chrome, chạy > 1 giờ, chương trình mở nó đã tắt.
# Không đụng Chrome thường, GPM-Login. Gọi tay: powershell -File don-chrome-an.ps1   (-Thu = chỉ liệt kê)
param([switch]$Thu)
$all = Get-CimInstance Win32_Process
$alive = @{}; $all | ForEach-Object { $alive[$_.ProcessId] = $true }
$cut = (Get-Date).AddHours(-1)
$roots = @($all | Where-Object { $_.Name -eq 'chrome.exe' -and $_.CommandLine -match '--headless' -and $_.CommandLine -notmatch '--type=' -and
  $_.ExecutablePath -like 'C:\Program Files\Google\Chrome\*' -and $_.CreationDate -lt $cut -and -not $alive[$_.ParentProcessId] })
if (-not $Thu) { foreach ($r in $roots) { taskkill /PID $r.ProcessId /T /F *> $null } }
"$(Get-Date -Format 'yyyy-MM-dd HH:mm') don-chrome-an: $($roots.Count) Chrome ẩn mồ côi$(if ($Thu) { ' (thử, chưa đóng)' } else { ' đã đóng' })"
