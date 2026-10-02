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

-- ===== Bàn làm việc Tổng quản + menu dự án (thêm 01/10/2026; bản cũ: .wezterm.lua.bak-before-giai-doan1) =====
-- Ô tài liệu bên phải: can-duyet.md + sổ tiến độ các dự án, tự vẽ lại khi file đổi
local VIEWER = { 'powershell.exe', '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
  HUB .. '\\cai-dat\\can-duyet-view.ps1' }

-- Đóng ĐÚNG ô theo số ô. KHÔNG dùng perform_action(CloseCurrentPane, ô): lệnh đó đóng ô ĐANG CHỌN của tab,
-- không phải ô truyền vào → 02/10 22h47 mở tài liệu 📄 mới đã đóng nhầm ô Manager Chatbot.
local function kill_pane(p)
  wezterm.background_child_process { wezterm.executable_dir .. '\\wezterm.exe', 'cli', '--no-auto-start',
    'kill-pane', '--pane-id', tostring(p:pane_id()) }
end

local function find_viewer(tab)
  for _, p in ipairs(tab:panes()) do
    if (p:get_title() or ''):find('Cần duyệt', 1, true) then return p end
  end
end

-- Ctrl+Shift+J: bật / tắt ô tài liệu cần duyệt bên cạnh ô đang chọn
local toggle_doc = wezterm.action_callback(function(window, pane)
  local v = find_viewer(window:active_tab())
  if v then
    kill_pane(v)
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
-- Ô tên 1 dòng trên đỉnh ô AI (cai-dat\ten-o.js). Sổ { [id ô tên] = id ô AI } lưu dạng JSON trong GLOBAL
-- (GLOBAL tự đổi khoá "227" thành số 227 nên không lưu bảng trực tiếp được).
-- Chỉ giải mã JSON khi sổ thay đổi (hàm vẽ tab gọi rất dày). Trả bảng dùng chung: ai muốn sửa thì sao chép trước.
local HDR = { s = nil, m = {} }
local function hdr_map()
  local s = wezterm.GLOBAL.ten_o_map or '{}'
  if s ~= HDR.s then
    local ok, m = pcall(wezterm.json_parse, s)
    HDR = { s = s, m = (ok and type(m) == 'table') and m or {} }
  end
  return HDR.m
end
local function hdr_copy() local c = {} for k, v in pairs(hdr_map()) do c[k] = v end return c end
local function hdr_save(m) wezterm.GLOBAL.ten_o_map = next(m) and wezterm.json_encode(m) or '{}' end
-- nhận Pane hoặc PaneInformation
local function is_header(p)
  local id = type(p.pane_id) == 'number' and p.pane_id or p:pane_id()
  return hdr_map()[tostring(id)] ~= nil
end

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
      kill_pane(p)
    end
  end
  if not cur then
    for _, p in ipairs(tab:panes()) do if not is_doc(p) and not is_header(p) then cur = p break end end
  end
  if not cur then return end
  if is_header(cur) then cur = wezterm.mux.get_pane(tonumber(hdr_map()[tostring(cur:pane_id())])) or cur end
  -- top_level: ô 📄 chiếm trọn mép phải tab, không chen vào dưới thanh tên của ô AI
  local doc = cur:split { direction = 'Right', size = 0.42, top_level = true, cwd = HUB, args = DOCVIEW(req.path) }
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
  if is_header(pane) then pane = wezterm.mux.get_pane(tonumber(hdr_map()[tostring(pane:pane_id())])) or pane end
  pane:move_to_new_tab()
  tab:activate()
end)

-- Ctrl+Shift+G: chọn một ô ở tab khác rồi kéo về bên phải ô đang chọn
local pull_menu = wezterm.action_callback(function(window, pane)
  local choices, cur_tab = {}, window:active_tab():tab_id()
  for wi, mw in ipairs(wezterm.mux.all_windows()) do
  for i, tab in ipairs(mw:tabs()) do
    if tab:tab_id() ~= cur_tab then
      for _, p in ipairs(tab:panes()) do if not is_header(p) then
        local cwd = p:get_current_working_dir()
        local dir = cwd and (cwd.file_path or tostring(cwd)) or ''
        local proj = dir:gsub('[\\/]+$', ''):match('([^\\/]+)$') or '?'
        table.insert(choices, { id = tostring(p:pane_id()),
          label = (mw:window_id() ~= window:window_id() and ('Cửa sổ ' .. wi .. ' · ') or '') .. 'Tab ' .. i .. '  ·  ' .. proj .. '  ·  ' .. (p:get_title() or '') })
      end end
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
      if is_header(p) then p = wezterm.mux.get_pane(tonumber(hdr_map()[tostring(p:pane_id())])) or p end
      wezterm.background_child_process { 'powershell.exe', '-NoProfile', '-Command',
        "$env:WEZTERM_UNIX_SOCKET='" .. SOCK .. "'; & '" .. WEZ_EXE .. "' cli --no-auto-start split-pane --pane-id "
          .. p:pane_id() .. ' --right --top-level --percent 30 --move-pane-id ' .. id }
      wezterm.time.call_after(1.5, function() wezterm.emit('chia-deu', window, p) end)
    end),
  }, pane)
end)

-- Ctrl+Shift+H: tab mới "Tổng quản" = Claude ở Hion bên trái + ô tài liệu cần duyệt bên phải
local open_desk = wezterm.action_callback(function(window, _)
  local tab, p = window:mux_window():spawn_tab { cwd = HUB, args = PS('claudeRC') }
  p:split { direction = 'Right', size = 0.38, cwd = HUB, args = VIEWER }
  tab:set_title('Tổng quản')
  p:activate()
end)

