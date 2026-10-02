wezterm.on('update-status', function(window, pane)
  -- Thanh tên bật lại 02/10 22h sau khi thêm phanh (hdr_allow / hdr_note); tắt tạm 18:18 vì dựng ô liên tục
  local okh, errh = pcall(process_headers, window)
  if not okh then wezterm.log_error('process_headers: ' .. tostring(errh)) end
  local okr, errr = pcall(morning_report)
  if not okr then wezterm.log_error('morning_report: ' .. tostring(errr)) end
  local oka, erra = pcall(process_alerts, window)
  if not oka then wezterm.log_error('process_alerts: ' .. tostring(erra)) end
  local oko, erro = pcall(process_open, window)
  if not oko then wezterm.log_error('process_open: ' .. tostring(erro)) end
  local okb, errb = pcall(auto_board)
  if not okb then wezterm.log_error('auto_board: ' .. tostring(errb)) end
  local oks, errs = pcall(autosave)
  if not oks then wezterm.log_error('autosave: ' .. tostring(errs)) end
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
        local n = restore_layout(w, d)
        kill_pane(menu) -- đóng ô menu `ai` lúc mở
        w:toast_notification('WezTerm · đội AI', '⏮ Đã mở lại ' .. n .. ' tab của phiên trước. Ô nào đang làm dở sẽ tự làm tiếp.', nil, 8000)
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
  local okf, fc = pcall(fuel_cells)
  if not okf then wezterm.log_error('fuel_cells: ' .. tostring(fc)) end
  local okw, errw = pcall(codex_warn, window)
  if not okw then wezterm.log_error('codex_warn: ' .. tostring(errw)) end
  window:set_right_status('')

  -- Góc trái: báo khi đang ở chế độ phím đặc biệt (copy mode…)
  local kt = window:active_key_table()
  window:set_left_status(kt and wezterm.format { { Background = { Color = '#e5c07b' } }, { Foreground = { Color = '#000000' } }, { Text = ' ⌨ ' .. kt .. ' ' } } or '')
end)
