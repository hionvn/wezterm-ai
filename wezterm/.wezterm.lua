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
local AI_ROOT = (machine.aiRoot or 'E:\\AI'):gsub('[\\/]+$', '')
local HUB = AI_ROOT .. '\\_Hub'
local AIDIR = (os.getenv('LOCALAPPDATA') or (HOME .. '\\AppData\\Local')) .. '\\wez-ai'

-- Chạy một lệnh trong PowerShell (có nạp profile: ai, claudeRC, codex...).
-- Xoá biến CLAUDE* thừa hưởng (nếu WezTerm được mở từ trong Claude) để Claude mới vẫn lưu lịch sử.
local function PS(cmd)
  return { 'powershell.exe', '-NoLogo', '-NoExit', '-Command',
    'Get-ChildItem Env:CLAUDE* -ErrorAction SilentlyContinue | Remove-Item; ' .. cmd }
end

-- Mở lên là vào menu `ai` (chọn dự án rồi chọn AI), bắt đầu ở _Hub
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

-- ===== Bàn làm việc Tổng quản + menu dự án (thêm 01/10/2026; bản cũ: .wezterm.lua.bak-before-giai-doan1) =====
-- Ô tài liệu bên phải: can-duyet.md + sổ tiến độ các dự án, tự vẽ lại khi file đổi
local VIEWER = { 'powershell.exe', '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
  HUB .. '\\cai-dat\\can-duyet-view.ps1' }

local function find_viewer(tab)
  for _, p in ipairs(tab:panes()) do
    if (p:get_title() or ''):find('Cần duyệt', 1, true) then return p end
  end
end

-- Ctrl+Shift+J: bật / tắt ô tài liệu cần duyệt bên cạnh ô đang chọn
local toggle_doc = wezterm.action_callback(function(window, pane)
  local v = find_viewer(window:active_tab())
  if v then
    window:perform_action(act.CloseCurrentPane { confirm = false }, v)
  else
    pane:split { direction = 'Right', size = 0.38, cwd = HUB, args = VIEWER }
  end
end)

-- Ô xem một tài liệu (tự vẽ lại khi file đổi), tiêu đề "📄 tên file"
local function DOCVIEW(path)
  return { 'powershell.exe', '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
    HUB .. '\\cai-dat\\can-duyet-view.ps1', '-File', path }
end
local function is_doc(p) return (p:get_title() or ''):find('📄', 1, true) ~= nil end

-- AI gọi cai-dat\mo-tai-lieu.js → wez-ai\open.json → mở ô 📄 bên phải tab đang xem (thay ô 📄 cũ)
local function process_open(window)
  local req_path = AIDIR .. '\\open.json'
  local f = io.open(req_path, 'rb')
  if not f then return end
  local s = f:read('*a')
  f:close()
  os.remove(req_path)
  local ok, req = pcall(wezterm.json_parse, s)
  if not ok or not req or not req.path then return end
  local tab, cur = window:active_tab(), window:active_pane()
  for _, p in ipairs(tab:panes()) do
    if is_doc(p) then
      if p:pane_id() == cur:pane_id() then cur = nil end
      window:perform_action(act.CloseCurrentPane { confirm = false }, p)
    end
  end
  if not cur then
    for _, p in ipairs(tab:panes()) do if not is_doc(p) then cur = p break end end
  end
  if not cur then return end
  local doc = cur:split { direction = 'Right', size = 0.42, cwd = HUB, args = DOCVIEW(req.path) }
  local docs = wezterm.GLOBAL.docs or {} -- nhớ ô 📄 nào xem file nào (để lưu / khôi phục bố cục)
  docs[tostring(doc:pane_id())] = req.path
  wezterm.GLOBAL.docs = docs
  cur:activate() -- giữ con trỏ ở ô bạn đang gõ
  window:toast_notification('WezTerm · đội AI', '📄 Đã mở tài liệu: ' .. (req.path:match('([^\\/]+)$') or req.path), nil, 5000)
end

-- Chuyển ô giữa tab chính và tab nền (giống anh Sơn đẩy agent ra tab phụ)
local WEZ_EXE = machine.wezterm or 'C:\\Program Files\\WezTerm\\wezterm.exe'
local SOCK = HOME .. '\\.local\\share\\wezterm\\gui-sock-' .. wezterm.procinfo.pid()

-- Ctrl+Shift+B: đẩy ô đang chọn ra một tab nền riêng, màn hình vẫn ở tab hiện tại
local push_bg = wezterm.action_callback(function(window, pane)
  local tab = window:active_tab()
  if #tab:panes() < 2 then return end -- tab chỉ còn 1 ô thì không đẩy
  pane:move_to_new_tab()
  tab:activate()
end)

