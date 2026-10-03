-- ===== Lưu / khôi phục bố cục (thêm 02/10/2026) =====
-- Ctrl+Shift+S lưu tay · tự lưu mỗi phút (khi có từ 2 ô) · Ctrl+Shift+O chọn bản để mở lại.
-- Mở lại: Claude tiếp tục đúng phiên cũ (session lấy từ file trạng thái), Codex `resume --last`,
-- ô 📋 / 📄 mở lại tài liệu. Bố cục dựng lại theo cột rồi theo hàng
-- (khớp kiểu chia ô thường dùng; kiểu chia lồng nhau phức tạp sẽ gần đúng).
local LAYOUT = { saved = AIDIR .. '\\bo-cuc-luu.json', auto = AIDIR .. '\\bo-cuc-tu-luu.json', prev = AIDIR .. '\\bo-cuc-phien-truoc.json' }

local function pane_kind(p)
  local x = pinfo(p)
  local title, ai = x.title, x.ai
  if title:find('Cần duyệt', 1, true) then return 'canduyet' end
  if title:find('📄', 1, true) then return 'doc' end
  if title:find('📊 Tổng quan', 1, true) then return 'board' end
  return ({ Claude = 'claude', Codex = 'codex' })[ai] or 'shell'
end

-- Sổ đội (wez-ai\doi\<dự án>.json) → [số ô] = vai trong đội; khoá công cụ (chan) lấy từ định nghĩa Hion\doi\<dự án>.json.
-- Lưu vào bố cục để khi mở lại, ô đội có lại đúng tên, Remote Control, khoá chỉ đọc; sổ đội ghi số ô mới.
local function doi_map()
  local m = {}
  for _, path in ipairs(wezterm.glob(AIDIR:gsub('\\', '/') .. '/doi/*.json')) do
    local r = read_json(path)
    if r and r.du_an then
      local def = read_json(HUB .. '\\doi\\' .. r.du_an .. '.json') or {}
      local chan = {}
      for _, w in ipairs(def.worker or {}) do chan[w.vai] = w.chan end
      if def.manager then chan[def.manager.vai or 'Manager'] = def.manager.chan end
      local function add(x)
        if x and x.o and tostring(x.o) ~= '' then
          m[tostring(x.o)] = { doi = r.du_an, logo = r.logo or def.logo or '', vai = x.vai, ten = x.ten or x.vai, icon = x.icon or '', chan = chan[x.vai], doi_ai = tostring(x.ai or ''):lower(), session = (x.session ~= '' and x.session) or nil } -- session: NGUỒN CHUẨN phiên của vai (03/10)
        end
      end
      add(r.manager)
      for _, w in ipairs(r.worker or {}) do add(w) end
    end
  end
  return m
end

local function capture_layout()
  local out, n = { t = os.time(), tabs = {} }, 0
  local docs = wezterm.GLOBAL.docs or {}
  local doi = doi_map()
  for _, mw in ipairs(wezterm.mux.all_windows()) do
    for _, tab in ipairs(mw:tabs()) do
      local panes = {}
      for _, info in ipairs(tab:panes_with_info()) do
        local p, id = info.pane, tostring(info.pane:pane_id())
        if not is_header(p) and id ~= tostring(wezterm.GLOBAL.board_o) then -- ô tên + bảng 📊 tự hiện không lưu: tự dựng lại sau khi khôi phục
          local it = { left = info.left, top = info.top, width = info.width, height = info.height,
            cwd = pinfo(p).dir, kind = pane_kind(p) } -- dùng thư mục đã nhớ, không hỏi lại Windows
          if it.kind == 'claude' then
            local s = read_json(STATE .. '\\' .. id .. '.json')
            if s and s.session and s.session ~= '' then it.session = s.session end
            it.state = s and s.state -- 'work' = đang làm dở → mở lại sẽ tự làm tiếp
          elseif it.kind == 'codex' then
            it.state = title_state(p)
          elseif it.kind == 'doc' then
            -- sổ docs nhớ theo số ô; số ô có thể đã bị dùng lại → chỉ tin khi tên file khớp tiêu đề ô
            local pth = docs[id]
            local nm = pth and pth:match('([^\\/]+)$')
            if nm and (pinfo(p).title or ''):find(nm, 1, true) then it.path = pth end
          end
          -- tab bảng tổng quan: tiêu đề ô có khi chỉ là "node.exe" → nhận theo tên tab
          if it.kind == 'shell' and (tab:get_title() or ''):find('📊', 1, true) then it.kind = 'board' end
          local d = doi[id]
          if d then
            for k, v in pairs(d) do it[k] = v end
            -- ô trong đội: loại AI theo sổ đội (tiêu đề / tiến trình có lúc không nhận ra)
            if d.doi_ai == 'codex' and it.kind == 'shell' then it.kind = 'codex'; it.state = it.state or title_state(p) end
            if d.doi_ai == 'claude' and it.kind == 'shell' then it.kind = 'claude' end
          end
          table.insert(panes, it)
          n = n + 1
        end
      end
      table.insert(out.tabs, { title = tab:get_title(), panes = panes })
    end
  end
  return out, n
