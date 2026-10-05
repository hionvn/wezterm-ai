-- ===== Bàn làm việc Tổng quản + menu dự án (thêm 01/10/2026; bản cũ: .wezterm.lua.bak-before-giai-doan1) =====
-- Ô tài liệu bên phải: can-duyet.md + sổ tiến độ các dự án, tự vẽ lại khi file đổi
local VIEWER = { 'powershell.exe', '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
  HUB .. '\\cai-dat\\can-duyet-view.ps1' }
-- Bảng tổng quan đội (Ctrl+Shift+U, 03/10/2026): cai-dat\bang-doi.js
local BOARD = { 'node', HUB .. '\\cai-dat\\bang-doi.js' }

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
local OPEN_LAST = 0
local function process_open(window)
  -- 06/10: mỗi lần mở 📄 = tạo tab/ô mới = giật 3–5 giây khi ~20 ô AI chạy (cham.log: 11,7 giây / 10 phút).
  -- Tối đa 1 lần / 3 phút; yêu cầu đến giữa chừng nằm chờ trong open.json (yêu cầu mới ghi đè cũ) → mở bản mới nhất.
  if os.time() - OPEN_LAST < 180 then return end
  local req_path = AIDIR .. '\\open.json'
  local f = io.open(req_path, 'rb')
  if not f then return end
  local s = f:read('*a')
  f:close()
  os.remove(req_path)
  local ok, req = pcall(wezterm.json_parse, s)
  if not ok or not req or not req.path then return end
  OPEN_LAST = os.time()
  local name = req.path:match('([^\\/]+)$') or req.path
  local tab, cur = window:active_tab(), window:active_pane()
  -- Thay ô 📄 cũ: đóng mọi ô tài liệu trong cửa sổ (ở tab đang xem hoặc ở tab 📄 riêng)
  for _, t in ipairs(window:mux_window():tabs()) do
    for _, p in ipairs(t:panes()) do
      if is_doc(p) then
        if p:pane_id() == cur:pane_id() then cur = nil end
        kill_pane(p)
      end
    end
  end
  local real = {}
  for _, p in ipairs(tab:panes()) do if not is_doc(p) and not is_header(p) then table.insert(real, p) end end
  if not cur then cur = real[1] end
  if not cur then return end
  if is_header(cur) then cur = wezterm.mux.get_pane(tonumber(hdr_map()[tostring(cur:pane_id())])) or cur end
  local doc
  if #real >= 2 then
    -- 03/10: tab đã có từ 2 ô (vd tab đội Manager + 4 worker) → mở tài liệu ở TAB RIÊNG, không chia ô:
    -- chia ô làm các worker bị bóp hẹp, mất chữ, đóng tài liệu xong bố cục không về như cũ.
    local dtab
    dtab, doc = window:mux_window():spawn_tab { cwd = HUB, args = DOCVIEW(req.path) }
    dtab:set_title('📄 ' .. name)
    tab:activate() -- vẫn ở tab đang xem; tài liệu chờ ở tab 📄
    window:toast_notification('WezTerm · đội AI', '📄 Tài liệu mới ở tab "📄 ' .. name .. '" (Ctrl+Tab để xem · đọc xong Ctrl+Shift+W)', nil, 8000)
  else
    -- tab chỉ 1 ô: mở bên phải như cũ; đóng tài liệu thì ô cũ tự trở lại đầy đủ
    doc = cur:split { direction = 'Right', size = 0.42, top_level = true, cwd = HUB, args = DOCVIEW(req.path) }
    cur:activate() -- giữ con trỏ ở ô bạn đang gõ
    window:toast_notification('WezTerm · đội AI', '📄 Đã mở tài liệu: ' .. name, nil, 5000)
  end
  local docs = wezterm.GLOBAL.docs or {} -- nhớ ô 📄 nào xem file nào (để lưu / khôi phục bố cục)
  docs[tostring(doc:pane_id())] = req.path
  wezterm.GLOBAL.docs = docs
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
