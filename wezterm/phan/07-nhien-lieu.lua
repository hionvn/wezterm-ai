-- Nhiên liệu Codex cho codex_warn. 19/10: phần quét phiên Codex (wezterm.glob + đọc 30 file phiên) CHUYỂN sang Node
-- (cai-dat\han-muc.js ghi fuel-codex.json mỗi phút) — trong Lua nó làm lượt update-status mất 260–7500 ms (cham.log 19/10).
-- Lua giờ chỉ đọc file JSON nhỏ đó tối đa 1 lần / 60 giây.
local fuel_cache = { at = 0, codex = {} }
local function fuel_cells()
  if os.time() - fuel_cache.at < 60 then return end
  fuel_cache.at = os.time()
  local rows = read_json(AIDIR .. '/fuel-codex.json')
  if type(rows) == 'table' then fuel_cache.codex = rows end
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

-- Tên ngắn của phiên trong ô (bỏ dấu quay ✳◐… của Claude, bỏ "Dự án | Ready |" của Codex), tối đa n ký tự
local SPIN = { ['✳'] = true, ['◐'] = true, ['◓'] = true, ['◑'] = true, ['◒'] = true, ['⠂'] = true, ['⠐'] = true }
local function short_title(t, proj, n)
  t = t or ''
  local last = t:match('.*|%s*(.-)%s*$') -- Codex: "Chatbot | Ready | Chatbot · ⚙ Engineer" → phần sau dấu | cuối
  if last then t = last end
  local first, rest = t:match('^(%S+)%s+(.*)$')
  if first and SPIN[first] then t = rest end
  if t == '' or t:lower():find('powershell') or t:lower() == (proj or ''):lower() then return nil end
  if utf8.len(t) and utf8.len(t) > n then t = t:sub(1, (utf8.offset(t, n + 1) or (#t + 1)) - 1) .. '…' end
  return t
end

-- Dự án + nhãn ngắn của một tab (dùng chung cho thanh tab và tiêu đề cửa sổ)
local function tab_info(tab)
  local p = tab.active_pane
  local id = tostring(hdr_map()[tostring(p.pane_id)] or p.pane_id) -- đang đứng ở ô tên → lấy ô AI bên dưới
  local x = PANE_LAST[id]
  local proj = x and x.proj or split_project(pane_dir(p))
  local title = tab.tab_title or ''
  local logo = proj_logo(proj)
  if title ~= '' then
    if title:sub(1, 4) == '📄' then logo = '📄' end
    -- "💬 Chatbot · đội" → bỏ logo đầu (đã vẽ riêng); tài liệu "📄 ten-file.html" → bỏ đuôi
    title = title:gsub('^%S+%s+', '', 1):gsub('%.html?$', ''):gsub('%.md$', '')
  end
  return proj, logo, title, x
end

-- 03/10 làm lại cho dễ nhìn: mỗi tab là 1 khối màu riêng của dự án.
--   Tab đang xem: nền màu dự án, chữ đậm tối · tab khác: vạch màu dự án ▌ + chữ xám
--   🔔 nền đỏ = cần duyệt · ✅ nền xanh dương = vừa xong · bỏ biểu tượng AI 🤖/🧩 cho đỡ rối
--   Tên: tab có đặt tên (đội, 📄 tài liệu) thì ghi tên đó; 2 tab cùng dự án mà không đặt tên thì thêm tên phiên ngắn
-- 19/10/2026 (người dùng yêu cầu): HIỆN LẠI hạn mức mọi gói AI ở góc PHẢI thanh tab (Claude 2 tài khoản · GPT 9router · Grok · Codex).
-- Số do cai-dat\han-muc.js (Node nền) gom 60 giây/lần → wez-ai\han-muc.json. Lua chỉ đọc file 30 giây/lần và CHỈ gọi
-- set_right_status khi chuỗi đổi (mỗi lần gọi phải chờ luồng giao diện — bài học 06/10). File cũ > 5 phút → bật lại script nền.
local HM = { at = 0, text = nil, fmt = nil, spawn = 0, shown = {} }
local function han_muc_status(window)
  local now = os.time()
  if now - HM.at >= 30 then
    HM.at = now
    local d = read_json(AIDIR .. '/han-muc.json')
    if d and d.text and d.text ~= HM.text then
      local cells = {}
      for _, p in ipairs(d.parts or {}) do
        cells[#cells + 1] = { Foreground = { Color = p.c } }
        cells[#cells + 1] = { Text = p.t }
      end
      HM.text, HM.fmt = d.text, wezterm.format(cells)
    end
    if (not d or now - (d.t or 0) > 300) and now - HM.spawn > 300 then
      HM.spawn = now
      wezterm.background_child_process { 'node', HUB .. '/cai-dat/han-muc.js', 'chay' } -- đã có bản chạy thì nó tự thoát
    end
  end
  local id = window:window_id()
  if HM.fmt and HM.shown[id] ~= HM.text then
    -- 19/10 chiều: thử sang trái rồi người dùng chọn lại GÓC PHẢI. Lần đầu mỗi cửa sổ xoá bản bên trái.
    if not HM.shown[id] then window:set_left_status('') end
    HM.shown[id] = HM.text; window:set_right_status(HM.fmt)
  end
end
