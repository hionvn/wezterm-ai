# Task Scheduler gọi qua an.vbs (không nháy cửa sổ): chạy Company Brain. Tham số chuyển thẳng cho brain.js (vd --linear).
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine')
& node (Join-Path $PSScriptRoot 'brain.js') @args *> (Join-Path $env:LOCALAPPDATA 'wez-ai\brain-lan-cuoi.txt')
