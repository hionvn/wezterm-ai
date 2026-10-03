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
local HDR_TRY, HDR_RATE, HDR_FIX = {}, {}, {} -- HDR_FIX[ô tên] = { t, n }: số lần đã thu ô tên bị giãn cao
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
-- 04/10: "thanhTenO": false trong ~\.wez-ai.json → tắt hẳn thanh tên cho nhẹ (Ctrl+Shift+D vẫn bật tạm được)
if machine.thanhTenO == false and not wezterm.GLOBAL.ten_o_tat then
  wezterm.GLOBAL.ten_o_tat, wezterm.GLOBAL.ten_o_tat_bang_tay, wezterm.GLOBAL.ten_o_last = true, true, nil
end
local function process_headers(window, apane)
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
    if not alive[h] or not alive[t] or alive[h].tab ~= alive[t].tab then
      if not g.ten_o_tat then wezterm.log_warn('ten-o bỏ ' .. h .. '/' .. t .. ': ' .. (not alive[h] and 'ô tên đã mất' or not alive[t] and 'ô AI đã đóng' or 'khác tab')) end
      map[h] = nil
    else has[t] = h end
  end
  if g.ten_o_tu_tat and os.time() - g.ten_o_tu_tat >= 300 then -- phanh tự tắt quá 5 phút → thử bật lại
    g.ten_o_tu_tat, g.ten_o_tat, g.ten_o_last = nil, false, nil
  end
  local paused = (g.ten_o_hoan or 0) > os.time() or dang_xep() -- 04/10: đang mở lại / xếp đội → chưa dựng thanh tên
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
              -- trả lại ô đang chọn, không giành chỗ của ô khác. CHỈ ở tab đang xem: pane:activate() ở tab khác
              -- làm màn hình nhảy sang tab đó (03/10). Tab nền: thanh tên tạm là ô chọn, lúc bạn vào tab thì
              -- đoạn "bấm vào ô tên" bên dưới tự chuyển về ô AI ngay dưới nó.
              if info.is_active and tab:tab_id() == window:active_tab():tab_id() then p:activate() end
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
      -- 04/10: ô tên đúng chỗ nhưng bị giãn cao (đóng ô bên cạnh / đổi cỡ cửa sổ chia thêm dòng cho mọi ô) → THU LẠI 1 dòng
      -- (đường ranh dưới ô tên dịch lên) thay vì phá đi dựng lại: dựng lại = 2 lần đổi cỡ ô AI = Claude/Codex vẽ lại cả hội thoại 2 lần.
      -- Thu 2 lần không được thì mới bỏ để dựng lại như cũ.
      if cao and not sai_cho then
        local k = HDR_FIX[h]
        if not k or os.time() - k.t >= 4 then
          if not k or k.n < 2 then
            HDR_FIX[h] = { t = os.time(), n = (k and k.n or 0) + 1 }
            wezterm.background_child_process { wezterm.executable_dir .. '\\wezterm.exe', 'cli', '--no-auto-start',
              'adjust-pane-size', '--pane-id', h, '--amount', tostring(hi.height - 1), 'Up' }
            cao = false
          end
        else
          cao = false -- vừa thu, đợi WezTerm cập nhật cỡ
        end
      elseif hi and hi.height == 1 then
        HDR_FIX[h] = nil
      end
      if (sai_cho or cao) and hdr_allow(tid) then
        -- 04/10: ghi lý do vào log GUI để biết vì sao thanh tên bị dựng lại (phanh "dựng quá 8 ô / phút")
        wezterm.log_warn(('ten-o bỏ %s/%s: %s · tên %dx%d@%d,%d · AI %dx%d@%d,%d'):format(h, tid, sai_cho and 'sai chỗ' or 'giãn cao',
          hi.width, hi.height, hi.left, hi.top, ti and ti.width or -1, ti and ti.height or -1, ti and ti.left or -1, ti and ti.top or -1))
        map[h] = nil; HDR_FIX[h] = nil
      end
    end
  end
  hdr_save(map)
  -- bấm vào ô tên → chuyển sang ô AI bên dưới
  local ap = apane or window:active_pane() -- 04/10: ô đang chọn do update-status truyền sẵn (khỏi chờ luồng giao diện)
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
