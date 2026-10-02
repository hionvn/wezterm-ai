-- ===== Bảng tổng quan + nhảy tới ô theo tên (03/10/2026) =====
-- Ctrl+Shift+U: bật / tắt bảng 📊 (báo cáo + checklist) ở BÊN PHẢI tab đang xem (03/10: trước là tab riêng).
-- Bảng mở bằng phím thì không tự đóng; bấm lại để đóng.
wezterm.on('tong-quan', function(window, pane)
  local b = board_pane()
  if b then
    local cur_tab = window:active_tab():tab_id()
    local ok, bt = pcall(function() return b:tab():tab_id() end)
    kill_pane(b); wezterm.GLOBAL.board_o = nil
    if ok and bt == cur_tab then return end -- bảng đang ở tab này → chỉ đóng
  end
  if is_header(pane) then pane = wezterm.mux.get_pane(tonumber(hdr_map()[tostring(pane:pane_id())])) or pane end
  open_board(pane, false)
end)

-- Ctrl+Shift+F4: đóng hẳn 1 dự án — chọn dự án (thấy số ô, số ô đang làm) → hỏi lại → đóng mọi ô của dự án
-- (đội, phiên phụ, tài liệu). Không bao giờ đóng ô Tổng quản + bảng 📊. Mở lại: wez.ps1 doi <dự án> hoặc Ctrl+Shift+O. (03/10/2026)
-- Ctrl+Shift+P: menu gọn của đội AI — mỗi dòng 1 việc hay dùng + phím tắt của nó (gõ để lọc, Enter chạy).
-- Dùng được cả khi phím tắt bị máy chiếm (vd Ctrl+Shift+F4 trên laptop). Bảng lệnh gốc WezTerm: Ctrl+Shift+Alt+P.
local MENU_DOI = {
  { 'tong-quan', '📊  Bảng tổng quan + checklist', 'Ctrl+Shift+U' },
  { 'nhay-o', '🔎  Nhảy tới ô theo tên', 'Ctrl+Shift+Space' },
  { 'mo-du-an', '➕  Mở dự án / AI', 'Ctrl+Shift+A' },
  { 'ban-duyet', '📋  Bàn duyệt (việc chờ bạn)', 'Ctrl+Shift+J' },
  { 'tat-du-an', '🛑  Đóng hẳn 1 dự án', 'Ctrl+Alt+W' },
  { 'luu', '💾  Lưu bố cục', 'Ctrl+Shift+S' },
  { 'mo-lai', '⏮  Mở lại bố cục', 'Ctrl+Shift+O' },
  { 'chia-deu', '⇔  Chia đều các ô', 'Ctrl+Shift+E' },
  { 'ten-o', '🏷  Bật/tắt thanh tên ô', 'Ctrl+Shift+D' },
  { 'goc', '⚙  Bảng lệnh gốc của WezTerm', 'Ctrl+Shift+Alt+P' },
}
wezterm.on('menu-doi', function(window, pane)
  local choices = {}
  for _, m in ipairs(MENU_DOI) do table.insert(choices, { id = m[1], label = m[2] .. '   ·   ' .. m[3] }) end
  window:perform_action(act.InputSelector {
    title = 'Đội AI — chọn việc  (gõ để lọc · Enter chạy · Esc thoát)', fuzzy = true, choices = choices,
    action = wezterm.action_callback(function(w, p, id)
      if not id then return end
      local run = {
        ['tong-quan'] = act.EmitEvent 'tong-quan', ['nhay-o'] = act.EmitEvent 'nhay-o', ['tat-du-an'] = act.EmitEvent 'tat-du-an',
        ['mo-du-an'] = project_menu, ['ban-duyet'] = toggle_doc, ['luu'] = save_layout, ['mo-lai'] = restore_menu,
        ['chia-deu'] = act.EmitEvent 'chia-deu', ['ten-o'] = act.EmitEvent 'ten-o-bat-tat', ['goc'] = act.ActivateCommandPalette,
      }
      if run[id] then w:perform_action(run[id], p) end
    end),
  }, pane)
end)

