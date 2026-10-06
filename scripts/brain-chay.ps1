# Task Scheduler gọi qua an.vbs (không nháy cửa sổ): chạy Company Brain. Tham số chuyển thẳng cho brain.js (vd --linear).
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine')
& (Join-Path $PSScriptRoot 'don-chrome-an.ps1') *>> (Join-Path $env:LOCALAPPDATA 'wez-ai\don-chrome-an.log') # 06/10: dọn Chrome ẩn AI bỏ quên (3 lần/ngày)
& node (Join-Path $PSScriptRoot 'brain.js') @args *> (Join-Path $env:LOCALAPPDATA 'wez-ai\brain-lan-cuoi.txt')