-- Ctrl+Shift+A: chọn dự án + AI từ danh sách, rồi chọn mở ở ô phải / ô dưới / tab mới
local AIS = { { '🤖 Claude', 'claudeRC' }, { '🧩 Codex', 'codex' } } -- Gemini đã bỏ (02/10/2026)
-- Thứ tự theo cây đội agent ở Hion\cay-du-an.json: Tổng quản → các PM dự án → công cụ; thư mục khác xếp cuối
local function projects()
  local dirs, seen, t = {}, {}, {}
  for _, path in ipairs(wezterm.read_dir(AI_ROOT)) do
    local n = path:match('([^\\/]+)$')
    if n and not n:find('.', 1, true) then dirs[n] = true end -- bỏ file, chỉ lấy thư mục
  end
  local f = io.open(HUB .. '\\cay-du-an.json', 'rb')
  if f then
    local ok, v = pcall(wezterm.json_parse, (f:read('*a'):gsub('^\239\187\191', '')))
    f:close()
    if ok and v and v.cay then
      for _, n in ipairs(v.cay) do
        if dirs[n.ten] and not seen[n.ten] then
          seen[n.ten] = true
          table.insert(t, { name = n.ten, level = n.cap or 0, icon = n.bieuTuong or '', role = n.vai or '' })
        end
      end
    end
  end
  local rest = {}
  for n in pairs(dirs) do if not seen[n] then table.insert(rest, n) end end
  table.sort(rest)
  for _, n in ipairs(rest) do table.insert(t, { name = n, level = -1, icon = '·', role = 'khác' }) end
  return t
