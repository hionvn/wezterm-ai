-- ===== Bảng 📊 (báo cáo + checklist) tự hiện bên phải ô Tổng quản khi agent làm việc (03/10/2026) =====
-- Ô Tổng quản: sổ wez-ai\doi\Hion.json (manager.o). Có agent đang làm (⏳) hoặc còn việc ☐ chưa xong → mở bảng bên phải;
-- mọi agent rảnh + hết việc dở quá 3 phút → tự đóng (chỉ bảng tự mở; bảng mở bằng Ctrl+Shift+U thì để yên).
-- Tắt tự hiện: "bangTuDong": false trong ~\.wez-ai.json.
local BOARD_MEMO = { t = 0, chua = 0, ranh_tu = nil }
-- get_pane báo LỖI (không trả nil) khi ô đã đóng → bọc pcall
local function pane_or_nil(o)
  if not o then return nil end
  local ok, p = pcall(wezterm.mux.get_pane, tonumber(o))
  return ok and p or nil
end
local function board_pane()
  local o = wezterm.GLOBAL.board_o
  return pane_or_nil(o)
end

-- ===== Worker tự NGỦ khi rảnh lâu (03/10/2026) — đỡ RAM + hạn mức khi chạy nhiều dự án =====
-- Worker 🟢 rảnh liên tục NGU_PHUT phút, không còn việc ☐ dở (viec.json), không chờ bạn (🔔) → ghi phiên vào sổ đội
-- (ngu = true, session) rồi đóng ô. Giao việc bằng `wez.ps1 send DựÁn.Vai` → tự thức, mở lại ĐÚNG phiên cũ.
-- Manager + Tổng quản không bao giờ ngủ. Đổi thời gian: "nguSauPhut" trong ~\.wez-ai.json (0 = tắt tự ngủ).
local NGU_PHUT = tonumber(machine.nguSauPhut) or 20
local NGU_RANH, NGU_MEMO = {}, { t = 0 }
local function tu_ngu()
  if NGU_PHUT <= 0 then return end
  local now = os.time()
  if now - NGU_MEMO.t < 30 then return end -- soát mỗi 30 giây là đủ
  NGU_MEMO.t = now
  local con_viec = {}
  for _, v in ipairs(read_json(AIDIR .. '\\viec.json') or {}) do
    if type(v) == 'table' and not v.xong and not v.bo and v.o then con_viec[tostring(v.o)] = true end
  end
  local home = (os.getenv('USERPROFILE') or HOME)
  for _, path in ipairs(wezterm.glob(AIDIR:gsub('\\', '/') .. '/doi/*.json')) do
    local r = read_json(path)
    if r and r.du_an and r.du_an ~= 'Hion' and type(r.worker) == 'table' and #r.worker > 0 then
      local doi_ghi = false
      for _, w in ipairs(r.worker) do
        local id = w.o and tostring(w.o) or ''
        local p = id ~= '' and pane_or_nil(id) or nil
        if p then
          local t = (PANE_LAST[id] and PANE_LAST[id].title) or ''
          local ranh = t:find('✳', 1, true) or t:find('| Ready |', 1, true)
          local al = read_json(ALERTS .. '\\' .. id .. '.json')
          if ranh and not con_viec[id] and not (al and al.kind == 'need') then
            NGU_RANH[id] = NGU_RANH[id] or now
            if now - NGU_RANH[id] >= NGU_PHUT * 60 then
              -- phiên Claude: lấy từ file trạng thái, CHỈ tin khi bản ghi phiên nằm đúng thư mục dự án
              -- (03/10: số ô bị dùng lại sau khởi động lại từng làm lẫn phiên Tổng quản sang ô Design)
              -- ưu tiên phiên ghi trong sổ đội (nguồn chuẩn theo VAI); file trạng thái theo số ô có thể lẫn sau khởi động lại
              local st = read_json(STATE .. '\\' .. id .. '.json')
              local sid = (w.session ~= '' and w.session) or (st and st.session)
              if not sid or sid == '' then
                -- chưa có file trạng thái (vd vừa Resume, chưa làm gì) → lấy mã phiên từ lệnh đang chạy: claude --resume <mã>
                local okf, fp = pcall(function() return p:get_foreground_process_info() end)
                if okf and fp and fp.argv then
                  for i, a in ipairs(fp.argv) do if a == '--resume' and fp.argv[i + 1] then sid = fp.argv[i + 1] end end
                end
              end
              if sid and sid ~= '' then
                local f = io.open(home .. '\\.claude\\projects\\E--AI-' .. r.du_an .. '\\' .. sid .. '.jsonl', 'rb')
                if f then f:close() else sid = nil end
              end
              if tostring(w.ai or ''):lower() == 'codex' or sid then -- Codex mở lại theo tên phiên, không cần sid
                w.session = sid or w.session
                w.ngu, w.ngu_luc, w.o = true, now, ''
                kill_pane(p)
                doi_ghi = true
                wezterm.log_warn('tu_ngu: ' .. r.du_an .. '.' .. tostring(w.vai) .. ' ngủ (ô ' .. id .. ')')
              end
              NGU_RANH[id] = nil
            end
          else
            NGU_RANH[id] = nil
          end
        end
      end
      if doi_ghi then
        local f = io.open(path, 'w')
        if f then f:write(wezterm.json_encode(r)) f:close() end
      end
    end
  end
