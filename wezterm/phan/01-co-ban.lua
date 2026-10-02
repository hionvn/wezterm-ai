-- Cài đặt WezTerm của Hion (tạo 01/10/2026).
-- Mục tiêu: dùng giống Windows Terminal (menu `ai`, chia cột, Alt+mũi tên)
-- và để AI tổng quản điều khiển các ô bằng `wezterm cli`.
local wezterm = require 'wezterm'
local act = wezterm.action
local config = wezterm.config_builder()

-- Cấu hình chung của máy (khoi-phuc.ps1 tạo): ~\.wez-ai.json = { "aiRoot": "E:\\AI", "wezterm": "...\\wezterm.exe" }
-- Không có file thì dùng mặc định bên dưới.
local HOME = os.getenv('USERPROFILE') or 'C:\\Users\\Hion'
local machine = {}
do
  local f = io.open(HOME .. '\\.wez-ai.json', 'rb')
  if f then
    local ok, v = pcall(wezterm.json_parse, (f:read('*a'):gsub('^\239\187\191', '')))
    f:close()
    if ok and type(v) == 'table' then machine = v end
  end
end
wezterm.add_to_config_reload_watch_list(HOME .. '\\.wez-ai.json') -- sửa file này là WezTerm tự nạp lại
local AI_ROOT = (machine.aiRoot or 'E:\\AI'):gsub('[\\/]+$', '')
local HUB = AI_ROOT .. '\\Hion'
local AIDIR = (os.getenv('LOCALAPPDATA') or (HOME .. '\\AppData\\Local')) .. '\\wez-ai'

-- Chạy một lệnh trong PowerShell (có nạp profile: ai, claudeRC, codex...).
-- Xoá biến CLAUDE* thừa hưởng (nếu WezTerm được mở từ trong Claude) để Claude mới vẫn lưu lịch sử.
local function PS(cmd)
  return { 'powershell.exe', '-NoLogo', '-NoExit', '-Command',
    'Get-ChildItem Env:CLAUDE* -ErrorAction SilentlyContinue | Remove-Item; ' .. cmd }
end
-- Như PS nhưng KHÔNG nạp profile (nhanh hơn ~1–2 giây/ô, 03/10) — chỉ dùng khi lệnh không cần hàm của profile
-- (claudeRC, codex chọn tài khoản…), vd ô Claude trong đội gọi thẳng `claude --resume`
local function PSN(cmd)
  return { 'powershell.exe', '-NoLogo', '-NoProfile', '-NoExit', '-Command',
    'Get-ChildItem Env:CLAUDE* -ErrorAction SilentlyContinue | Remove-Item; ' .. cmd }
end

-- Mở lên là vào menu `ai` (chọn dự án rồi chọn AI), bắt đầu ở Hion
config.default_prog = PS('ai')
config.default_cwd = HUB

-- Giao diện
config.font = wezterm.font_with_fallback { 'Cascadia Mono', 'Consolas' }
config.font_size = 11
config.initial_cols = 200
config.initial_rows = 50
config.inactive_pane_hsb = { saturation = 0.7, brightness = 0.55 } -- ô không chọn thì tối đi
config.window_close_confirmation = 'AlwaysPrompt'

-- Chia đều n cột (bấm khi tab chỉ có 1 ô)
local function cols(n)
  return wezterm.action_callback(function(_, pane)
    local p = pane
    for i = n, 2, -1 do
      p = p:split { direction = 'Right', size = (i - 1) / i }
    end
  end)
end

-- Ctrl+C: có bôi đen thì copy, không thì gửi Ctrl+C (dừng lệnh) như bình thường
local copy_or_interrupt = wezterm.action_callback(function(window, pane)
  local sel = window:get_selection_text_for_pane(pane)
  if sel ~= '' then
    window:perform_action(act.CopyTo 'Clipboard', pane)
    window:perform_action(act.ClearSelection, pane)
  else
    window:perform_action(act.SendKey { key = 'c', mods = 'CTRL' }, pane)
  end
end)