-- Ctrl+Shift+G: chọn một ô ở tab khác rồi kéo về bên phải ô đang chọn
local pull_menu = wezterm.action_callback(function(window, pane)
  local choices, cur_tab = {}, window:active_tab():tab_id()
  for i, tab in ipairs(window:mux_window():tabs()) do
    if tab:tab_id() ~= cur_tab then
      for _, p in ipairs(tab:panes()) do
        local cwd = p:get_current_working_dir()
        local dir = cwd and (cwd.file_path or tostring(cwd)) or ''
        local proj = dir:gsub('[\\/]+$', ''):match('([^\\/]+)$') or '?'
        table.insert(choices, { id = tostring(p:pane_id()),
          label = 'Tab ' .. i .. '  ·  ' .. proj .. '  ·  ' .. (p:get_title() or '') })
      end
    end
  end
  if #choices == 0 then
    window:toast_notification('WezTerm', 'Không có ô nào ở tab khác để kéo về', nil, 3000)
    return
  end
  window:perform_action(act.InputSelector {
    title = 'Kéo ô nào về tab này?  (Enter chọn · Esc thoát)',
    choices = choices,
    fuzzy = true,
    action = wezterm.action_callback(function(_, p, id)
      if not id then return end
      wezterm.background_child_process { 'powershell.exe', '-NoProfile', '-Command',
        "$env:WEZTERM_UNIX_SOCKET='" .. SOCK .. "'; & '" .. WEZ_EXE .. "' cli split-pane --pane-id "
          .. p:pane_id() .. ' --right --percent 50 --move-pane-id ' .. id }
    end),
  }, pane)
end)

-- Ctrl+Shift+H: tab mới "Tổng quản" = Claude ở _Hub bên trái + ô tài liệu cần duyệt bên phải
local open_desk = wezterm.action_callback(function(window, _)
  local tab, p = window:mux_window():spawn_tab { cwd = HUB, args = PS('claudeRC') }
  p:split { direction = 'Right', size = 0.38, cwd = HUB, args = VIEWER }
  tab:set_title('Tổng quản')
  p:activate()
end)

-- Ctrl+Shift+A: chọn dự án + AI từ danh sách, rồi chọn mở ở ô phải / ô dưới / tab mới
local AIS = { { '🤖 Claude', 'claudeRC' }, { '🧩 Codex', 'codex' }, { '💎 Gemini', 'gemini' } }
local function projects()
  local t = {}
  for _, path in ipairs(wezterm.read_dir(AI_ROOT)) do
    local n = path:match('([^\\/]+)$')
    if n and not n:find('.', 1, true) then table.insert(t, n) end -- bỏ file, chỉ lấy thư mục
  end
  table.sort(t)
  return t
end
local project_menu = wezterm.action_callback(function(window, pane)
  local choices = {}
  for _, proj in ipairs(projects()) do
    for i, a in ipairs(AIS) do
      table.insert(choices, { id = proj .. '|' .. i, label = proj .. '   ·   ' .. a[1] })
    end
  end
  window:perform_action(act.InputSelector {
    title = 'Mở dự án + AI  (gõ để lọc · Enter chọn · Esc thoát)',
    choices = choices,
    fuzzy = true,
    action = wezterm.action_callback(function(win, p, id)
      if not id then return end
      local proj, i = id:match('^(.-)|(%d+)$')
      local a, dir = AIS[tonumber(i)], AI_ROOT .. '\\' .. proj
      win:perform_action(act.InputSelector {
        title = proj .. ' · ' .. a[1] .. '  →  mở ở đâu?',
        choices = { { id = 'Right', label = '➡  Ô bên phải' }, { id = 'Bottom', label = '⬇  Ô bên dưới' },
          { id = 'tab', label = '🗂  Tab mới' } },
        action = wezterm.action_callback(function(w2, p2, where)
          if not where then return end
          if where == 'tab' then
            local t = w2:mux_window():spawn_tab { cwd = dir, args = PS(a[2]) }
            t:set_title(proj)
          else
            p2:split { direction = where, cwd = dir, args = PS(a[2]) }
          end
        end),
      }, p)
    end),
  }, pane)
end)

local save_layout, restore_menu -- định nghĩa ở mục "Lưu / khôi phục bố cục" bên dưới

