config.keys = {
  -- Bàn làm việc Tổng quản, ô cần duyệt, menu dự án
  { key = 'H', mods = 'CTRL|SHIFT', action = open_desk },
  { key = 'J', mods = 'CTRL|SHIFT', action = toggle_doc },
  { key = 'A', mods = 'CTRL|SHIFT', action = project_menu },
  -- Đẩy ô ra tab nền / kéo ô ở tab khác về
  { key = 'B', mods = 'CTRL|SHIFT', action = push_bg },
  { key = 'G', mods = 'CTRL|SHIFT', action = pull_menu },
  -- Lưu bố cục / mở lại bố cục đã lưu (hàm ở mục "Lưu / khôi phục bố cục" bên dưới)
  { key = 'S', mods = 'CTRL|SHIFT', action = wezterm.action_callback(function(w, p) w:perform_action(save_layout, p) end) },
  { key = 'O', mods = 'CTRL|SHIFT', action = wezterm.action_callback(function(w, p) w:perform_action(restore_menu, p) end) },
  -- Chia ô
  -- Alt+Shift+D: thêm 1 cột ở mép phải cả tab rồi chia đều (không lồng ô mới vào trong ô đang chọn)
  { key = 'D', mods = 'ALT|SHIFT', action = wezterm.action_callback(function(w, p)
    local np = p:split { direction = 'Right', top_level = true, cwd = HUB, args = PS('ai') }
    wezterm.emit('chia-deu', w, np)
  end) },
  -- Sắp xếp ô: Ctrl+Shift+X đổi chỗ (hiện chữ cái trên mỗi ô, bấm chữ của ô muốn đổi)
  --            Ctrl+Shift+F tách ô đang chọn ra cửa sổ riêng (kéo thả tự do, Win+mũi tên để xếp)
  { key = 'X', mods = 'CTRL|SHIFT', action = act.PaneSelect { mode = 'SwapWithActive', alphabet = 'asdfghjklqwertyuiop' } },
  { key = 'F', mods = 'CTRL|SHIFT', action = act.EmitEvent 'tach-o' },
  { key = '_', mods = 'ALT|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = '@', mods = 'ALT|SHIFT', action = cols(2) },
  { key = '#', mods = 'ALT|SHIFT', action = cols(3) },
  { key = '$', mods = 'ALT|SHIFT', action = cols(4) },
  { key = '2', mods = 'ALT|SHIFT', action = cols(2) },
  { key = '3', mods = 'ALT|SHIFT', action = cols(3) },
  { key = '4', mods = 'ALT|SHIFT', action = cols(4) },
  -- Chia đều mọi ô trong tab đang xem (bao nhiêu ô cũng được): cột rộng bằng nhau, ô xếp chồng cao bằng nhau
  -- (đóng tạm thanh tên các ô trước khi chia, chia xong tự dựng lại — xem sự kiện 'chia-deu' cuối file)
  { key = 'E', mods = 'CTRL|SHIFT', action = act.EmitEvent 'chia-deu' },
  -- Bật/tắt thanh tên 1 dòng trên đỉnh mỗi ô AI
  { key = 'D', mods = 'CTRL|SHIFT', action = act.EmitEvent 'ten-o-bat-tat' },
  { key = 'U', mods = 'CTRL|SHIFT', action = act.EmitEvent 'tong-quan' },   -- 📊 bảng tổng quan đội (03/10)
  { key = 'F4', mods = 'CTRL|SHIFT', action = act.EmitEvent 'tat-du-an' },  -- đóng hẳn 1 dự án (mọi ô của nó), có hỏi lại (03/10)
  { key = 'w', mods = 'CTRL|ALT', action = act.EmitEvent 'tat-du-an' },     -- như trên; laptop hay cần Fn cho F4 nên thêm phím này
  -- Ctrl+Shift+P: MENU GỌN của đội AI (03/10, người dùng thấy bảng lệnh gốc quá nhiều dòng thừa) · bảng gốc → Ctrl+Shift+Alt+P
  { key = 'P', mods = 'CTRL|SHIFT', action = act.EmitEvent 'menu-doi' },
  { key = 'p', mods = 'CTRL|SHIFT', action = act.EmitEvent 'menu-doi' },
  { key = 'P', mods = 'CTRL|SHIFT|ALT', action = act.ActivateCommandPalette },
  { key = 'Space', mods = 'CTRL|SHIFT', action = act.EmitEvent 'nhay-o' }, -- nhảy tới ô theo tên (03/10)
  -- Dời tab trên thanh tab sang trái/phải (bản WezTerm này không kéo thả tab bằng chuột được) (03/10)
  { key = 'LeftArrow', mods = 'CTRL|SHIFT|ALT', action = act.MoveTabRelative(-1) },
  { key = 'RightArrow', mods = 'CTRL|SHIFT|ALT', action = act.MoveTabRelative(1) },
  -- Chuyển ô: Alt + mũi tên
  { key = 'LeftArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Left' },
  { key = 'RightArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Right' },
  { key = 'UpArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Up' },
  { key = 'DownArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Down' },
  -- Chỉnh kích thước ô: Alt + Shift + mũi tên (hoặc kéo chuột ở đường ranh)
  { key = 'LeftArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Left', 5 } },
  { key = 'RightArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Right', 5 } },
  { key = 'UpArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Up', 3 } },
  { key = 'DownArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Down', 3 } },
  -- Phóng to / thu nhỏ ô đang chọn
  { key = 'Z', mods = 'CTRL|SHIFT', action = act.TogglePaneZoomState },
  -- Đóng ô đang chọn (có hỏi lại)
  { key = 'W', mods = 'CTRL|SHIFT', action = act.CloseCurrentPane { confirm = true } },
  -- Copy / dán giống Windows
  { key = 'c', mods = 'CTRL', action = copy_or_interrupt },
  { key = 'v', mods = 'CTRL', action = act.PasteFrom 'Clipboard' },
}

-- Chuột phải = dán (giống Windows Terminal)
config.mouse_bindings = {
  { event = { Down = { streak = 1, button = 'Right' } }, mods = 'NONE', action = act.PasteFrom 'Clipboard' },
  -- Ctrl + click = mở link trên trình duyệt, kể cả khi Claude/Codex đang giữ chuột (mouse_reporting)
  { event = { Up = { streak = 1, button = 'Left' } }, mods = 'CTRL', action = act.OpenLinkAtMouseCursor },
  { event = { Down = { streak = 1, button = 'Left' } }, mods = 'CTRL', action = act.Nop },
  { event = { Up = { streak = 1, button = 'Left' } }, mods = 'CTRL', mouse_reporting = true, action = act.OpenLinkAtMouseCursor },
  { event = { Down = { streak = 1, button = 'Left' } }, mods = 'CTRL', mouse_reporting = true, action = act.Nop },
}