end

local function write_layout(path)
  local data, n = capture_layout()
  local f = io.open(path, 'w')
  if f then f:write(wezterm.json_encode(data)) f:close() end
  return n
end

local function q(s) return "'" .. (tostring(s):gsub("'", "''")) .. "'" end
local TIEP = 'Tiếp tục việc đang làm dở trước khi WezTerm khởi động lại (đọc lại tiến độ nếu cần).'
local function restore_args(it)
  -- 03/10: lần khởi động lại thật, các ô Claude mở lại bị chạy trong E:\AI\Hion thay vì thư mục dự án
  -- (tham số cwd của split không được tôn trọng) → luôn tự cd vào đúng thư mục trước khi chạy AI
  local PS0 = PS
  local function PS(cmd, khong_profile)
    if it.cwd and it.cwd ~= '' then cmd = 'Set-Location -LiteralPath ' .. q(it.cwd) .. '; ' .. cmd end
    return (khong_profile and PSN or PS0)(cmd)
  end
  if it.kind == 'claude' then
    -- 03/10 (lần 2): ô không có mã phiên từng dùng `--continue` → vớ phiên mới nhất trong thư mục = phiên của ô KHÁC
    -- (ra 3 ô Security, 3 Sino Manager, 2 Tổng quản cùng một phiên). Luật mới: mỗi phiên chỉ mở ở MỘT ô;
    -- không có mã phiên / phiên đã có ô khác giữ → mở PowerShell trống (không chạy AI, không tốn hạn mức).
    local DA_MO = wezterm.GLOBAL.phien_da_mo or {}
    if not it.session or DA_MO[it.session] then
      return PS("Write-Host 'Ô này không có phiên Claude riêng (hoặc phiên đã mở ở ô khác) nên không tự mở lại AI. Cần thì: wez.ps1 doi <dự án> hoặc gõ claudeRC.' -ForegroundColor DarkGray")
    end
    DA_MO[it.session] = true
    wezterm.GLOBAL.phien_da_mo = DA_MO
    local tiep = it.state == 'work' and (' ' .. q(TIEP)) or '' -- đang làm dở → tự làm tiếp
    if it.doi and it.doi ~= 'Hion' then -- ô trong đội: giữ tên, Remote Control, khoá công cụ; gọi thẳng claude → không cần profile
      return PS(('claude --resume ' .. it.session)
        .. ' -n ' .. q(it.logo .. ' ' .. it.doi .. ' · ' .. it.icon .. ' ' .. it.ten)
        .. ' --remote-control ' .. q(it.doi .. '-' .. it.vai)
        .. (it.chan and (' ' .. q('--disallowedTools=' .. (it.chan:gsub('%s+', ',')))) or '') .. tiep, true)
    end
    -- ô ngoài đội + Tổng quản Hion: claudeRC (hàm trong profile, Remote Control theo tên thư mục)
    return PS('claudeRC --resume ' .. it.session .. tiep)
  end
  if it.kind == 'codex' then
    local tiep = it.state == 'work' and (' ' .. q(TIEP)) or ''
    -- ô Codex trong đội: mở lại đúng phiên theo tên (/rename lúc mở đội); không thấy tên thì lấy phiên gần nhất
    if it.doi then
      return PS('codex resume ' .. q(it.logo .. ' ' .. it.doi .. ' · ' .. it.icon .. ' ' .. it.ten) .. tiep
        .. '; if ($LASTEXITCODE) { codex resume --last' .. tiep .. ' }')
    end
    return PS('codex resume --last' .. tiep)
  end
  if it.kind == 'canduyet' then return VIEWER end
  if it.kind == 'board' then return BOARD end
  if it.kind == 'doc' and it.path then return DOCVIEW(it.path) end
  return { 'powershell.exe', '-NoLogo' }
end
local function safe_cwd(dir)
  if dir and pcall(wezterm.read_dir, dir) then return dir end
  return HUB
end

