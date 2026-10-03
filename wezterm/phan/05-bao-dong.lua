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
-- Ghi sổ đội (wez-ai\doi\<dự án>.json). json_encode biến bảng RỖNG thành {} → đội chưa có worker bị ghi "worker": {}
-- → ten-o.js gọi ws.map / ws.find lỗi, ô tên chết ngay khi mở → dựng lại liên tục (bắt được 04/10) → ép lại thành [].
-- Danh sách file sổ đội (wez-ai\doi\*.json). wezterm.glob trên máy này ≈ 600–700 ms/lần (đo 04/10) → quét tối đa 2 phút/lần,
-- tự ngủ (tu_ngu) + tự lưu (doi_map) dùng chung. Đội mới mở thì chậm nhất 2 phút mới được tính.
local DOI_DS = { t = -1000, ds = {} }
local function so_doi_files()
  if os.time() - DOI_DS.t >= 120 then DOI_DS = { t = os.time(), ds = wezterm.glob(AIDIR:gsub('\\', '/') .. '/doi/*.json') } end
  return DOI_DS.ds
end
local function ghi_so_doi_file(path, r)
  local s = wezterm.json_encode(r):gsub('"worker":%{%}', '"worker":[]')
  local f = io.open(path, 'w')
  if f then f:write(s) f:close() end
end

-- "Đang xếp ô" (04/10/2026): lúc mở lại phiên / mở đội, WezTerm phải dựng nhiều ô liên tục. Trong lúc đó các việc nền
-- của update-status (dựng thanh tên 🏷, bảng 📊 tự hiện, worker tự ngủ, tự lưu bố cục) chen vào tách / đóng ô
-- → bố cục giành nhau, GUI đứng hình (con trỏ quay mãi). Cờ: wezterm.GLOBAL.xep_den (Lua tự đặt khi mở lại phiên)
-- hoặc file wez-ai\dang-xep.txt = giờ hết hạn (wez.ps1 doi ghi khi mở đội). Hết hạn thì tự bỏ, không cần dọn.
local XEP_MEMO = { t = -1, den = 0 }
local function dang_xep()
  local now = os.time()
  if (wezterm.GLOBAL.xep_den or 0) > now then return true end
  if XEP_MEMO.t ~= now then -- đọc file tối đa 1 lần / giây
    XEP_MEMO.t = now
    local f = io.open(AIDIR .. '\\dang-xep.txt', 'rb')
    XEP_MEMO.den = f and tonumber((f:read('*a') or ''):match('%d+')) or 0
    if f then f:close() end
  end
  return XEP_MEMO.den > now
end
-- Đồng hồ mili giây (đo việc nào làm GUI chậm)
local function ms()
  local ok, v = pcall(function() return tonumber(wezterm.time.now():format('%s%.3f')) end)
  return (ok and v or os.time()) * 1000
end

-- Báo động: Claude ghi file qua hooks (cai-dat\wez-alert.js); Codex thì đoán từ tiêu đề ô.
-- File: %LOCALAPPDATA%\wez-ai\alerts\<PANEID>.json = { kind = 'need' | 'done', text, t }
-- Trạng thái (cho wez.ps1 send / cho): wez-ai\state\<PANEID>.json = { state = 'work' | 'idle' | 'need', ai, t }
local ALERTS = AIDIR .. '\\alerts'
local STATE = AIDIR .. '\\state'
local tab_alert, toasted, last_state = {}, {}, {}
local TAB_STAT = {} -- [tab_id] = { work, need } — process_alerts đếm mỗi 2 giây, format-tab-title đọc
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
local PANE_SLOW = 30 -- 04/10: 6 → 30 giây. Đo thật: 14 ô = process_alerts 450–650 ms mỗi nhịp 2 giây (GUI khựng đều).
                    -- Loại AI + trạng thái đã đọc từ TIÊU ĐỀ ô (nhanh, mỗi giây); tiến trình + thư mục hiếm khi đổi.
