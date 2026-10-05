-- Nhiên liệu: hạn mức 5 giờ / tuần đã dùng của Claude (statusline.js ghi) và Codex (file phiên gần nhất)
local fuel_cache = { at = 0, cells = nil }
local FUEL_GLOB = {} -- [số tài khoản Codex] = { t, files }: kết quả quét thư mục phiên gần nhất
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
    -- 04/10: wezterm.glob ≈ 600 ms/lần trên máy này → chỉ quét lại thư mục mỗi 5 phút / tài khoản; giữa chừng dùng lại file phiên đã biết
    local gm = FUEL_GLOB[tk.so or 0]
    if gm and os.time() - gm.t < 300 then
      files = gm.files
    else
      for d = 0, 6 do -- thư mục sessions/YYYY/MM/DD: tìm ngày gần nhất có phiên (trước đây quét cả lịch sử → giật mỗi phút)
        files = wezterm.glob(root .. os.date('%Y/%m/%d', os.time() - d * 86400) .. '/*.jsonl')
        if #files > 0 then break end
      end
      table.sort(files)
      FUEL_GLOB[tk.so or 0] = { t = os.time(), files = files }
    end
    -- 03/10: file phiên không đổi cỡ thì dùng lại kết quả cũ; đọc 96KB cuối thay vì 256KB (mỗi phút × 3 tài khoản → giật)
    local f, size = files[#files] and io.open(files[#files], 'rb'), nil
    if f then size = f:seek('end') f:close() end
    local memo = FUEL_MEMO[tk.so or 0]
    local s = nil
    if memo and memo.file == files[#files] and memo.size == size then
      if memo.row then table.insert(codex, memo.row) end
    else
      FUEL_MEMO[tk.so or 0] = { file = files[#files], size = size, row = memo and memo.row }
      -- 06/10: phiên vừa mở chưa có số hạn mức → lùi về tối đa 5 phiên trước (trước đây tài khoản biến mất khỏi
      -- fuel-codex.json → wez.ps1 "không đọc được hạn mức Codex" → vai kẹt ở Grok mãi)
      -- nhiều ô cùng tài khoản chạy song song → file mới nhất theo tên chưa chắc có số mới nhất: gom 10 phiên cuối,
      -- lấy khung có giờ làm mới muộn nhất, trong khung đó lấy % cao nhất (trong 1 khung % chỉ tăng)
      for i = #files, math.max(1, #files - 9), -1 do
        local t = read_file(files[i], 98304)
        if t then
          for u, r in t:gmatch('"primary":{"used_percent":([%d%.]+),"window_minutes":%d+,"resets_at":(%d+)}') do
            u, r = tonumber(u), tonumber(r)
            if not s or r > s.r5 or (r == s.r5 and u > s.p5) then s = s or {}; s.p5, s.r5 = u, r end
          end
          for u, r in t:gmatch('"secondary":{"used_percent":([%d%.]+),"window_minutes":%d+,"resets_at":(%d+)}') do
            u, r = tonumber(u), tonumber(r)
            if s and (not s.rw or r > s.rw or (r == s.rw and u > s.pw)) then s.pw, s.rw = u, r end
          end
        end
      end
      if not s and memo and memo.row then table.insert(codex, memo.row) end -- vẫn chưa có → giữ số cũ
    end
    if s then
      local p5, r5, pw, rw = s.p5, s.r5, s.pw, s.rw
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
  -- ghi hạn mức Codex ra file cho bảng tổng quan (cai-dat\bang-doi.js) — thanh bên phải đã bỏ (03/10)
  local fx = io.open(AIDIR .. '\\fuel-codex.json', 'w')
  if fx then
    local rows = {}
    -- 06/10: đã qua giờ làm mới → ghi 0 (trước ghi số cũ 100% → wez.ps1 tưởng Codex vẫn hết, không chuyển về)
    local now = os.time()
    for _, c in ipairs(codex) do rows[#rows + 1] = { icon = c.icon, ten = c.ten,
      five = (c.five_reset and c.five_reset < now) and 0 or c.five, week = (c.week_reset and c.week_reset < now) and 0 or c.week } end
    -- bảng rỗng: json_encode ghi "{}" thay vì "[]" → bang-doi.js lỗi "fx is not iterable" (06/10)
    fx:write(#rows == 0 and '[]' or wezterm.json_encode(rows)) fx:close()
  end
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