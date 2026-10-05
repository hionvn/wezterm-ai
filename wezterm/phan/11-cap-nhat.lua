-- ===== Báo có bản cập nhật mới của đội AI trên GitHub (03/10/2026) =====
-- Mỗi 6 giờ chạy ngầm cap-nhat-tu-github.ps1 -Kiem (git fetch, không đổi gì) → ghi wez-ai\ban-moi.json;
-- có thay đổi mới → báo 1 lần / bản: "Ctrl+Shift+P → ⬆ Cập nhật đội AI". Máy chủ ("chuNhan": true) không báo.
-- Tắt: "tuKiemCapNhat": false trong ~\.wez-ai.json.
local REPO_DOI = machine.repo or (AI_ROOT .. '\\wezterm-ai')
local function kiem_ban_moi(window)
  if machine.chuNhan == true or machine.tuKiemCapNhat == false then return end
  local now = os.time()
  if now - (wezterm.GLOBAL.bm_doc or 0) < 60 then return end
  wezterm.GLOBAL.bm_doc = now
  if now - (wezterm.GLOBAL.bm_chay or 0) > 6 * 3600 then
    wezterm.GLOBAL.bm_chay = now
    wezterm.background_child_process { 'powershell.exe', '-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass',
      '-File', REPO_DOI .. '\\cap-nhat-tu-github.ps1', '-Kiem' }
  end
  local d = read_json(AIDIR .. '\\ban-moi.json')
  if d and (tonumber(d.moi) or 0) > 0 and d.dau and d.dau ~= wezterm.GLOBAL.bm_bao then
    wezterm.GLOBAL.bm_bao = d.dau
    window:toast_notification('WezTerm · đội AI', '⬆ Có bản cập nhật mới (' .. d.moi .. ' thay đổi). Ctrl+Shift+P → "Cập nhật đội AI".', nil, 12000)
  end
end

-- Đo thời gian từng việc của update-status (04/10/2026): lượt nào > CHAM_MS mili giây thì ghi wez-ai\cham.log
-- (giờ · tổng · việc chậm nhất) → biết đích xác việc nào làm GUI đứng hình. File tự cắt khi > 200 KB.
local CHAM_MS, CHAM_LOG = 300, AIDIR .. '\\cham.log'
local function chay(DO, ten, fn, ...)
  local t0 = ms()
  local ok, err = pcall(fn, ...)
  if not ok then wezterm.log_error(ten .. ': ' .. tostring(err)) end
  table.insert(DO, { ten, ms() - t0 })
  return ok, err
