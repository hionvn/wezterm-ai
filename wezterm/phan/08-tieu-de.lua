wezterm.on('format-tab-title', function(tab, tabs)
  -- chạy rất dày → chỉ tra bảng PANE_LAST (update-status cập nhật mỗi 2 giây), không hỏi Windows
  local proj, logo, title, x = tab_info(tab)
  local label = title
  if label == '' then
    label = proj
    local trung = 0
    for _, t in ipairs(tabs or {}) do if select(1, tab_info(t)) == proj and (t.tab_title or '') == '' then trung = trung + 1 end end
    if trung > 1 then
      local s = short_title(x and x.title or tab.active_pane.title, proj, 14)
      if s then label = proj .. ' · ' .. s end
    end
  end
  if tab.active_pane.is_zoomed then label = label .. ' 🔍' end
  -- tình trạng tab (03/10): ⏳n = số ô đang làm · 🔔n = số ô cần duyệt (chỉ hiện khi > 0)
  local st = TAB_STAT[tostring(tab.tab_id)]
  if st and st.work > 0 then label = label .. ' ⏳' .. st.work end
  if st and st.need > 0 then label = label .. ' 🔔' .. st.need end
  local alert = tab_alert[tostring(tab.tab_id)]
  local color = proj_color(proj)
  local n = tostring(tab.tab_index + 1)
  if alert then
    local bg = alert == 'need' and '#a8322d' or '#1f5fb4' -- cần duyệt = đỏ · xong việc = xanh dương (người dùng chọn 03/10)
    return {
      { Background = { Color = bg } }, { Foreground = { Color = '#ffffff' } }, { Attribute = { Intensity = 'Bold' } },
      { Text = ' ' .. n .. ' ' .. (alert == 'need' and '🔔' or '✅') .. ' ' .. logo .. ' ' .. label .. ' ' },
      { Background = { Color = '#15181c' } }, { Text = ' ' },
    }
  end
  if tab.is_active then
    return {
      { Background = { Color = color } }, { Foreground = { Color = '#15181c' } }, { Attribute = { Intensity = 'Bold' } },
      { Text = ' ' .. n .. ' ' .. logo .. ' ' .. label .. ' ' },
      { Background = { Color = '#15181c' } }, { Text = ' ' },
    }
  end
  return {
    { Background = { Color = '#23272e' } }, { Foreground = { Color = color } }, { Text = '▌' },
    { Foreground = { Color = '#7f848e' } }, { Text = n .. ' ' },
    { Foreground = { Color = '#c8ccd4' } }, { Text = logo .. ' ' .. label .. ' ' },
    { Background = { Color = '#15181c' } }, { Text = ' ' },
  }
end)

-- Tiêu đề cửa sổ (thanh trên cùng + thanh tác vụ Windows) — 03/10 làm gọn: chỉ ghi tab đang xem + tổng báo động,
-- vd "💬 Chatbot · đội  —  🔔 1 cần duyệt · ✅ 2 xong" (trước đây liệt kê mọi AI trong tab → dài, rối)
wezterm.on('format-window-title', function(tab, pane, tabs, panes)
  local proj, logo, title = tab_info(tab)
  local s = logo .. ' ' .. proj .. ((title ~= '' and title ~= proj) and (' · ' .. title) or '')
  local need, done = 0, 0
  for _, a in pairs(tab_alert) do if a == 'need' then need = need + 1 elseif a == 'done' then done = done + 1 end end
  local tail = {}
  if need > 0 then tail[#tail + 1] = '🔔 ' .. need .. ' cần duyệt' end
  if done > 0 then tail[#tail + 1] = '✅ ' .. done .. ' xong' end
  return s .. (#tail > 0 and ('   —   ' .. table.concat(tail, ' · ')) or '')
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
  -- bảng tổng quan: bấm vào dòng (link wezai-o:<số ô>) → nhảy tới đúng ô, kể cả ở tab khác
  local oid = uri:match('^wezai%-o:(%d+)$')
  if oid then
    local p = wezterm.mux.get_pane(tonumber(oid))
    if p then p:tab():activate() p:activate() end
    return false
  end
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