-- 04/10: mỗi câu hỏi chậm trên Windows chụp lại CẢ cây tiến trình (claude/codex kéo theo nhiều node MCP) → vài chục ms/lần,
-- chạy ngay trên luồng GUI. Mở lại phiên 20 ô thì các ô hết hạn cùng một nhịp → dồn 40 câu hỏi vào 1 lượt → đứng hình.
-- Giới hạn: làm mới tối đa SLOW_MAX ô mỗi giây (ô MỚI chưa có gì thì vẫn hỏi ngay); ô chưa tới lượt dùng tạm bản cũ.
local SLOW_MAX, SLOW_BUDGET = 2, { t = -1, n = 0 }
local function pinfo(p)
  local now = os.time()
  if PANE_NOW.t ~= now then PANE_NOW = { t = now, m = {} } end
  if SLOW_BUDGET.t ~= now then SLOW_BUDGET.t, SLOW_BUDGET.n = now, 0 end
  local id = p:pane_id()
  local x = PANE_NOW.m[id]
  if x then return x end
  local sc = PANE_SLOWC[id]
  if not sc or (now - sc.t >= PANE_SLOW and SLOW_BUDGET.n < SLOW_MAX) then
    SLOW_BUDGET.n = SLOW_BUDGET.n + 1
    local t0 = ms()
    local proc = p:get_foreground_process_name() or ''
    local t1 = ms()
    sc = { t = now, proc = proc, cwd = p:get_current_working_dir() }
    PANE_SLOWC[id] = sc
    local t2 = ms() -- đo thật mỗi câu hỏi Windows (04/10): chậm > 80 ms thì ghi log GUI
    if t2 - t0 > 80 then wezterm.log_warn(('pinfo chậm: ô %d · tiến trình %.0fms · thư mục %.0fms'):format(id, t1 - t0, t2 - t1)) end
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
  if x.ai == 'Codex' then -- which_ai: theo tiến trình HOẶC tiêu đề "| Ready |"… (tiến trình giờ chỉ hỏi lại mỗi 30 giây)
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

