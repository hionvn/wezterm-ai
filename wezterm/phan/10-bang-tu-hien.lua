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