end
local project_menu = wezterm.action_callback(function(window, pane)
  local choices = {}
  local list = projects()
  for k, p in ipairs(list) do
    local last_child = p.level == 1 and (k == #list or list[k + 1].level ~= 1)
    local indent = p.level == 1 and (last_child and '   └─ ' or '   ├─ ') or ''
    for i, a in ipairs(AIS) do
      table.insert(choices, { id = p.name .. '|' .. i,
        label = indent .. p.icon .. ' ' .. p.name .. '  ·  ' .. p.role .. '   →   ' .. a[1] })
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
            -- ô bên phải = cột mới ở mép phải cả tab (không lồng vào trong ô đang chọn), rồi chia đều
            local np = p2:split { direction = where, top_level = where == 'Right', cwd = dir, args = PS(a[2]) }
            if where == 'Right' then wezterm.emit('chia-deu', w2, np) end
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
  -- Alt+Shift+D: thêm 1 cột ở mép phải cả tab rồi chia đều (không lồng ô mới vào trong ô đang chọn)
  { key = 'D', mods = 'ALT|SHIFT', action = wezterm.action_callback(function(w, p)
    local np = p:split { direction = 'Right', top_level = true, cwd = HUB, args = PS('ai') }
    wezterm.emit('chia-deu', w, np)
  end) },
  -- Sắp xếp ô: Ctrl+Shift+X đổi chỗ (hiện chữ cái trên mỗi ô, bấm chữ của ô muốn đổi)
  --            Ctrl+Shift+F tách ô đang chọn ra cửa sổ riêng (kéo thả tự do, Win+mũi tên để xếp)
  { key = 'X', mods = 'CTRL|SHIFT', action = act.PaneSelect { mode = 'SwapWithActive', alphabet = 'asdfghjklqwertyuiop' } },
  { key = 'F', mods = 'CTRL|SHIFT', action = act.EmitEvent 'tach-o' },
  { key = '_', mods = 'ALT|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = '@', mods = 'ALT|SHIFT', action = cols(2) },
  { key = '#', mods = 'ALT|SHIFT', action = cols(3) },
  { key = '$', mods = 'ALT|SHIFT', action = cols(4) },
  { key = '2', mods = 'ALT|SHIFT', action = cols(2) },
  { key = '3', mods = 'ALT|SHIFT', action = cols(3) },
  { key = '4', mods = 'ALT|SHIFT', action = cols(4) },
  -- Chia đều mọi ô trong tab đang xem (bao nhiêu ô cũng được): cột rộng bằng nhau, ô xếp chồng cao bằng nhau
  -- (đóng tạm thanh tên các ô trước khi chia, chia xong tự dựng lại — xem sự kiện 'chia-deu' cuối file)
  { key = 'E', mods = 'CTRL|SHIFT', action = act.EmitEvent 'chia-deu' },
  -- Bật/tắt thanh tên 1 dòng trên đỉnh mỗi ô AI
  { key = 'D', mods = 'CTRL|SHIFT', action = act.EmitEvent 'ten-o-bat-tat' },
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
  -- Ctrl + click = mở link trên trình duyệt, kể cả khi Claude/Codex đang giữ chuột (mouse_reporting)
  { event = { Up = { streak = 1, button = 'Left' } }, mods = 'CTRL', action = act.OpenLinkAtMouseCursor },
  { event = { Down = { streak = 1, button = 'Left' } }, mods = 'CTRL', action = act.Nop },
  { event = { Up = { streak = 1, button = 'Left' } }, mods = 'CTRL', mouse_reporting = true, action = act.OpenLinkAtMouseCursor },
  { event = { Down = { streak = 1, button = 'Left' } }, mods = 'CTRL', mouse_reporting = true, action = act.Nop },
}

-- ===== Thanh trạng thái (thêm 01/10/2026; bản cũ: .wezterm.lua.bak-before-statusbar) =====
-- Tên tab: số · biểu tượng AI · dự án (màu theo dự án, giống thanh trạng thái Claude)
-- Góc phải: AI · dự án › thư mục con · 🌿 nhánh git · số ô · giờ, ngày
config.use_fancy_tab_bar = false
config.tab_max_width = 32
config.status_update_interval = 2000

-- Màu + logo riêng từng dự án: lấy từ Hion\cay-du-an.json (trường "mau", "logo"); dự án lạ → màu theo tên, logo 📁
local proj_colors = { hion = '#e5c07b', sino = '#e06c75', coolguy = '#61afef', chatbot = '#c678dd' }
local proj_logos = {}
do
  local f = io.open(HUB .. '\\cay-du-an.json', 'rb')
  if f then
    local ok, v = pcall(wezterm.json_parse, (f:read('*a'):gsub('^\239\187\191', '')))
    f:close()
    if ok and v and v.cay then
      for _, n in ipairs(v.cay) do
        if n.mau then proj_colors[n.ten:lower()] = n.mau end
        if n.logo then proj_logos[n.ten:lower()] = n.logo end
      end
    end
  end
end
local function proj_logo(name) return proj_logos[(name or ''):lower()] or '📁' end
local palette = { '#56b6c2', '#98c379', '#d19a66', '#c678dd', '#61afef' }
local function proj_color(name)
  name = name or '?'
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
  if s:find('claude') or s:find('✳') or s:find('◐') or s:find('◓') or s:find('◑') or s:find('◒') then return '🤖', 'Claude' end
  if s:find('powershell') or s:find('pwsh') then return '⌨️', 'PowerShell' end
  return '▪️', nil
end

-- Nhánh git: đọc thẳng file .git\HEAD (không chạy lệnh git nên không chậm)
local GIT_MEMO = {} -- [thư mục] = { t, nhánh } — thanh phải vẽ mỗi 2 giây, nhánh hiếm khi đổi
local git_branch_raw
local function git_branch(dir)
  local m = GIT_MEMO[dir]
  if m and os.time() - m.t < 15 then return m.b end
  local b = git_branch_raw(dir)
  GIT_MEMO[dir] = { t = os.time(), b = b }
  return b
end
git_branch_raw = function(dir)
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

-- Báo động: Claude ghi file qua hooks (cai-dat\wez-alert.js); Codex thì đoán từ tiêu đề ô.
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
-- Nhớ trong RAM lần ghi gần nhất → không đọc file mỗi 2 giây cho từng ô (chỉ đọc khi trạng thái đổi hoặc mỗi 10 giây)
local SYNC_MEMO, FIX_MEMO = {}, {}
local function sync_state(id, state, ai)
  local m = SYNC_MEMO[id]
  if m and m.state == state and os.time() - m.t < 10 then return end
  SYNC_MEMO[id] = { state = state, t = os.time() }
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
  if not title:find('✳', 1, true) then FIX_MEMO[id] = nil return end
  if FIX_MEMO[id] and os.time() - FIX_MEMO[id] < 10 then return end -- ô rảnh: soát file mỗi 10 giây là đủ
  FIX_MEMO[id] = os.time()
  local path = STATE .. '\\' .. id .. '.json'
  local cur = read_json(path)
  if not cur or cur.state ~= 'work' or os.time() - (cur.t or 0) < 8 then return end
  cur.state, cur.t, cur.by = 'idle', os.time(), nil
  local f = io.open(path, 'w')
  if f then f:write(wezterm.json_encode(cur)) f:close() end
end

-- Thông tin một ô (tiêu đề, tiến trình, thư mục, AI, dự án), hỏi Windows tối đa 1 lần mỗi giây cho mỗi ô.
-- get_foreground_process_name / get_current_working_dir trên Windows khá chậm; trước đây báo động, thanh tên,
-- thanh trạng thái, vẽ tab… mỗi chỗ hỏi lại riêng → GUI giật/treo khi thao tác nhanh. PANE_LAST giữ bản gần nhất
-- để các hàm vẽ (format-tab-title, format-window-title — chạy rất dày) chỉ tra bảng, không hỏi Windows.
-- 03/10: tiến trình + thư mục (2 câu hỏi chậm) chỉ hỏi lại mỗi PANE_SLOW giây / ô; tiêu đề (nhanh) vẫn mỗi giây.
-- Trước đây cứ 2 giây hỏi lại cả 2 cho MỌI ô (kể cả ô tên 🏷) → 20 ô = 40 lần hỏi Windows / 2 giây → giật.
local PANE_NOW, PANE_LAST, PANE_SLOWC = { t = -1, m = {} }, {}, {}
local PANE_SLOW = 6
local function pinfo(p)
  local now = os.time()
  if PANE_NOW.t ~= now then PANE_NOW = { t = now, m = {} } end
  local id = p:pane_id()
  local x = PANE_NOW.m[id]
  if x then return x end
  local sc = PANE_SLOWC[id]
  if not sc or now - sc.t >= PANE_SLOW then
    sc = { t = now, proc = p:get_foreground_process_name() or '', cwd = p:get_current_working_dir() }
    PANE_SLOWC[id] = sc
  end
  x = { title = p:get_title() or '', proc = sc.proc, cwd = sc.cwd }
  x.dir = pane_dir { current_working_dir = x.cwd }
  x.proj, x.sub = split_project(x.dir)
  x.icon, x.ai = which_ai { foreground_process_name = x.proc, title = x.title }
  PANE_NOW.m[id], PANE_LAST[tostring(id)] = x, x
  return x
end

-- Trạng thái Codex đọc từ tiêu đề: 'work' đang làm, 'idle' rảnh, 'need' cần duyệt
local function title_state(p)
  local x = pinfo(p)
  local title = x.title
  local proc = x.proc:lower()
  if proc:find('codex') then
    local low = title:lower()
    if low:find('approv') or low:find('waiting') then return 'need', '🧩 Codex' end
    if title:find('Ready') then return 'idle', '🧩 Codex' end
    return 'work', '🧩 Codex'
  end
end

-- Báo sang điện thoại (ntfy) khi một ô cần duyệt mà bạn chưa bấm vào sau N phút.
-- Bật / tắt: wez.ps1 dienthoai bat | tat | thu  → ghi vào ~\.wez-ai.json mục "dienThoai".
local PHONE = machine.dienThoai
if PHONE and not PHONE.ntfy then PHONE = nil end
local phoned = {}
local function send_phone(text)
  local body = AIDIR .. '\\ntfy-' .. os.time() .. '.txt' -- nội dung qua file: giữ đúng tiếng Việt
  local f = io.open(body, 'wb')
  if not f then return end
  f:write(text)
  f:close()
  wezterm.background_child_process { 'cmd.exe', '/c', 'curl.exe', '-s', '-m', '15', '-H', 'Title: WezTerm AI', '-H', 'Tags: bell',
    '-H', 'Priority: high', '--data-binary', '@' .. body, (PHONE.server or 'https://ntfy.sh') .. '/' .. PHONE.ntfy, '&', 'del', body }
end

-- Thông báo Windows bấm được: bấm vào → nhảy về đúng ô (thong-bao.ps1 tạo link wezai-o:<PANEID> → chuyen-o.ps1).
-- Link đăng ký 1 lần bằng cai-dat\dang-ky-thong-bao.ps1; thiếu script thì dùng thông báo thường của WezTerm.
local NOTIFY = { vbs = HUB .. '\\cai-dat\\an.vbs', ps1 = HUB .. '\\cai-dat\\thong-bao.ps1' }
local function toast_click(window, pane_id, title, text)
  local f = io.open(NOTIFY.ps1, 'rb')
  if f then
    f:close()
    wezterm.background_child_process { 'wscript.exe', NOTIFY.vbs, NOTIFY.ps1, '-Pane', tostring(pane_id), '-Title', title, '-Text', text }
  else
    window:toast_notification(title, text, nil, 6000)
  end
end

local function process_alerts(window)
  local focused = window:is_focused()
  local active = tostring(window:active_pane():pane_id())
  local alive, pane_tab, pane_proj = {}, {}, {}
  -- Duyệt mọi cửa sổ WezTerm (trước đây chỉ cửa sổ hiện tại → mở 2 cửa sổ thì xoá nhầm báo động của cửa sổ kia)
  for _, mw in ipairs(wezterm.mux.all_windows()) do
    for _, tab in ipairs(mw:tabs()) do
      for _, p in ipairs(tab:panes()) do
        local id = tostring(p:pane_id())
        alive[id], pane_tab[id] = true, tostring(tab:tab_id())
        if not is_header(p) then -- ô tên 🏷: không có AI, khỏi hỏi Windows
          local okp, x = pcall(pinfo, p)
          pane_proj[id] = (okp and x.proj ~= '?') and x.proj or nil
          local state, who = title_state(p)
          if state then
            local prev = last_state[id]
            last_state[id] = state
            if state == 'need' and prev ~= 'need' then write_alert(id, 'need', who .. ' cần bạn duyệt')
            elseif state == 'idle' and (prev == 'work' or prev == 'need') then write_alert(id, 'done', who .. ' đã làm xong') end
            sync_state(id, state, 'codex')
          else
            fix_claude_state(id, okp and x.title or '')
          end
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
            local where = pane_proj[id] and (' · ' .. pane_proj[id]) or ''
            toast_click(window, id, 'WezTerm · đội AI' .. where, v.text or 'AI cần bạn')
          end
          -- Chưa bấm vào ô sau N phút → báo sang điện thoại (mỗi lần báo động chỉ gửi 1 lần)
          local key = id .. ':' .. tostring(v.t)
          if PHONE and not phoned[key] and (v.kind == 'need' or (v.kind == 'done' and PHONE.baoXong))
            and os.time() - (v.t or 0) >= (PHONE.sauPhut or 5) * 60 then
            phoned[key] = true
            send_phone((v.text or 'AI cần bạn') .. ' (chờ ' .. math.floor((os.time() - v.t) / 60) .. ' phút)')
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
-- ô 📋 / 📄 mở lại tài liệu. Bố cục dựng lại theo cột rồi theo hàng
-- (khớp kiểu chia ô thường dùng; kiểu chia lồng nhau phức tạp sẽ gần đúng).
local LAYOUT = { saved = AIDIR .. '\\bo-cuc-luu.json', auto = AIDIR .. '\\bo-cuc-tu-luu.json', prev = AIDIR .. '\\bo-cuc-phien-truoc.json' }

local function pane_kind(p)
  local x = pinfo(p)
  local title, ai = x.title, x.ai
  if title:find('Cần duyệt', 1, true) then return 'canduyet' end
  if title:find('📄', 1, true) then return 'doc' end
  return ({ Claude = 'claude', Codex = 'codex' })[ai] or 'shell'
end

local function capture_layout()
  local out, n = { t = os.time(), tabs = {} }, 0
  local docs = wezterm.GLOBAL.docs or {}
  for _, mw in ipairs(wezterm.mux.all_windows()) do
    for _, tab in ipairs(mw:tabs()) do
      local panes = {}
      for _, info in ipairs(tab:panes_with_info()) do
        local p, id = info.pane, tostring(info.pane:pane_id())
        if not is_header(p) then -- ô tên không lưu: tự dựng lại sau khi khôi phục
          local it = { left = info.left, top = info.top, width = info.width, height = info.height,
            cwd = pinfo(p).dir, kind = pane_kind(p) } -- dùng thư mục đã nhớ, không hỏi lại Windows
          if it.kind == 'claude' then
            local s = read_json(STATE .. '\\' .. id .. '.json')
            if s and s.session and s.session ~= '' then it.session = s.session end
          elseif it.kind == 'doc' then
            it.path = docs[id]
          end
          table.insert(panes, it)
          n = n + 1
        end
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
  if it.kind == 'canduyet' then return VIEWER end
  if it.kind == 'doc' and it.path then return DOCVIEW(it.path) end
  return { 'powershell.exe', '-NoLogo' }
end
local function safe_cwd(dir)
  if dir and pcall(wezterm.read_dir, dir) then return dir end
  return HUB
end

local function restore_tab(mw, t)
  local keep = {} -- bỏ ô không có thư mục (ô tên 🏷 lỡ bị lưu ở bản cũ)
  for _, it in ipairs(t.panes or {}) do if it.cwd or it.kind ~= 'shell' then table.insert(keep, it) end end
  t = { title = t.title, panes = keep }
  if #t.panes == 0 then return end
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

-- Menu `ai` chọn "2) Mở lại tất cả phiên đang làm dở" → PowerShell gửi biến wez_ai=mo-lai (OSC 1337 SetUserVar)
-- → mở lại bố cục phiên trước (Claude tiếp đúng phiên, Codex resume) rồi đóng ô menu.
wezterm.on('user-var-changed', function(window, pane, name, value)
  if name ~= 'wez_ai' or value ~= 'mo-lai' then return end
  local d
  for _, k in ipairs { 'prev', 'saved', 'auto' } do
    local x = read_json(LAYOUT[k])
    if x and x.tabs and #x.tabs > 0 then d = x break end
  end
  if not d then
    window:toast_notification('WezTerm · đội AI', 'Chưa có phiên nào được lưu để mở lại', nil, 4000)
    return
  end
  for _, t in ipairs(d.tabs) do
    local ok, err = pcall(restore_tab, window:mux_window(), t)
    if not ok then wezterm.log_error('restore_tab: ' .. tostring(err)) end
  end
  kill_pane(pane) -- đóng đúng ô menu (CloseCurrentPane có thể đóng nhầm ô đang chọn sau khi mở lại các tab)
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
local FUEL_MEMO = {} -- [số tài khoản Codex] = { file, size, row }: file phiên chưa đổi thì không đọc lại
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
  -- Codex: mỗi dự án một tài khoản (~\.codex-tai-khoan.json, CODEX_HOME riêng) → đọc file phiên mới nhất của từng tài khoản
  local home = (os.getenv('USERPROFILE') or 'C:\\Users\\Hion'):gsub('\\', '/')
  local bang = read_json(home .. '/.codex-tai-khoan.json')
  local tks = (bang and bang.taiKhoan) or { { so = 0, ten = 'Codex', thuMuc = home .. '/.codex' } }
  local codex = {}
  for _, tk in ipairs(tks) do
    local files, root = {}, (tk.thuMuc or ''):gsub('\\', '/') .. '/sessions/'
    for d = 0, 6 do -- thư mục sessions/YYYY/MM/DD: tìm ngày gần nhất có phiên (trước đây quét cả lịch sử → giật mỗi phút)
      files = wezterm.glob(root .. os.date('%Y/%m/%d', os.time() - d * 86400) .. '/*.jsonl')
      if #files > 0 then break end
    end
    table.sort(files)
    -- 03/10: file phiên không đổi cỡ thì dùng lại kết quả cũ; đọc 96KB cuối thay vì 256KB (mỗi phút × 3 tài khoản → giật)
    local f, size = files[#files] and io.open(files[#files], 'rb'), nil
    if f then size = f:seek('end') f:close() end
    local memo = FUEL_MEMO[tk.so or 0]
    local s = nil
    if memo and memo.file == files[#files] and memo.size == size then
      if memo.row then table.insert(codex, memo.row) end
    else
      s = files[#files] and read_file(files[#files], 98304)
      FUEL_MEMO[tk.so or 0] = { file = files[#files], size = size }
    end
    if s then
      local p5, r5, pw, rw
      for u, r in s:gmatch('"primary":{"used_percent":([%d%.]+),"window_minutes":%d+,"resets_at":(%d+)}') do p5, r5 = u, r end
      for u, r in s:gmatch('"secondary":{"used_percent":([%d%.]+),"window_minutes":%d+,"resets_at":(%d+)}') do pw, rw = u, r end
      if not pw then for u in s:gmatch('"secondary":{"used_percent":([%d%.]+)') do pw = u end end
      if p5 then
        local du_an = {}
        for k, v in pairs((bang and bang.duAn) or {}) do if v == tk.so then table.insert(du_an, k) end end
        local row = { so = tk.so, ten = tk.ten or 'Codex', icon = (tk.ten or 'Codex'):match('^(%S+)'), du_an = table.concat(du_an, ', '),
          five = tonumber(p5), five_reset = tonumber(r5), week = tonumber(pw), week_reset = tonumber(rw) }
        FUEL_MEMO[tk.so or 0].row = row
        table.insert(codex, row)
      end
    end
  end
  for i, c in ipairs(codex) do
    table.insert(cells, { Foreground = { Color = '#5c6370' } })
    table.insert(cells, { Text = i == 1 and '  ·  ' or '  ' })
    for _, it in ipairs(fuel_part(#codex > 1 and c.icon or 'Codex', c.five, c.five_reset, #codex > 1 and nil or c.week)) do table.insert(cells, it) end
  end
  fuel_cache = { at = os.time(), cells = cells, codex = codex }
  return cells
end

-- Cảnh báo một tài khoản Codex sắp hết hạn mức (5 giờ hoặc tuần) → thông báo + điện thoại (nếu bật). Mỗi mốc làm mới báo 1 lần.
-- KHÔNG tự xoay tài khoản (rủi ro điều khoản OpenAI — đã chốt 02/10/2026). Ngưỡng: ~\.wez-ai.json "codexCanhBao" (mặc định 90).
local CODEX_WARN = tonumber(machine.codexCanhBao) or 90
local function codex_warn(window)
  local now = os.time()
  local g = wezterm.GLOBAL
  g.codex_warned = g.codex_warned or {}
  for _, c in ipairs(fuel_cache.codex or {}) do
    local five = (c.five_reset and c.five_reset < now) and 0 or c.five
    local which, pct, reset
    if c.week and c.week >= CODEX_WARN then which, pct, reset = 'tuần', c.week, c.week_reset
    elseif five and five >= CODEX_WARN then which, pct, reset = '5 giờ', five, c.five_reset end
    if which then
      local key = tostring(c.so) .. ':' .. which .. ':' .. tostring(reset or os.date('%Y%m%d%H'))
      if not g.codex_warned[key] then
        g.codex_warned[key] = true
        local msg = '⛽ ' .. c.ten .. (c.du_an ~= '' and (' (' .. c.du_an .. ')') or '') .. ' đã dùng ' .. math.floor(pct + 0.5) .. '% hạn mức ' .. which
          .. (reset and (' · làm mới ' .. os.date('%H:%M %d/%m', reset)) or '')
          .. '. Giao tạm việc dự án này cho Claude, hoặc chờ làm mới.'
        window:toast_notification('WezTerm · đội AI', msg, nil, 15000)
        if PHONE then send_phone(msg) end
      end
    end
  end
end

wezterm.on('format-tab-title', function(tab)
  local p = tab.active_pane
  -- hàm này chạy rất dày → chỉ tra bảng PANE_LAST (update-status cập nhật mỗi 2 giây), không hỏi Windows
  local id = tostring(hdr_map()[tostring(p.pane_id)] or p.pane_id) -- đang đứng ở ô tên → lấy ô AI bên dưới
  local x = PANE_LAST[id]
  local proj = x and x.proj or split_project(pane_dir(p))
  local icon = x and x.icon or which_ai { title = p.title }
  local zoom = p.is_zoomed and ' 🔍' or ''
  local alert = tab_alert[tostring(tab.tab_id)]
  local bg = alert == 'need' and '#a8322d' or (alert == 'done' and '#1f5fb4' or (tab.is_active and '#3a3f4b' or '#1e2127')) -- xong việc = nền xanh dương (03/10, người dùng chọn), cần duyệt = đỏ
  local bell = alert == 'need' and '🔔 ' or (alert == 'done' and '✅ ' or '')
  return {
    { Background = { Color = bg } },
    { Foreground = { Color = (tab.is_active or alert) and '#ffffff' or '#7f848e' } },
    { Text = ' ' .. (tab.tab_index + 1) .. ' ' .. bell .. icon .. ' ' },
    { Foreground = { Color = alert and '#ffffff' or (tab.is_active and proj_color(proj) or '#7f848e') } },
    { Attribute = { Intensity = (tab.is_active or alert) and 'Bold' or 'Normal' } },
    { Text = proj_logo(proj) .. ' ' .. proj .. zoom .. ' ' },
  }
end)

-- Tiêu đề cửa sổ (hiện trên thanh tác vụ Windows khi thu nhỏ): "🤖 Claude · Hion | 🧩 Codex · Chatbot"
-- Ô đang chọn đứng đầu; bỏ qua ô xem tài liệu 📄/📋; có 🔔/✅ khi tab cần duyệt / vừa xong
wezterm.on('format-window-title', function(tab, pane, tabs, panes)
  -- chạy rất dày → chỉ tra bảng PANE_LAST, không hỏi Windows
  local function label(p)
    local x = PANE_LAST[tostring(p.pane_id)]
    if x then return x.icon .. ' ' .. (x.ai or 'Terminal') .. ' · ' .. proj_logo(x.proj) .. ' ' .. x.proj end
    local icon, ai = which_ai { title = p.title }
    return icon .. ' ' .. (ai or 'Terminal')
  end
  local tid = hdr_map()[tostring(pane.pane_id)]
  if tid then pane = { pane_id = tonumber(tid), title = '' } end -- đang đứng ở ô tên → lấy ô AI bên dưới
  local parts, seen = { label(pane) }, {}
  seen[parts[1]] = true
  for _, p in ipairs(panes) do
    local t = p.title or ''
    if p.pane_id ~= pane.pane_id and not t:find('📄', 1, true) and not t:find('📋', 1, true) and not is_header(p) then
      local l = label(p)
      if not seen[l] then seen[l] = true; parts[#parts + 1] = l end
    end
  end
  local alert = tab_alert[tostring(tab.tab_id)]
  local bell = alert == 'need' and '🔔 ' or (alert == 'done' and '✅ ' or '')
  return bell .. table.concat(parts, ' | ')
end)

-- Bàn duyệt: nút [✅ Duyệt] [✏️ Trả lời] [❌ Bỏ] trong ô 📋 là link wezai-duyet:<việc>/<mã>
-- → chạy cai-dat\duyet.js (chuyển việc sang "Đã xử lý" + ghi quyet-dinh.md). Trả lời / Bỏ thì hỏi thêm một dòng.
local DUYET = HUB .. '/cai-dat/duyet.js'
local function run_duyet(window, args)
  local okc, out, err = wezterm.run_child_process(args)
  local msg = okc and (out or ''):gsub('%s+$', '') or ('❌ ' .. ((err or ''):gsub('%s+$', '')))
  window:toast_notification('WezTerm · bàn duyệt', msg ~= '' and msg or 'Đã ghi.', nil, 4000)
end
wezterm.on('open-uri', function(window, pane, uri)
  local verb, id = uri:match('^wezai%-duyet:(%a+)/(%w+)$')
  if not verb then return end -- link thường: mở như mặc định
  if verb == 'ok' then
    run_duyet(window, { 'node', DUYET, 'ok', id })
  else
    window:perform_action(act.PromptInputLine {
      description = verb == 'sua' and '✏️ Câu trả lời / yêu cầu của bạn (Enter = lưu · Esc = huỷ):'
        or '❌ Lý do bỏ (có thể để trống · Enter = bỏ · Esc = huỷ):',
      action = wezterm.action_callback(function(win, _, line)
        if line == nil or (verb == 'sua' and line == '') then return end
        run_duyet(win, { 'node', DUYET, verb, id, line })
      end),
    }, pane)
  end
  return false
end)

-- Báo cáo sáng: mỗi ngày từ 7 giờ, lần đầu WezTerm chạy thì Tổng quản gom tiến độ + việc chờ duyệt → Hion\bao-cao\<ngày>.md và bật lên
local function morning_report()
  local today = wezterm.strftime('%Y-%m-%d')
  if wezterm.GLOBAL.bao_cao_ngay == today or tonumber(wezterm.strftime('%H')) < 7 then return end
  wezterm.GLOBAL.bao_cao_ngay = today
  local f = io.open(HUB .. '/bao-cao/' .. today .. '.md', 'rb')
  if f then f:close() return end
  wezterm.background_child_process { 'node', HUB .. '/cai-dat/bao-cao-sang.js', '--mo' }
end

-- ===== Thanh tên trên đỉnh mỗi ô AI (02/10/2026) =====
-- Tab có từ 2 ô trở lên: mỗi ô Claude/Codex được tách thêm 1 ô cao 1 dòng phía trên chạy cai-dat\ten-o.js,
-- hiện "🤖 Claude · CHATBOT › thư-mục-con" trên nền màu dự án, giãn theo bề ngang ô. Ctrl+Shift+D bật/tắt.
-- Sổ ô tên: hdr_map()/hdr_save() ; thông tin vẽ ghi ra wez-ai\ten-o.json cho ten-o.js đọc.
local TEN_O_FILE = AIDIR .. '\\ten-o.json'
local TEN_O_JS = HUB .. '\\cai-dat\\ten-o.js'

-- Đóng ô tên = bỏ khỏi sổ + ghi lại ten-o.json → ten-o.js không thấy mình nữa thì tự thoát (~1 giây).
-- KHÔNG dùng perform_action(CloseCurrentPane / AdjustPaneSize, ô): 2 lệnh này tác động lên ô ĐANG CHỌN của tab,
-- không phải ô truyền vào → đóng / bóp nhầm ô AI (lỗi bóp nhỏ ô 18:16 02/10).
local function write_ten_o(map)
  local g = wezterm.GLOBAL
  local ok, old = pcall(wezterm.json_parse, g.ten_o_last or '{}')
  local oldo = (ok and type(old) == 'table' and type(old.o) == 'table') and old.o or {}
  local out = { tat = g.ten_o_tat and true or false, o = {} }
  for h in pairs(map) do out.o[h] = oldo[h] end
  local s = wezterm.json_encode(out)
  local f = io.open(TEN_O_FILE, 'w')
  if f then f:write(s) f:close() g.ten_o_last = s end
end
local function close_headers(window, tab)
  local map, n = hdr_copy(), 0
  for _, p in ipairs(tab:panes()) do
    local id = tostring(p:pane_id())
    if map[id] then
      map[id] = nil
      n = n + 1
    end
  end
  hdr_save(map)
  if n > 0 then write_ten_o(map) end
  return n
end

-- Phanh chống dựng ô tên liên tục (lỗi 18:16 02/10: tab bị thu còn 14 cột → "No space for split!" mỗi giây,
-- ô tên đặt sai chỗ bị đóng rồi dựng lại → ô AI bị bóp nhỏ dần):
--   mỗi ô AI: cách nhau ≥ 30 giây, tối đa 3 lần / 10 phút · mỗi lượt chỉ dựng 1 ô · ≥ 8 lần / phút → tự TẮT thanh tên.
local HDR_TRY, HDR_RATE = {}, {}
local function hdr_allow(id)
  local now = os.time()
  local x = HDR_TRY[id]
  if x and (now - x.t < 30 or (now - x.t < 600 and x.n >= 3)) then return false end
  return true
end
local function hdr_note(id)
  local now = os.time()
  local x = HDR_TRY[id]
  if not x or now - x.t >= 600 then x = { n = 0, t = now } end
  x.n, x.t = x.n + 1, now
  HDR_TRY[id] = x
  -- 03/10: chỉ đếm lần DỰNG LẠI cùng một ô (dấu hiệu lặp). Mở / xếp lại cả đội dựng nhiều ô mới một lúc là bình thường
  -- (trước đây đếm cả ô mới → xếp 2 đội cùng lúc đã làm phanh tự tắt nhầm).
  local r = {}
  if x.n >= 2 then r[1] = now end
  for _, t in ipairs(HDR_RATE) do if now - t < 60 then table.insert(r, t) end end
  HDR_RATE = r
  return #r
end
-- Phanh tự tắt (không phải bạn bấm Ctrl+Shift+D) → nạp lại cấu hình hoặc sau 5 phút thì tự bật lại
if wezterm.GLOBAL.ten_o_tu_tat or (wezterm.GLOBAL.ten_o_tat and not wezterm.GLOBAL.ten_o_tat_bang_tay) then
  wezterm.GLOBAL.ten_o_tu_tat, wezterm.GLOBAL.ten_o_tat, wezterm.GLOBAL.ten_o_last = nil, false, nil
end
local function process_headers(window)
  local g = wezterm.GLOBAL
  local map = hdr_copy()
  -- ô nào còn sống, nằm ở tab nào
  local alive = {}
  for _, mw in ipairs(wezterm.mux.all_windows()) do
    for _, t in ipairs(mw:tabs()) do
      for _, p in ipairs(t:panes()) do alive[tostring(p:pane_id())] = { pane = p, tab = t:tab_id() } end
    end
  end
  local has = {}
  for h, t in pairs(map) do -- bỏ cặp đã mất ô, hoặc ô AI đã bị đẩy sang tab khác
    if not alive[h] or not alive[t] or alive[h].tab ~= alive[t].tab then map[h] = nil else has[t] = h end
  end
  if g.ten_o_tu_tat and os.time() - g.ten_o_tu_tat >= 300 then -- phanh tự tắt quá 5 phút → thử bật lại
    g.ten_o_tu_tat, g.ten_o_tat, g.ten_o_last = nil, false, nil
  end
  local paused = (g.ten_o_hoan or 0) > os.time()
  local made = false
  for _, tab in ipairs(not g.ten_o_tat and not paused and window:mux_window():tabs() or {}) do
    local infos = tab:panes_with_info()
    local real = 0
    for _, info in ipairs(infos) do if not map[tostring(info.pane:pane_id())] then real = real + 1 end end
    local ts = tab:get_size()
    -- cửa sổ thu nhỏ / đang kéo cỡ: kích thước tab nhỏ hơn ô → bỏ qua, không tách
    local tab_ok = ts and ts.cols >= 30 and ts.rows >= 12
    if real >= 2 and tab_ok then
      for _, info in ipairs(infos) do
        local p = info.pane
        local id = tostring(p:pane_id())
        if not made and not map[id] and not has[id] and info.height > 8 and info.width >= 20
            and info.width <= ts.cols and hdr_allow(id) then
          local ai = pinfo(p).ai
          if ai == 'Claude' or ai == 'Codex' then
            made = true
            local ok, h = pcall(function()
              return p:split { direction = 'Top', size = 1, cwd = HUB, args = { 'node', TEN_O_JS } } -- size >= 1 = số dòng
            end)
            if ok and h then
              map[tostring(h:pane_id())] = id
              has[id] = tostring(h:pane_id())
              alive[tostring(h:pane_id())] = { pane = h, tab = tab:tab_id() }
              if info.is_active then p:activate() end -- trả lại ô đang chọn, không giành chỗ của ô khác
            else
              wezterm.log_error('ten-o split: ' .. tostring(h))
            end
            if hdr_note(id) >= 6 then
              g.ten_o_tat = true
              g.ten_o_tu_tat = os.time()
              g.ten_o_last = nil
              wezterm.log_error('ten-o: dựng quá 8 ô / phút → tự tắt thanh tên')
              window:toast_notification('WezTerm · đội AI', '⚠️ Thanh tên ô dựng lại liên tục → đã tự tắt (Ctrl+Shift+D để bật lại)', nil, 6000)
            end
          end
        end
      end
    end
  end
  -- ô tên phải nằm ngay trên ô AI của nó và cao 1 dòng (sau khi đổi chỗ / kéo / chia đều thì có thể sai)
  -- → bỏ khỏi sổ (ten-o.js tự thoát), vòng sau dựng lại đúng chỗ — có phanh hdr_allow nên không lặp liên tục
  local active_of = {}
  for _, t in ipairs(window:mux_window():tabs()) do
    local pos = {}
    for _, info in ipairs(t:panes_with_info()) do pos[tostring(info.pane:pane_id())] = info end
    local tap = t:active_pane()
    if tap then active_of[tostring(tap:pane_id())] = true end
    for h, tid in pairs(map) do
      local hi, ti = pos[h], pos[tid]
      local sai_cho = hi and ti and (hi.left ~= ti.left or hi.top + hi.height + 1 ~= ti.top)
      local cao = hi and hi.height > 1 and not paused
      if (sai_cho or cao) and hdr_allow(tid) then map[h] = nil end
    end
  end
  hdr_save(map)
  -- bấm vào ô tên → chuyển sang ô AI bên dưới
  local ap = window:active_pane()
  local target = ap and map[tostring(ap:pane_id())]
  if target and alive[target] then alive[target].pane:activate() end
  -- ghi thông tin cho ten-o.js
  local out = { tat = g.ten_o_tat and true or false, o = {} }
  if not g.ten_o_tat then
    for h, t in pairs(map) do
      local x = pinfo(alive[t].pane)
      out.o[h] = { pane = t, icon = x.icon, ai = x.ai or 'Terminal', proj = x.proj, logo = proj_logo(x.proj), sub = x.sub, color = proj_color(x.proj), active = active_of[t] or false }
    end
  end
  local s = wezterm.json_encode(out)
  if s ~= g.ten_o_last then
    local f = io.open(TEN_O_FILE, 'w')
    if f then f:write(s) f:close() g.ten_o_last = s end
  end
end

wezterm.on('ten-o-bat-tat', function(window, pane)
  local g = wezterm.GLOBAL
  g.ten_o_tat = not g.ten_o_tat
  g.ten_o_tat_bang_tay = g.ten_o_tat -- bạn tự tắt bằng phím → giữ tắt, không tự bật lại
  g.ten_o_last = nil
  if g.ten_o_tat then
    for _, t in ipairs(window:mux_window():tabs()) do close_headers(window, t) end
  end
  pcall(process_headers, window)
  window:toast_notification('WezTerm · đội AI', g.ten_o_tat and '🏷 Đã tắt thanh tên ô (Ctrl+Shift+D để bật lại)' or '🏷 Đã bật thanh tên ô', nil, 3000)
end)

-- Ctrl+Shift+F: tách ô đang chọn ra cửa sổ riêng (kéo thả tự do trên màn hình; Ctrl+Shift+G ở cửa sổ chính để kéo về)
wezterm.on('tach-o', function(window, pane)
  if is_header(pane) then pane = wezterm.mux.get_pane(tonumber(hdr_map()[tostring(pane:pane_id())])) or pane end
  if #window:active_tab():panes() < 2 then return end
  pane:move_to_new_window()
end)

-- Gộp lệnh: thêm ô / bấm Ctrl+Shift+E nhiều lần liên tiếp → chỉ chạy chia-deu.ps1 MỘT lần, 1,2 giây sau lần bấm cuối
-- (trước đây mỗi lần bấm bật 1 bản, 4 bản giành nhau kéo đường ranh → WezTerm đứng hình). Script cũng tự chặn chạy chồng.
local chia_deu_hen = { n = 0, pane = nil }
wezterm.on('chia-deu', function(window, pane)
  local tab = window:active_tab()
  if is_header(pane) then pane = wezterm.mux.get_pane(tonumber(hdr_map()[tostring(pane:pane_id())])) or pane end
  wezterm.GLOBAL.ten_o_hoan = os.time() + 20 -- chia xong mới dựng lại thanh tên
  close_headers(window, tab)
  chia_deu_hen.n = chia_deu_hen.n + 1
  chia_deu_hen.pane = pane:pane_id()
  local my = chia_deu_hen.n
  wezterm.time.call_after(2.0, function() -- 2 giây: chờ ô tên tự thoát (~1 giây) rồi mới chia
    if my ~= chia_deu_hen.n then return end -- đã có lần bấm mới hơn, để lần đó chạy
    wezterm.background_child_process { 'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
      '-File', HUB .. '\\cai-dat\\chia-deu.ps1', '-Pane', tostring(chia_deu_hen.pane) }
  end)
end)

wezterm.on('update-status', function(window, pane)
  -- Thanh tên bật lại 02/10 22h sau khi thêm phanh (hdr_allow / hdr_note); tắt tạm 18:18 vì dựng ô liên tục
  local okh, errh = pcall(process_headers, window)
  if not okh then wezterm.log_error('process_headers: ' .. tostring(errh)) end
  local okr, errr = pcall(morning_report)
  if not okr then wezterm.log_error('morning_report: ' .. tostring(errr)) end
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
  local okx, x = pcall(pinfo, pane) -- ô có thể vừa đóng
  if not okx then return end
  local dir, proj, sub, icon, ai = x.dir, x.proj, x.sub, x.icon, x.ai
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
  local okw, errw = pcall(codex_warn, window)
  if not okw then wezterm.log_error('codex_warn: ' .. tostring(errw)) end
  if ai then add { { Foreground = { Color = '#56b6c2' } }, { Text = icon .. ' ' .. ai } } end
  local where = { { Foreground = { Color = proj_color(proj) } }, { Attribute = { Intensity = 'Bold' } }, { Text = proj_logo(proj) .. ' ' .. proj } }
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