config.keys = {
  -- Bàn làm việc Tổng quản, ô cần duyệt, menu dự án
  { key = 'H', mods = 'CTRL|SHIFT', action = open_desk },
  { key = 'J', mods = 'CTRL|SHIFT', action = toggle_doc },
  { key = 'A', mods = 'CTRL|SHIFT', action = project_menu },
  -- Đẩy ô ra tab nền / kéo ô ở tab khác về
  { key = 'B', mods = 'CTRL|SHIFT', action = push_bg },
  { key = 'G', mods = 'CTRL|SHIFT', action = pull_menu },
  -- Lưu bố cục / mở lại bố cục đã lưu (hàm ở mục "Lưu / khôi phục bố cục" bên dưới)
  { key = 'S', mods = 'CTRL|SHIFT', action = wezterm.action_callback(function(w, p) w:perform_action(save_layout, p) end) },
  { key = 'O', mods = 'CTRL|SHIFT', action = wezterm.action_callback(function(w, p) w:perform_action(restore_menu, p) end) },
  -- Chia ô
  { key = 'D', mods = 'ALT|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = '_', mods = 'ALT|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = '@', mods = 'ALT|SHIFT', action = cols(2) },
  { key = '#', mods = 'ALT|SHIFT', action = cols(3) },
  { key = '$', mods = 'ALT|SHIFT', action = cols(4) },
  { key = '2', mods = 'ALT|SHIFT', action = cols(2) },
  { key = '3', mods = 'ALT|SHIFT', action = cols(3) },
  { key = '4', mods = 'ALT|SHIFT', action = cols(4) },
  -- Chuyển ô: Alt + mũi tên
  { key = 'LeftArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Left' },
  { key = 'RightArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Right' },
  { key = 'UpArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Up' },
  { key = 'DownArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Down' },
  -- Chỉnh kích thước ô: Alt + Shift + mũi tên (hoặc kéo chuột ở đường ranh)
  { key = 'LeftArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Left', 5 } },
  { key = 'RightArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Right', 5 } },
  { key = 'UpArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Up', 3 } },
  { key = 'DownArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Down', 3 } },
  -- Phóng to / thu nhỏ ô đang chọn
  { key = 'Z', mods = 'CTRL|SHIFT', action = act.TogglePaneZoomState },
  -- Đóng ô đang chọn (có hỏi lại)
  { key = 'W', mods = 'CTRL|SHIFT', action = act.CloseCurrentPane { confirm = true } },
  -- Copy / dán giống Windows
  { key = 'c', mods = 'CTRL', action = copy_or_interrupt },
  { key = 'v', mods = 'CTRL', action = act.PasteFrom 'Clipboard' },
}

-- Chuột phải = dán (giống Windows Terminal)
config.mouse_bindings = {
  { event = { Down = { streak = 1, button = 'Right' } }, mods = 'NONE', action = act.PasteFrom 'Clipboard' },
}

-- ===== Thanh trạng thái (thêm 01/10/2026; bản cũ: .wezterm.lua.bak-before-statusbar) =====
-- Tên tab: số · biểu tượng AI · dự án (màu theo dự án, giống thanh trạng thái Claude)
-- Góc phải: AI · dự án › thư mục con · 🌿 nhánh git · số ô · giờ, ngày
config.use_fancy_tab_bar = false
config.tab_max_width = 32
config.status_update_interval = 2000