local function restore_tab(mw, t)
  local keep = {} -- bỏ ô không có thư mục (ô tên 🏷 lỡ bị lưu ở bản cũ)
  for _, it in ipairs(t.panes or {}) do if it.cwd or it.kind ~= 'shell' then table.insert(keep, it) end end
  t = { title = t.title, panes = keep }
  if #t.panes == 0 then return end
  local cols, by_left = {}, {}
  for _, it in ipairs(t.panes) do -- gom ô thành cột theo mép trái
    local c = by_left[it.left]
    if not c then
      c = { left = it.left, width = it.width, items = {} }
      by_left[it.left] = c
      table.insert(cols, c)
    end
    c.width = math.max(c.width, it.width)
    table.insert(c.items, it)
  end
  table.sort(cols, function(a, b) return a.left < b.left end)
  for _, c in ipairs(cols) do table.sort(c.items, function(a, b) return a.top < b.top end) end

  local made = {} -- { it, ô mới } → ghi số ô mới vào sổ đội
  local first = cols[1].items[1]
  local tab, root = mw:spawn_tab { cwd = safe_cwd(first.cwd), args = restore_args(first) }
  made[#made + 1] = { first, root }
  if t.title and t.title ~= '' then tab:set_title(t.title) end
  local heads, cur = { root }, root
  for i = 2, #cols do -- tách dần sang phải, giữ tỉ lệ chiều rộng
    local rest = 0
    for j = i, #cols do rest = rest + cols[j].width end
    local it = cols[i].items[1]
    cur = cur:split { direction = 'Right', size = rest / (rest + cols[i - 1].width), cwd = safe_cwd(it.cwd), args = restore_args(it) }
    made[#made + 1] = { it, cur }
    heads[i] = cur
  end
  for i, c in ipairs(cols) do -- trong mỗi cột: tách dần xuống dưới
    local p = heads[i]
    for k = 2, #c.items do
      local rest = 0
      for j = k, #c.items do rest = rest + c.items[j].height end
      local it = c.items[k]
      p = p:split { direction = 'Bottom', size = rest / (rest + c.items[k - 1].height), cwd = safe_cwd(it.cwd), args = restore_args(it) }
      made[#made + 1] = { it, p }
    end
  end
  root:activate()
  -- Sổ đội: ô của đội vừa mở lại có số ô mới → ghi lại để thanh tên, statusline, wez.ps1 (Chatbot.Engineer…) trỏ đúng
  local by_doi = {}
  for _, m in ipairs(made) do
    local it = m[1]
    if it.doi then by_doi[it.doi] = by_doi[it.doi] or {}; by_doi[it.doi][it.vai] = tostring(m[2]:pane_id()) end
  end
  for du_an, vai_o in pairs(by_doi) do
    local path = AIDIR .. '\\doi\\' .. du_an .. '.json'
    local r = read_json(path)
    if r then
      if r.manager and vai_o[r.manager.vai] then r.manager.o = vai_o[r.manager.vai] end
      for _, w in ipairs(r.worker or {}) do if vai_o[w.vai] then w.o = vai_o[w.vai] end end
      local f = io.open(path, 'w')
      if f then f:write(wezterm.json_encode(r)) f:close() end
    end
  end
end

-- Mở lại cả bố cục đã lưu vào cửa sổ (dùng cho Ctrl+Shift+O, menu `ai`, và tự mở lại khi khởi động)
local function restore_layout(window, d)
  -- 03/10: tạm dừng dựng thanh tên 🏷 trong 25 giây — mở lại nhiều ô cùng lúc làm thanh tên bị dựng/xoá liên tục
  -- → phanh an toàn hiểu nhầm là lỗi và tự tắt thanh tên (sau khởi động lại thấy 0 thanh tên)
  wezterm.GLOBAL.ten_o_hoan = os.time() + 25
  wezterm.GLOBAL.phien_da_mo = {} -- mỗi lần mở lại: đếm lại phiên nào đã có ô giữ (chống 2 ô cùng một phiên)
  local n = 0
  for _, t in ipairs(d and d.tabs or {}) do
    local ok, err = pcall(restore_tab, window:mux_window(), t)
    if ok then n = n + 1 else wezterm.log_error('restore_tab: ' .. tostring(err)) end
  end
  return n
end

-- Ctrl+Shift+S: lưu bố cục hiện tại
save_layout = wezterm.action_callback(function(window)
  local n = write_layout(LAYOUT.saved)
  window:toast_notification('WezTerm · đội AI', '💾 Đã lưu bố cục (' .. n .. ' ô). Mở lại: Ctrl+Shift+O', nil, 4000)
end)

-- Ctrl+Shift+O: chọn bản bố cục để mở lại (thành các tab mới trong cửa sổ này)
restore_menu = wezterm.action_callback(function(window, pane)
  local choices = {}
  for _, c in ipairs { { 'saved', '💾 Bản lưu tay (Ctrl+Shift+S)' }, { 'prev', '⏮  Phiên trước (trước lần mở WezTerm này)' }, { 'auto', '🔄 Tự lưu gần nhất (phiên này)' } } do
    local d = read_json(LAYOUT[c[1]])
    if d and d.tabs then
      local n = 0
      for _, t in ipairs(d.tabs) do n = n + #(t.panes or {}) end
      table.insert(choices, { id = c[1], label = c[2] .. '  ·  ' .. os.date('%H:%M %d/%m', d.t or 0) .. '  ·  ' .. #d.tabs .. ' tab, ' .. n .. ' ô' })
    end
  end
  if #choices == 0 then
    window:toast_notification('WezTerm', 'Chưa có bố cục nào được lưu', nil, 3000)
    return
  end
  window:perform_action(act.InputSelector {
    title = 'Mở lại bố cục nào?  (Enter chọn · Esc thoát)',
    choices = choices,
    action = wezterm.action_callback(function(w, _, id)
      if not id then return end
      local d = read_json(LAYOUT[id])
      for _, t in ipairs(d and d.tabs or {}) do
        local ok, err = pcall(restore_tab, w:mux_window(), t)
        if not ok then wezterm.log_error('restore_tab: ' .. tostring(err)) end
      end
    end),
  }, pane)
end)

-- Menu `ai` chọn "2) Mở lại tất cả phiên đang làm dở" → PowerShell gửi biến wez_ai=mo-lai (OSC 1337 SetUserVar)
-- → mở lại bố cục phiên trước (Claude tiếp đúng phiên, Codex resume) rồi đóng ô menu.
wezterm.on('user-var-changed', function(window, pane, name, value)
  if name ~= 'wez_ai' or value ~= 'mo-lai' then return end
  local d
  for _, k in ipairs { 'prev', 'saved', 'auto' } do
    local x = read_json(LAYOUT[k])
    if x and x.tabs and #x.tabs > 0 then d = x break end
  end
  if not d then
    window:toast_notification('WezTerm · đội AI', 'Chưa có phiên nào được lưu để mở lại', nil, 4000)
    return
  end
  for _, t in ipairs(d.tabs) do
    local ok, err = pcall(restore_tab, window:mux_window(), t)
    if not ok then wezterm.log_error('restore_tab: ' .. tostring(err)) end
  end
  kill_pane(pane) -- đóng đúng ô menu (CloseCurrentPane có thể đóng nhầm ô đang chọn sau khi mở lại các tab)
end)

-- Tự lưu mỗi 30 giây (03/10: trước là 1 phút — trạng thái "đang làm" mới hơn khi mở lại), chỉ khi có từ 2 ô (để một lần mở thử 1 ô không đè mất bố cục cũ)
local last_autosave = 0
local function autosave()
  if os.time() - last_autosave < 30 then return end
  last_autosave = os.time()
  local n = 0
  for _, mw in ipairs(wezterm.mux.all_windows()) do
    for _, tab in ipairs(mw:tabs()) do n = n + #tab:panes() end
  end
  if n >= 2 then write_layout(LAYOUT.auto) end
end

-- Khi WezTerm vừa mở: tạo thư mục cần thiết, chuyển bản tự lưu của lần trước thành "Phiên trước",
-- xoá trạng thái cũ (số ô sẽ đánh lại từ đầu)
wezterm.on('gui-startup', function()
  wezterm.background_child_process { 'cmd.exe', '/c', 'mkdir', ALERTS, STATE }
  local s = read_file(LAYOUT.auto)
  if s and s ~= '' then
    local f = io.open(LAYOUT.prev, 'wb')
    if f then f:write(s) f:close() end
    os.remove(LAYOUT.auto)
    wezterm.GLOBAL.hint_restore = true
  end
  for _, path in ipairs(wezterm.glob(STATE:gsub('\\', '/') .. '/*.json')) do os.remove(path) end
  -- 03/10: dọn rác mỗi lần mở WezTerm (chạy ngầm, không làm chậm lúc mở): giữ 5 log WezTerm mới nhất;
  -- xoá file tạm cũ hơn 1 ngày ở wez-ai\giao (câu giao việc), wez-ai\git-nho (nhớ git của statusline), ntfy-*.txt
  wezterm.background_child_process { 'powershell.exe', '-NoProfile', '-WindowStyle', 'Hidden', '-Command',
    "$d = \"$HOME\\.local\\share\\wezterm\"; Get-ChildItem $d -Filter '*log*' -File | Sort-Object LastWriteTime -Descending | Select-Object -Skip 5 | Remove-Item -ErrorAction SilentlyContinue; "
    .. "$w = \"$env:LOCALAPPDATA\\wez-ai\"; Get-ChildItem \"$w\\giao\",\"$w\\git-nho\" -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } | Remove-Item -ErrorAction SilentlyContinue; "
    .. "Get-ChildItem $w -Filter 'ntfy-*.txt' -File -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue" }
end)