local ALERT_SCAN = { t = 0 }
-- 04/10 (chuột đơ): window:is_focused() / window:active_pane() phải chờ luồng giao diện trả lời — đo thật 300–1250 ms/lượt
-- khi ~20 ô AI quay tiêu đề liên tục. Giờ: ô đang chọn lấy từ tham số update-status (WezTerm truyền sẵn),
-- cửa sổ có đang được chọn hay không thì nhớ qua sự kiện window-focus-changed (chỉ chạy khi đổi focus).
local WIN_FOCUS = {}
local OLIST_LAST, OLIST_T = nil, 0
wezterm.on('window-focus-changed', function(window, pane) WIN_FOCUS[window:window_id()] = window:is_focused() end)
local function process_alerts(window, apane)
  local T0, TT = ms(), { pinfo = 0, tt = 0, file = 0, n = 0 } -- đo từng phần (04/10)
  local focused = WIN_FOCUS[window:window_id()]
  if focused == nil then focused = window:is_focused(); WIN_FOCUS[window:window_id()] = focused end
  local active = tostring((apane or window:active_pane()):pane_id())
  TT.win = ms() - T0
  local alive, pane_tab, pane_proj = {}, {}, {}
  local olist = {} -- 04/10: danh sách ô cho bang-doi.js (thay `wezterm cli list` mỗi 3 giây — mỗi lần 1–3 giây trên luồng giao diện)
  local stat = {} -- [tab] = { work = số ô đang làm, need = số ô cần duyệt } → hiện trên tên tab
  -- Duyệt mọi cửa sổ WezTerm (trước đây chỉ cửa sổ hiện tại → mở 2 cửa sổ thì xoá nhầm báo động của cửa sổ kia)
  for _, mw in ipairs(wezterm.mux.all_windows()) do
    for _, tab in ipairs(mw:tabs()) do
      local tp = ms()
      local tab_panes = tab:panes()
      TT.panes = (TT.panes or 0) + ms() - tp
      for _, p in ipairs(tab_panes) do
        TT.lap = ms()
        local id = tostring(p:pane_id())
        alive[id], pane_tab[id] = true, tostring(tab:tab_id())
        olist[#olist + 1] = { id = p:pane_id(), tab = tab:tab_id(), p = p }
        if not is_header(p) then -- ô tên 🏷: không có AI, khỏi hỏi Windows
          local ta = ms()
          local okp, x = pcall(pinfo, p)
          TT.pinfo, TT.n = TT.pinfo + ms() - ta, TT.n + 1
          TT.hdr = (TT.hdr or 0) + (ta - (TT.lap or ta))
          pane_proj[id] = (okp and x.proj ~= '?') and x.proj or nil
          local state, who = title_state(p)
          local tb = ms()
          -- đếm cho tên tab: Claude đang làm = tiêu đề có dấu quay ◐◓◑◒; Codex đang làm = 'work'
          local t1 = okp and x.title:match('^(%S+)') or ''
          local busy = state == 'work' or (not state and (t1 == '◐' or t1 == '◓' or t1 == '◑' or t1 == '◒'))
          local tid0 = pane_tab[id]
          stat[tid0] = stat[tid0] or { work = 0, need = 0 }
          if busy then stat[tid0].work = stat[tid0].work + 1 end
          if state then
            local prev = last_state[id]
            last_state[id] = state
            if state == 'need' and prev ~= 'need' then write_alert(id, 'need', who .. ' cần bạn duyệt')
            elseif state == 'idle' and (prev == 'work' or prev == 'need') then write_alert(id, 'done', who .. ' đã làm xong') end
            sync_state(id, state, 'codex')
          else
            fix_claude_state(id, okp and x.title or '')
          end
          TT.file = TT.file + ms() - tb
        end
      end
    end
  end
  TT.loop = ms() - T0
  -- ghi wez-ai\o-list.json (dạng giống `wezterm cli list --format json`: pane_id, tab_id, title, cwd) — chỉ ghi khi đổi
  pcall(function()
    local arr = {}
    for i, o in ipairs(olist) do
      local x = PANE_LAST[tostring(o.id)]
      arr[i] = { pane_id = o.id, tab_id = o.tab, title = x and x.title or (o.p:get_title() or ''),
        cwd = x and x.dir and ('file:///' .. x.dir:gsub('\\', '/')) or '' }
    end
    local s = wezterm.json_encode(arr)
    if s ~= OLIST_LAST or os.time() - OLIST_T >= 10 then
      local f = io.open(AIDIR .. '\\o-list.json', 'w')
      if f then f:write(s) f:close() OLIST_LAST, OLIST_T = s, os.time() end
    end
  end)
  tab_alert = {}
  -- 04/10: đo thật lúc chạy 34 ô: wezterm.glob thư mục alerts mỗi nhịp ≈ 600 ms (phần còn lại của process_alerts chỉ vài ms).
  -- Giờ: mỗi nhịp mở thẳng file của từng ô đang sống (io.open, rất nhanh); quét cả thư mục 2 phút/lần để dọn file của ô đã đóng.
  local paths, quet = {}, os.time() - ALERT_SCAN.t >= 120
  if quet then
    ALERT_SCAN.t = os.time()
    paths = wezterm.glob(ALERTS:gsub('\\', '/') .. '/*.json')
  else
    for id in pairs(alive) do if not hdr_map()[id] then paths[#paths + 1] = ALERTS .. '\\' .. id .. '.json' end end
  end
  for _, path in ipairs(paths) do
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
          if v.kind == 'need' then stat[tid] = stat[tid] or { work = 0, need = 0 }; stat[tid].need = stat[tid].need + 1 end
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
  TAB_STAT = stat
  local tong = ms() - T0
  if tong > 250 then
    wezterm.log_warn(('process_alerts %.0fms: window %.0f · tab:panes %.0f · đầu vòng(id/header) %.0f · pinfo %.0f (%d ô) · trạng thái %.0f · cả vòng %.0f · báo động %.0f'):format(
      tong, TT.win or 0, TT.panes or 0, TT.hdr or 0, TT.pinfo, TT.n, TT.file, TT.loop or 0, tong - (TT.loop or 0)))
  end
  -- Dọn trạng thái của ô đã đóng (số ô có thể được dùng lại sau khi mở lại WezTerm)
  if quet then -- cùng nhịp quét 2 phút
    for _, path in ipairs(wezterm.glob(STATE:gsub('\\', '/') .. '/*.json')) do
      local id = path:match('(%d+)%.json$')
      if id and not alive[id] then os.remove(path) end
    end
  end
end