end
local function ghi_cham(DO, tong)
  table.sort(DO, function(a, b) return a[2] > b[2] end)
  local parts = {}
  for i = 1, math.min(4, #DO) do parts[i] = DO[i][1] .. ' ' .. math.floor(DO[i][2]) .. 'ms' end
  local so_o = 0
  for _, mw in ipairs(wezterm.mux.all_windows()) do for _, t in ipairs(mw:tabs()) do so_o = so_o + #t:panes() end end
  local f = io.open(CHAM_LOG, 'rb')
  local cu = f and f:seek('end') or 0
  if f then f:close() end
  f = io.open(CHAM_LOG, cu > 204800 and 'w' or 'a')
  if f then
    f:write(os.date('%Y-%m-%d %H:%M:%S') .. '  tổng ' .. math.floor(tong) .. 'ms  · ' .. so_o .. ' ô' .. (dang_xep() and ' · đang xếp' or '') .. '  · ' .. table.concat(parts, ' · ') .. '\n')
    f:close()
  end
end

local RIGHT_CLEARED = false
local function cap_nhat(window, pane, do_rieng)
  chay(do_rieng, 'kiem_ban_moi', kiem_ban_moi, window)
  -- Thanh tên bật lại 02/10 22h sau khi thêm phanh (hdr_allow / hdr_note); tắt tạm 18:18 vì dựng ô liên tục
  chay(do_rieng, 'process_headers', process_headers, window, pane)
  chay(do_rieng, 'morning_report', morning_report)
  chay(do_rieng, 'process_alerts', process_alerts, window, pane)
  chay(do_rieng, 'process_open', process_open, window)
  chay(do_rieng, 'auto_board', auto_board)
  chay(do_rieng, 'tu_ngu', tu_ngu) -- worker rảnh lâu → tự ngủ (đóng ô, nhớ phiên)
  chay(do_rieng, 'autosave', autosave)
  if wezterm.GLOBAL.hint_restore then
    wezterm.GLOBAL.hint_restore = false
    -- 03/10 (người dùng yêu cầu): mở WezTerm lên → HỎI "Resume phiên trước" hay "Mở mới", không tự mở lại nữa.
    -- Resume: mở lại mọi tab, ô đang làm dở tự làm tiếp · Mở mới: ở lại menu `ai` (sau vẫn mở lại được bằng Ctrl+Shift+O).
    -- "tuMoLai": true trong ~\.wez-ai.json = tự Resume không hỏi · false = không hỏi, không mở lại.
    local mw = window:mux_window()
    local fresh = #mw:tabs() == 1 and #mw:tabs()[1]:panes() == 1
    local d = read_json(LAYOUT.prev)
    if fresh and d and d.tabs and #d.tabs > 0 and machine.tuMoLai ~= false then
      local menu = pane
      local so_o = 0
      for _, t in ipairs(d.tabs) do so_o = so_o + #(t.panes or {}) end
      local function resume(w)
        -- mở lần lượt từng ô (04/10) → ô đầu tiên mở ngay, đóng ô menu được luôn; báo khi mở xong hết
        local n = restore_layout(w, d, function(so)
          w:toast_notification('WezTerm · đội AI', '✅ Đã mở lại ' .. so .. ' ô của phiên trước. Ô nào đang làm dở sẽ tự làm tiếp.', nil, 8000)
        end)
        if n > 0 then kill_pane(menu) end -- đóng ô menu `ai` lúc mở
      end
      if machine.tuMoLai == true then resume(window) return end
      window:perform_action(act.InputSelector {
        title = 'Mở WezTerm: làm tiếp phiên trước hay mở mới?  (Enter chọn · Esc = mở mới)',
        choices = {
          { id = 'resume', label = '⏮  Resume — mở lại ' .. #d.tabs .. ' tab, ' .. so_o .. ' ô của phiên trước (lưu lúc ' .. os.date('%H:%M %d/%m', d.t or 0) .. '), ô đang làm dở tự làm tiếp' },
          { id = 'moi', label = '🆕  Mở mới — bắt đầu từ menu chọn dự án (vẫn mở lại được sau bằng Ctrl+Shift+O)' },
        },
        action = wezterm.action_callback(function(w, _, id)
          if id == 'resume' then resume(w) end
        end),
      }, pane)
      return
    end
  end
  -- 03/10: BỎ phần thông tin bên phải thanh tab (⛽ hạn mức, AI, dự án, nhánh, số ô, giờ) để các tab có thêm chỗ
  -- (người dùng yêu cầu). Hạn mức vẫn theo dõi ngầm: cảnh báo Codex ≥ 90% + ghi cho bảng tổng quan (Ctrl+Shift+U).
  chay(do_rieng, 'fuel_cells', fuel_cells)
  chay(do_rieng, 'codex_warn', codex_warn, window)
  -- 04/10: chỉ 1 lần, khỏi gửi lệnh cho giao diện mỗi lượt. 06/10: BỎ chữ ⌨ góc trái (báo copy mode) — active_key_table +
  -- set_left_status mỗi lượt phải chờ luồng giao diện: đo 150–950 ms/lượt = thủ phạm chính làm WezTerm chậm khi ~22 ô chạy
  if not RIGHT_CLEARED then window:set_right_status(''); window:set_left_status(''); RIGHT_CLEARED = true end
end

-- CHỐNG CHẠY CHỒNG (04/10/2026): tách ô / mở tab trong Lua (pane:split, spawn_tab) là lệnh "nhường lượt" — trong lúc chờ,
-- WezTerm chạy luôn một lượt update-status khác (đo thật: 1 nhịp ghi 2 lần process_alerts). Lượt sau đọc sổ thanh tên CŨ
-- → dựng thêm thanh tên thứ 2 cho cùng ô, rồi 2 lượt ghi đè sổ của nhau → thanh thừa tự thoát, ô lệch, dựng lại…
-- = lỗi "dựng quá 8 ô / phút" trong log + giật GUI. Giờ: đang có lượt chạy dở thì lượt mới bỏ qua (nhịp sau 2 giây làm tiếp).
local US_DANG = 0 -- giờ bắt đầu lượt đang chạy dở (0 = không có); kẹt quá 15 giây thì coi như đã xong
-- GIỚI HẠN NHỊP (04/10/2026, chuột đơ): ngoài nhịp 2 giây, WezTerm còn gọi update-status MỖI LẦN tiêu đề ô đổi — ~20 ô Claude/Codex
-- quay ◐◓◑◒ liên tục → đo thật 45 lượt / 10 giây (đáng lẽ 5), mỗi lượt 0,3–3 giây trên luồng giao diện → chuột / gõ phím đơ.
-- Giờ: phần nặng chạy tối đa 1 lần / US_NHIP ms; lượt chen giữa chỉ làm việc rẻ: bấm vào ô tên 🏷 → nhảy xuống ô AI ngay.
local US_LAST, US_NHIP = 0, 1800
wezterm.on('update-status', function(window, pane)
  PERF.goi = (PERF.goi or 0) + 1
  if US_DANG > 0 and os.time() - US_DANG < 15 then return end
  if ms() - US_LAST < US_NHIP then
    local t = hdr_map()[tostring(pane:pane_id())]
    local ai = t and wezterm.mux.get_pane(tonumber(t))
    if ai then ai:activate() end
    return
  end
  US_LAST = ms()
  US_DANG = os.time()
  local do_rieng, t0 = {}, ms()
  local ok, err = pcall(cap_nhat, window, pane, do_rieng)
  local t_do = 0; for _, x in ipairs(do_rieng) do t_do = t_do + x[2] end
  table.insert(do_rieng, { 'chua_do', ms() - t0 - t_do }) -- 06/10: phần thời gian nằm ngoài mọi việc đã đo
  US_DANG = 0
  if not ok then wezterm.log_error('update-status: ' .. tostring(err)) end
  local tong = ms() - t0
  if tong > CHAM_MS then pcall(ghi_cham, do_rieng, tong) end
  PERF.us_n, PERF.us_ms = (PERF.us_n or 0) + 1, (PERF.us_ms or 0) + tong
  if os.time() - PERF.t >= 10 then
    local DV = AIDIR .. '\\dem-ve.log' -- giữ lại để theo dõi "đơ" về sau; > 200 KB thì ghi lại từ đầu
    local f0 = io.open(DV, 'rb')
    local cu = f0 and f0:seek('end') or 0
    if f0 then f0:close() end
    local f = io.open(DV, cu > 204800 and 'w' or 'a')
    if f then
      f:write(('%s  %ds · vẽ tên tab %d lần %.0fms CPU · tiêu đề cửa sổ %d lần · update-status gọi %d · chạy đủ %d lượt %.0fms\n'):format(
        os.date('%H:%M:%S'), os.time() - PERF.t, PERF.tab_n, PERF.tab_ms, PERF.win_n, PERF.goi or 0, PERF.us_n, PERF.us_ms))
      f:close()
    end
    PERF.tab_n, PERF.tab_ms, PERF.win_n, PERF.us_n, PERF.us_ms, PERF.goi, PERF.t = 0, 0, 0, 0, 0, 0, os.time()
  end
end)
