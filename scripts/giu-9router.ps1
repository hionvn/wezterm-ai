# Canh 9router (08/10): cổng 20128 không nghe → bật lại ở nền. Task Scheduler "WezAI-9router" gọi 2 phút/lần qua an.vbs.
# Lý do: 08/10 ~08:40 9router tự tắt, ~37 worker đứng "waiting for network" tới hết hạn 30 phút.
$nghe = Get-NetTCPConnection -LocalPort 20128 -State Listen -ErrorAction SilentlyContinue
if ($nghe) { exit 0 }
$log = Join-Path $env:LOCALAPPDATA 'wez-ai\giu-9router.log'
Add-Content -Path $log -Value ("{0:yyyy-MM-dd HH:mm:ss} 9router tắt → bật lại" -f (Get-Date)) -Encoding utf8
Start-Process -FilePath "$env:APPDATA\npm\9router.cmd" -ArgumentList '-t', '-n', '--skip-update', '-H', '127.0.0.1' -WindowStyle Hidden