local proj_colors = { _hub = '#e5c07b', sino = '#e06c75', coolguy = '#61afef', chatbot = '#c678dd' }
local palette = { '#56b6c2', '#98c379', '#d19a66', '#c678dd', '#61afef' }
local function proj_color(name)
  local c = proj_colors[name:lower()]
  if c then return c end
  local h = 0
  for i = 1, #name do h = (h * 31 + name:byte(i)) % 1000003 end
  return palette[h % #palette + 1]
end

-- Lấy đường dẫn thư mục của ô (dạng E:\AI\Sino\...)
local function pane_dir(p)
  local cwd = p.current_working_dir
  if cwd == nil then return nil end
  local s = type(cwd) == 'userdata' and (cwd.file_path or tostring(cwd)) or tostring(cwd)
  s = s:gsub('^file://[^/]*', ''):gsub('^/(%a:)', '%1'):gsub('/', '\\'):gsub('\\$', '')
  return s
end

-- Dự án = thư mục ngay dưới AI_ROOT (E:\AI) ; phần sau là thư mục con
local ROOT_PREFIX = AI_ROOT:lower() .. '\\'
local function split_project(dir)
  if not dir then return '?', nil end
  if dir:lower():sub(1, #ROOT_PREFIX) == ROOT_PREFIX then
    local proj, rest = dir:sub(#ROOT_PREFIX + 1):match('^([^\\]+)\\?(.*)$')
    if proj then return proj, (rest ~= '' and rest or nil) end
  end
  return dir:match('([^\\]+)$') or dir, nil
end

-- AI nào đang chạy trong ô (dựa vào tiến trình + tiêu đề)
local function which_ai(p)
  local s = ((p.foreground_process_name or '') .. ' ' .. (p.title or '')):lower()
  if s:find('codex') then return '🧩', 'Codex' end
  if s:find('gemini') or s:find('◇') or s:find('✦') or s:find('✋') then return '💎', 'Gemini' end
  if s:find('claude') or s:find('✳') or s:find('◐') or s:find('◓') or s:find('◑') or s:find('◒') then return '🤖', 'Claude' end
  if s:find('powershell') or s:find('pwsh') then return '⌨️', 'PowerShell' end
  return '▪️', nil
end

-- Nhánh git: đọc thẳng file .git\HEAD (không chạy lệnh git nên không chậm)
local function git_branch(dir)
  local d = dir
  while d and d ~= '' do
    local f = io.open(d .. '\\.git\\HEAD', 'r')
    if f then
      local head = f:read('*l') or ''
      f:close()
      return head:match('ref: refs/heads/(.+)') or head:sub(1, 7)
    end
    local parent = d:match('^(.*)\\[^\\]+$')
    if parent == nil or parent == d then break end
    d = parent
  end
  return nil
end

-- ===== Báo động + đồng hồ nhiên liệu (thêm 01/10/2026) =====
local function read_file(path, tail)
  local f = io.open(path, 'rb')
  if not f then return nil end
  if tail then
    local size = f:seek('end')
    f:seek('set', math.max(0, size - tail))
  end
  local s = f:read('*a')
  f:close()
  return s
end
local function read_json(path)
  local s = read_file(path)
  if not s or s == '' then return nil end
  local ok, v = pcall(wezterm.json_parse, s)
  return ok and v or nil
end

-- Báo động: Claude ghi file qua hooks (cai-dat\wez-alert.js); Codex, Gemini thì đoán từ tiêu đề ô.
-- File: %LOCALAPPDATA%\wez-ai\alerts\<PANEID>.json = { kind = 'need' | 'done', text, t }
-- Trạng thái (cho wez.ps1 send / cho): wez-ai\state\<PANEID>.json = { state = 'work' | 'idle' | 'need', ai, t }
local ALERTS = AIDIR .. '\\alerts'
local STATE = AIDIR .. '\\state'
local tab_alert, toasted, last_state = {}, {}, {}
local function write_alert(id, kind, text)
  local f = io.open(ALERTS .. '\\' .. id .. '.json', 'w')
  if f then
    f:write(string.format('{"kind":"%s","text":"%s","t":%d}', kind, text, os.time()))
    f:close()
  end
end

-- Đồng bộ file trạng thái với điều đoán được từ tiêu đề ô.
-- wez.ps1 send vừa ghi 'work' thì để yên 10 giây (AI chưa kịp nhận câu, tiêu đề chưa đổi).
local function sync_state(id, state, ai)
  local path = STATE .. '\\' .. id .. '.json'
  local cur = read_json(path) or {}
  if cur.state == state then return end
  if cur.state == 'work' and cur.by == 'send' and os.time() - (cur.t or 0) < 10 then return end
  cur.state, cur.ai, cur.t, cur.by = state, ai, os.time(), nil
  local f = io.open(path, 'w')
  if f then f:write(wezterm.json_encode(cur)) f:close() end
end

-- Claude: hooks ghi trạng thái; nhưng bấm Esc ngắt giữa chừng thì không có hook "xong".
-- Tiêu đề có ✳ = Claude đang rảnh → sửa 'work' bị kẹt thành 'idle' (giữ nguyên session).
local function fix_claude_state(id, title)
  if not title:find('✳', 1, true) then return end
  local path = STATE .. '\\' .. id .. '.json'
  local cur = read_json(path)
  if not cur or cur.state ~= 'work' or os.time() - (cur.t or 0) < 8 then return end
  cur.state, cur.t, cur.by = 'idle', os.time(), nil
  local f = io.open(path, 'w')
  if f then f:write(wezterm.json_encode(cur)) f:close() end
end

-- Trạng thái Codex / Gemini đọc từ tiêu đề: 'work' đang làm, 'idle' rảnh, 'need' cần duyệt
local function title_state(p)
  local title = p:get_title() or ''
  if title:find('✋') then return 'need', '💎 Gemini' end
  if title:find('✦') then return 'work', '💎 Gemini' end
  if title:find('◇') then return 'idle', '💎 Gemini' end
  local proc = (p:get_foreground_process_name() or ''):lower()
  if proc:find('codex') then
    local low = title:lower()
    if low:find('approv') or low:find('waiting') then return 'need', '🧩 Codex' end
    if title:find('Ready') then return 'idle', '🧩 Codex' end
    return 'work', '🧩 Codex'
  end
end

local function process_alerts(window)
  local focused = window:is_focused()
  local active = tostring(window:active_pane():pane_id())
  local alive, pane_tab = {}, {}
  -- Duyệt mọi cửa sổ WezTerm (trước đây chỉ cửa sổ hiện tại → mở 2 cửa sổ thì xoá nhầm báo động của cửa sổ kia)
  for _, mw in ipairs(wezterm.mux.all_windows()) do
    for _, tab in ipairs(mw:tabs()) do
      for _, p in ipairs(tab:panes()) do
        local id = tostring(p:pane_id())
        alive[id], pane_tab[id] = true, tostring(tab:tab_id())
        local state, who = title_state(p)
        if state then
          local prev = last_state[id]
          last_state[id] = state
          if state == 'need' and prev ~= 'need' then write_alert(id, 'need', who .. ' cần bạn duyệt')
          elseif state == 'idle' and (prev == 'work' or prev == 'need') then write_alert(id, 'done', who .. ' đã làm xong') end
          sync_state(id, state, who:find('Codex', 1, true) and 'codex' or 'gemini')
        else
          fix_claude_state(id, p:get_title() or '')
        end
      end
    end
  end
  tab_alert = {}
  for _, path in ipairs(wezterm.glob(ALERTS:gsub('\\', '/') .. '/*.json')) do
    local id = path:match('(%d+)%.json$')
    if id then
      if not alive[id] or (focused and id == active) then
        os.remove(path) -- ô đã đóng, hoặc bạn đang nhìn đúng ô đó: tắt báo động
        if not alive[id] then toasted[id], last_state[id] = nil, nil end
      else
        local v = read_json(path)
        if v then
          local tid = pane_tab[id]
          tab_alert[tid] = (tab_alert[tid] == 'need') and 'need' or v.kind
          if toasted[id] ~= v.t then
            toasted[id] = v.t
            window:toast_notification('WezTerm · đội AI', v.text or 'AI cần bạn', nil, 6000)
          end
        end
      end
    end
  end
  -- Dọn trạng thái của ô đã đóng (số ô có thể được dùng lại sau khi mở lại WezTerm)
  for _, path in ipairs(wezterm.glob(STATE:gsub('\\', '/') .. '/*.json')) do
    local id = path:match('(%d+)%.json$')
    if id and not alive[id] then os.remove(path) end
  end
end

-- ===== Lưu / khôi phục bố cục (thêm 02/10/2026) =====
-- Ctrl+Shift+S lưu tay · tự lưu mỗi phút (khi có từ 2 ô) · Ctrl+Shift+O chọn bản để mở lại.
-- Mở lại: Claude tiếp tục đúng phiên cũ (session lấy từ file trạng thái), Codex `resume --last`,
-- Gemini `--resume latest`, ô 📋 / 📄 mở lại tài liệu. Bố cục dựng lại theo cột rồi theo hàng
-- (khớp kiểu chia ô thường dùng; kiểu chia lồng nhau phức tạp sẽ gần đúng).
local LAYOUT = { saved = AIDIR .. '\\bo-cuc-luu.json', auto = AIDIR .. '\\bo-cuc-tu-luu.json', prev = AIDIR .. '\\bo-cuc-phien-truoc.json' }

local function pane_kind(p)
  local title = p:get_title() or ''
  if title:find('Cần duyệt', 1, true) then return 'canduyet' end
  if title:find('📄', 1, true) then return 'doc' end
  local _, ai = which_ai { foreground_process_name = p:get_foreground_process_name(), title = title }
  return ({ Claude = 'claude', Codex = 'codex', Gemini = 'gemini' })[ai] or 'shell'
end

local function capture_layout()
  local out, n = { t = os.time(), tabs = {} }, 0
  local docs = wezterm.GLOBAL.docs or {}
  for _, mw in ipairs(wezterm.mux.all_windows()) do
    for _, tab in ipairs(mw:tabs()) do
      local panes = {}
      for _, info in ipairs(tab:panes_with_info()) do
        local p, id = info.pane, tostring(info.pane:pane_id())
        local it = { left = info.left, top = info.top, width = info.width, height = info.height,
          cwd = pane_dir { current_working_dir = p:get_current_working_dir() }, kind = pane_kind(p) }
        if it.kind == 'claude' then
          local s = read_json(STATE .. '\\' .. id .. '.json')
          if s and s.session and s.session ~= '' then it.session = s.session end
        elseif it.kind == 'doc' then
          it.path = docs[id]
        end
        table.insert(panes, it)
        n = n + 1
      end
      table.insert(out.tabs, { title = tab:get_title(), panes = panes })
    end
  end
  return out, n
end

local function write_layout(path)
  local data, n = capture_layout()
  local f = io.open(path, 'w')
  if f then f:write(wezterm.json_encode(data)) f:close() end
  return n
end

local function restore_args(it)
  if it.kind == 'claude' then return PS(it.session and ('claudeRC --resume ' .. it.session) or 'claudeRC --continue') end
  if it.kind == 'codex' then return PS('codex resume --last') end
  if it.kind == 'gemini' then return PS('gemini --resume latest') end
  if it.kind == 'canduyet' then return VIEWER end
  if it.kind == 'doc' and it.path then return DOCVIEW(it.path) end
  return { 'powershell.exe', '-NoLogo' }
end
local function safe_cwd(dir)
  if dir and pcall(wezterm.read_dir, dir) then return dir end
  return HUB
end

local function restore_tab(mw, t)
  if not t.panes or #t.panes == 0 then return end
  local cols, by_left = {}, {}
  for _, it in ipairs(t.panes) do -- gom ô thành cột theo mép trái
    local c = by_left[it.left]
    if not c then
      c = { left = it.left, width = it.width, items = {} }
      by_left[it.left] = c
      table.insert(cols, c)
    end
    c.width = math.max(c.width, it.width)
    table.insert(c.items, it)
  end
  table.sort(cols, function(a, b) return a.left < b.left end)
  for _, c in ipairs(cols) do table.sort(c.items, function(a, b) return a.top < b.top end) end

  local first = cols[1].items[1]
  local tab, root = mw:spawn_tab { cwd = safe_cwd(first.cwd), args = restore_args(first) }
  if t.title and t.title ~= '' then tab:set_title(t.title) end
  local heads, cur = { root }, root
  for i = 2, #cols do -- tách dần sang phải, giữ tỉ lệ chiều rộng
    local rest = 0
    for j = i, #cols do rest = rest + cols[j].width end
    local it = cols[i].items[1]
    cur = cur:split { direction = 'Right', size = rest / (rest + cols[i - 1].width), cwd = safe_cwd(it.cwd), args = restore_args(it) }
    heads[i] = cur
  end
  for i, c in ipairs(cols) do -- trong mỗi cột: tách dần xuống dưới
    local p = heads[i]
    for k = 2, #c.items do
      local rest = 0
      for j = k, #c.items do rest = rest + c.items[j].height end
      local it = c.items[k]
      p = p:split { direction = 'Bottom', size = rest / (rest + c.items[k - 1].height), cwd = safe_cwd(it.cwd), args = restore_args(it) }
    end
  end
  root:activate()
end

-- Ctrl+Shift+S: lưu bố cục hiện tại
save_layout = wezterm.action_callback(function(window)
  local n = write_layout(LAYOUT.saved)
  window:toast_notification('WezTerm · đội AI', '💾 Đã lưu bố cục (' .. n .. ' ô). Mở lại: Ctrl+Shift+O', nil, 4000)
end)

-- Ctrl+Shift+O: chọn bản bố cục để mở lại (thành các tab mới trong cửa sổ này)
restore_menu = wezterm.action_callback(function(window, pane)
  local choices = {}
  for _, c in ipairs { { 'saved', '💾 Bản lưu tay (Ctrl+Shift+S)' }, { 'prev', '⏮  Phiên trước (trước lần mở WezTerm này)' }, { 'auto', '🔄 Tự lưu gần nhất (phiên này)' } } do
    local d = read_json(LAYOUT[c[1]])
    if d and d.tabs then
      local n = 0
      for _, t in ipairs(d.tabs) do n = n + #(t.panes or {}) end
      table.insert(choices, { id = c[1], label = c[2] .. '  ·  ' .. os.date('%H:%M %d/%m', d.t or 0) .. '  ·  ' .. #d.tabs .. ' tab, ' .. n .. ' ô' })
    end
  end
  if #choices == 0 then
    window:toast_notification('WezTerm', 'Chưa có bố cục nào được lưu', nil, 3000)
    return
  end
  window:perform_action(act.InputSelector {
    title = 'Mở lại bố cục nào?  (Enter chọn · Esc thoát)',
    choices = choices,
    action = wezterm.action_callback(function(w, _, id)
      if not id then return end
      local d = read_json(LAYOUT[id])
      for _, t in ipairs(d and d.tabs or {}) do
        local ok, err = pcall(restore_tab, w:mux_window(), t)
        if not ok then wezterm.log_error('restore_tab: ' .. tostring(err)) end
      end
    end),
  }, pane)
end)

-- Tự lưu mỗi phút, chỉ khi có từ 2 ô (để một lần mở thử 1 ô không đè mất bố cục cũ)
local last_autosave = 0
local function autosave()
  if os.time() - last_autosave < 60 then return end
  last_autosave = os.time()
  local n = 0
  for _, mw in ipairs(wezterm.mux.all_windows()) do
    for _, tab in ipairs(mw:tabs()) do n = n + #tab:panes() end
  end
  if n >= 2 then write_layout(LAYOUT.auto) end
end

-- Khi WezTerm vừa mở: tạo thư mục cần thiết, chuyển bản tự lưu của lần trước thành "Phiên trước",
-- xoá trạng thái cũ (số ô sẽ đánh lại từ đầu)
wezterm.on('gui-startup', function()
  wezterm.background_child_process { 'cmd.exe', '/c', 'mkdir', ALERTS, STATE }
  local s = read_file(LAYOUT.auto)
  if s and s ~= '' then
    local f = io.open(LAYOUT.prev, 'wb')
    if f then f:write(s) f:close() end
    os.remove(LAYOUT.auto)
    wezterm.GLOBAL.hint_restore = true
  end
  for _, path in ipairs(wezterm.glob(STATE:gsub('\\', '/') .. '/*.json')) do os.remove(path) end
end)

-- Nhiên liệu: hạn mức 5 giờ / tuần đã dùng của Claude (statusline.js ghi) và Codex (file phiên gần nhất)
local fuel_cache = { at = 0, cells = nil }
local function pct_color(p)
  return p >= 80 and '#e06c75' or (p >= 50 and '#e5c07b' or '#98c379')
end
local function fuel_part(name, five, five_reset, week)
  local now = os.time()
  local cells = { { Foreground = { Color = '#abb2bf' } }, { Text = name .. ' ' } }
  if five then
    if five_reset and five_reset < now then five = 0 end -- đã qua giờ làm mới
    five = math.floor(five + 0.5)
    table.insert(cells, { Foreground = { Color = pct_color(five) } })
    local txt = '5h ' .. five .. '%'
    if five >= 80 and five_reset then txt = txt .. ' (mới lúc ' .. os.date('%H:%M', five_reset) .. ')' end
    table.insert(cells, { Text = txt })
  end
  if week then
    week = math.floor(week + 0.5)
    table.insert(cells, { Foreground = { Color = '#7f848e' } })
    table.insert(cells, { Text = ' · tuần ' })
    table.insert(cells, { Foreground = { Color = pct_color(week) } })
    table.insert(cells, { Text = week .. '%' })
  end
  return cells
end
local function fuel_cells()
  if os.time() - fuel_cache.at < 60 and fuel_cache.cells then return fuel_cache.cells end
  local cells = { { Foreground = { Color = '#abb2bf' } }, { Text = '⛽ ' } }
  local c = read_json(AIDIR .. '\\fuel-claude.json')
  if c then
    for _, it in ipairs(fuel_part('Claude', c.five, c.five_reset, c.week)) do table.insert(cells, it) end
  end
  local home = (os.getenv('USERPROFILE') or 'C:\\Users\\Hion'):gsub('\\', '/')
  local files = wezterm.glob(home .. '/.codex/sessions/*/*/*/*.jsonl')
  table.sort(files)
  local s = files[#files] and read_file(files[#files], 262144)
  if s then
    local p5, r5, pw
    for u, r in s:gmatch('"primary":{"used_percent":([%d%.]+),"window_minutes":%d+,"resets_at":(%d+)}') do p5, r5 = u, r end
    for u in s:gmatch('"secondary":{"used_percent":([%d%.]+)') do pw = u end
    if p5 then
      table.insert(cells, { Foreground = { Color = '#5c6370' } })
      table.insert(cells, { Text = '  ·  ' })
      for _, it in ipairs(fuel_part('Codex', tonumber(p5), tonumber(r5), tonumber(pw))) do table.insert(cells, it) end
    end
  end
  fuel_cache = { at = os.time(), cells = cells }
  return cells
end

wezterm.on('format-tab-title', function(tab)
  local p = tab.active_pane
  local proj = split_project(pane_dir(p))
  local icon = which_ai(p)
  local zoom = p.is_zoomed and ' 🔍' or ''
  local alert = tab_alert[tostring(tab.tab_id)]
  local bg = alert == 'need' and '#a8322d' or (alert == 'done' and '#2e6b3a' or (tab.is_active and '#3a3f4b' or '#1e2127'))
  local bell = alert == 'need' and '🔔 ' or (alert == 'done' and '✅ ' or '')
  return {
    { Background = { Color = bg } },
    { Foreground = { Color = (tab.is_active or alert) and '#ffffff' or '#7f848e' } },
    { Text = ' ' .. (tab.tab_index + 1) .. ' ' .. bell .. icon .. ' ' },
    { Foreground = { Color = alert and '#ffffff' or (tab.is_active and proj_color(proj) or '#7f848e') } },
    { Attribute = { Intensity = (tab.is_active or alert) and 'Bold' or 'Normal' } },
    { Text = proj .. zoom .. ' ' },
  }
end)

wezterm.on('update-status', function(window, pane)
  local oka, erra = pcall(process_alerts, window)
  if not oka then wezterm.log_error('process_alerts: ' .. tostring(erra)) end
  local oko, erro = pcall(process_open, window)
  if not oko then wezterm.log_error('process_open: ' .. tostring(erro)) end
  local oks, errs = pcall(autosave)
  if not oks then wezterm.log_error('autosave: ' .. tostring(errs)) end
  if wezterm.GLOBAL.hint_restore then
    wezterm.GLOBAL.hint_restore = false
    window:toast_notification('WezTerm · đội AI', '⏮ Có bố cục của phiên trước. Bấm Ctrl+Shift+O để mở lại.', nil, 8000)
  end
  local info = {
    current_working_dir = pane:get_current_working_dir(),
    foreground_process_name = pane:get_foreground_process_name(),
    title = pane:get_title(),
  }
  local dir = pane_dir(info)
  local proj, sub = split_project(dir)
  local icon, ai = which_ai(info)
  local cells = {}
  local function add(items)
    if #cells > 0 then
      table.insert(cells, { Foreground = { Color = '#5c6370' } })
      table.insert(cells, { Text = '  |  ' })
    end
    for _, it in ipairs(items) do table.insert(cells, it) end
  end

  local okf, fc = pcall(fuel_cells)
  if not okf then wezterm.log_error('fuel_cells: ' .. tostring(fc)) end
  if okf and fc and #fc > 2 then add(fc) end
  if ai then add { { Foreground = { Color = '#56b6c2' } }, { Text = icon .. ' ' .. ai } } end
  local where = { { Foreground = { Color = proj_color(proj) } }, { Attribute = { Intensity = 'Bold' } }, { Text = '📁 ' .. proj } }
  table.insert(where, { Attribute = { Intensity = 'Normal' } })
  if sub then
    table.insert(where, { Foreground = { Color = '#7f848e' } })
    table.insert(where, { Text = ' › ' .. (sub:gsub('\\', '/')) })
  end
  add(where)
  local br = dir and git_branch(dir)
  if br then add { { Foreground = { Color = '#98c379' } }, { Text = '🌿 ' .. br } } end
  local n = #window:active_tab():panes()
  if n > 1 then add { { Foreground = { Color = '#abb2bf' } }, { Text = '▦ ' .. n .. ' ô' } } end
  local wd = { 'CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7' }
  add { { Foreground = { Color = '#abb2bf' } }, { Text = '🕐 ' .. wezterm.strftime('%H:%M') .. ' ' .. wd[tonumber(wezterm.strftime('%w')) + 1] .. ' ' .. wezterm.strftime('%d/%m') .. ' ' } }
  window:set_right_status(wezterm.format(cells))

  -- Góc trái: báo khi đang ở chế độ phím đặc biệt (copy mode…)
  local kt = window:active_key_table()
  window:set_left_status(kt and wezterm.format { { Background = { Color = '#e5c07b' } }, { Foreground = { Color = '#000000' } }, { Text = ' ⌨ ' .. kt .. ' ' } } or '')
end)

return config