end
local function open_board(beside, auto)
  local nb = beside:split { direction = 'Right', size = 0.45, top_level = true, cwd = HUB, args = BOARD } -- top_level: bảng chiếm trọn mép phải, không bóp 1 ô
  wezterm.GLOBAL.board_o, wezterm.GLOBAL.board_auto = tostring(nb:pane_id()), auto
  BOARD_MEMO.mo_luc = os.time()
  beside:activate() -- giữ con trỏ ở ô bạn đang gõ
  return nb
end
local function auto_board()
  if machine.bangTuDong == false then return end
  local r = read_json(AIDIR .. '\\doi\\Hion.json')
  local tq = r and r.manager and pane_or_nil(r.manager.o)
  if not tq then return end
  local now = os.time()
  if now - BOARD_MEMO.t >= 10 then -- đếm việc ☐ chưa xong mỗi 10 giây
    BOARD_MEMO.t = now
    local vs, n = read_json(AIDIR .. '\\viec.json') or {}, 0
    for _, v in ipairs(vs) do if not v.xong and not v.bo then n = n + 1 end end
    BOARD_MEMO.chua = n
  end
  local work = 0
  for _, st in pairs(TAB_STAT) do work = work + (st.work or 0) end
  -- chính ô Tổng quản đang làm (đang trả lời bạn) thì không tính là "agent làm việc"
  local x = PANE_LAST[tostring(tq:pane_id())]
  local t1 = x and (x.title or ''):match('^(%S+)') or ''
  if t1 == '◐' or t1 == '◓' or t1 == '◑' or t1 == '◒' then work = work - 1 end
  local busy = work > 0 or BOARD_MEMO.chua > 0
  local b = board_pane()
  if busy then
    BOARD_MEMO.ranh_tu = nil
    -- phanh chống nháy (03/10): bảng vừa mở < 60 giây mà đã mất (lỗi / bạn tự đóng) → không mở lại ngay
    if not b and os.time() - (BOARD_MEMO.mo_luc or 0) >= 60 then open_board(tq, true) end
  elseif b and wezterm.GLOBAL.board_auto then
    BOARD_MEMO.ranh_tu = BOARD_MEMO.ranh_tu or now
    if now - BOARD_MEMO.ranh_tu >= 180 then kill_pane(b); wezterm.GLOBAL.board_o = nil; BOARD_MEMO.ranh_tu = nil end
  end
end