wezterm.on('tat-du-an', function(window, pane)
  wezterm.log_warn('tat-du-an: đã nhận lệnh') -- để biết phím có tới WezTerm không
  local doi = doi_map()
  local hion = read_json(AIDIR .. '\\doi\\Hion.json')
  local giu = { [tostring(wezterm.GLOBAL.board_o or '')] = true }
  if hion and hion.manager then giu[tostring(hion.manager.o)] = true end
  local nhom, thu_tu = {}, {}
  for _, mw in ipairs(wezterm.mux.all_windows()) do
    for _, tab in ipairs(mw:tabs()) do
      for _, p in ipairs(tab:panes()) do
        local id = tostring(p:pane_id())
        if not is_header(p) and not giu[id] then
          local x = PANE_LAST[id] or pinfo(p)
          local proj = (doi[id] and doi[id].doi) or x.proj or '?'
          if not nhom[proj] then nhom[proj] = { o = {}, work = 0 }; table.insert(thu_tu, proj) end
          table.insert(nhom[proj].o, id)
          local t1 = (x.title or ''):match('^(%S+)') or ''
          if t1 == '◐' or t1 == '◓' or t1 == '◑' or t1 == '◒' or (x.title or ''):find('| Working |', 1, true) then nhom[proj].work = nhom[proj].work + 1 end
        end
      end
    end
  end
  local choices = {}
  for _, proj in ipairs(thu_tu) do
    local g = nhom[proj]
    table.insert(choices, { id = proj, label = proj_logo(proj) .. ' ' .. proj .. ' — ' .. #g.o .. ' ô' .. (g.work > 0 and ('  ·  ⚠️ ' .. g.work .. ' ô đang làm') or '') })
  end
  if #choices == 0 then window:toast_notification('WezTerm', 'Không có dự án nào để đóng', nil, 3000) return end
  window:perform_action(act.InputSelector {
    title = 'Đóng hẳn dự án nào?  (Enter chọn · Esc thoát)', fuzzy = true, choices = choices,
    action = wezterm.action_callback(function(w, p2, proj)
      if not proj then return end
      local g = nhom[proj]
      w:perform_action(act.InputSelector {
        title = 'Đóng ' .. #g.o .. ' ô của ' .. proj .. '?' .. (g.work > 0 and (' ⚠️ ' .. g.work .. ' ô ĐANG LÀM sẽ bị dừng.') or '') .. ' Mở lại: wez.ps1 doi ' .. proj .. ' / Ctrl+Shift+O',
        choices = { { id = 'khong', label = '❌ Không, giữ lại' }, { id = 'dong', label = '✅ Đóng hết ' .. #g.o .. ' ô của ' .. proj } },
        action = wezterm.action_callback(function(w2, _, ok)
          if ok ~= 'dong' then return end
          for _, id in ipairs(g.o) do local pp = pane_or_nil(id); if pp then kill_pane(pp) end end
          w2:toast_notification('WezTerm · đội AI', '🛑 Đã đóng ' .. #g.o .. ' ô của ' .. proj, nil, 5000)
        end),
      }, p2)
    end),
  }, pane)
end)

-- Ctrl+Shift+Space: danh sách mọi ô (dự án · vai · trạng thái), gõ vài chữ để lọc, Enter là tới đúng ô
wezterm.on('nhay-o', function(window, pane)
  local doi = doi_map()
  local choices = {}
  for _, mw in ipairs(wezterm.mux.all_windows()) do
    for ti, tab in ipairs(mw:tabs()) do
      for _, p in ipairs(tab:panes()) do
        if not is_header(p) then
          local id = tostring(p:pane_id())
          local x = PANE_LAST[id] or pinfo(p)
          local title = x.title or ''
          local d = doi[id]
          local who
          if d then who = d.icon .. ' ' .. d.ten
          elseif title:find('📄', 1, true) then who = title
          elseif title:find('📊', 1, true) then who = '📊 Tổng quan'
          else who = (x.ai and (x.icon .. ' ') or '') .. (short_title(title, x.proj, 30) or (x.ai or 'PowerShell')) end
          local t1 = title:match('^(%S+)') or ''
          local al = read_json(ALERTS .. '\\' .. id .. '.json')
          local st = (al and al.kind == 'need') and '🔔 cần duyệt'
            or ((t1 == '◐' or t1 == '◓' or t1 == '◑' or t1 == '◒' or title:find('Working', 1, true)) and '⏳ đang làm')
            or (x.ai and '🟢 rảnh' or '')
          local proj = d and d.doi or x.proj
          table.insert(choices, { id = id, label = proj_logo(proj) .. ' ' .. proj .. ' · ' .. who .. '   ' .. st .. '   (tab ' .. ti .. ')' })
        end
      end
    end
  end
  window:perform_action(act.InputSelector {
    title = 'Nhảy tới ô nào?  (gõ để lọc · Enter chọn · Esc thoát)',
    fuzzy = true,
    choices = choices,
    action = wezterm.action_callback(function(w, _, id)
      if not id then return end
      local p = wezterm.mux.get_pane(tonumber(id))
      if p then p:tab():activate() p:activate() end
    end),
  }, pane)
end)

return config