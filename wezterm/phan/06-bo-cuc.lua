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
  for _, path in ipairs(so_doi_files()) do
    local r = read_json(path)
    if r and r.du_an then
      local def = read_json(HUB .. '\\doi\\' .. r.du_an .. '.json') or {}
      local chan, tk = {}, {}
      for _, w in ipairs(def.worker or {}) do chan[w.vai] = w.chan; tk[w.vai] = w.tk end
      if def.manager then chan[def.manager.vai or 'Manager'] = def.manager.chan end
      -- 04/10: tài khoản Codex của vai (trường "tk"; không có thì theo dự án) — mở lại phiên Codex phải đúng CODEX_HOME
      local tk_du_an = ((read_json(HOME .. '\\.codex-tai-khoan.json') or {}).duAn or {})[r.du_an]
      local function add(x)
        if x and x.o and tostring(x.o) ~= '' then
          m[tostring(x.o)] = { doi = r.du_an, logo = r.logo or def.logo or '', vai = x.vai, ten = x.ten or x.vai, icon = x.icon or '', chan = chan[x.vai], doi_ai = tostring(x.ai or ''):lower(), session = (x.session ~= '' and x.session) or nil, tk = tk[x.vai] or tk_du_an } -- session: NGUỒN CHUẨN phiên của vai (03/10)
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
            if (d.doi_ai == 'claude' or d.doi_ai == 'deepseek') and it.kind == 'shell' then it.kind = 'claude' end
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
-- 04/10: giống $DEEPSEEK_ENV trong Hion\cai-dat\wez.ps1 (Claude Code chạy bằng DeepSeek; key lấy từ biến người dùng lúc chạy)
local DEEPSEEK_ENV = "$env:ANTHROPIC_AUTH_TOKEN = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', 'User'); $env:ANTHROPIC_BASE_URL = 'https://api.deepseek.com/anthropic'; Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue; $env:ANTHROPIC_MODEL = 'deepseek-flash[1m]'; $env:ANTHROPIC_DEFAULT_OPUS_MODEL = 'deepseek-flash[1m]'; $env:ANTHROPIC_DEFAULT_SONNET_MODEL = 'deepseek-flash[1m]'; $env:ANTHROPIC_DEFAULT_HAIKU_MODEL = 'deepseek-flash'; $env:CLAUDE_CODE_SUBAGENT_MODEL = 'deepseek-flash'; $env:CLAUDE_CODE_AUTO_COMPACT_WINDOW = '786432'"
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
      -- 04/10: vai "deepseek" = Claude Code chạy bằng DeepSeek: đặt biến (key đọc lúc chạy, không ghi file), bỏ Remote Control
      local ds = it.doi_ai == 'deepseek'
      -- 05/10: DeepSeek báo "Invalid schema for function Artifact" → luôn chặn Artifact
      local chan = it.chan
      if ds and not (' ' .. (chan or '') .. ' '):find(' Artifact ', 1, true) then chan = ((chan or '') .. ' Artifact'):gsub('^%s+', '') end
      return PS((ds and (DEEPSEEK_ENV .. '; ') or '') .. ('claude --resume ' .. it.session)
        .. ' --permission-mode bypassPermissions' -- 06/10: người dùng cho cả đội bỏ hỏi quyền (giống wez.ps1)
        .. ' -n ' .. q(it.logo .. ' ' .. it.doi .. ' · ' .. it.icon .. ' ' .. it.ten)
        .. (ds and '' or (' --remote-control ' .. q(it.doi .. '-' .. it.vai)))
        .. (chan and (' ' .. q('--disallowedTools=' .. (chan:gsub('%s+', ',')))) or '') .. tiep, true)
    end
    -- ô ngoài đội + Tổng quản Hion: claudeRC (hàm trong profile, Remote Control theo tên thư mục)
    return PS('claudeRC --resume ' .. it.session .. tiep)
  end
  if it.kind == 'codex' then
    local tiep = it.state == 'work' and (' ' .. q(TIEP)) or ''
    -- 04/10: BỎ "codex resume --last" và mở theo tên: Codex tự đổi tên phiên ("Đọc POS và báo cáo…") nên mở theo tên luôn
    -- thất bại → tụt xuống --last = phiên gần nhất của tài khoản → 4 worker Sino cùng mở MỘT phiên, 6 ô Aff cùng một phiên.
    -- Giờ: ô trong đội mở lại theo MÃ PHIÊN (UUID, sổ đội trường session) với đúng CODEX_HOME của vai; mỗi mã chỉ mở ở 1 ô.
    local DA_MO = wezterm.GLOBAL.phien_da_mo or {}
    local sid = it.session and tostring(it.session):match('^%x+%-%x+%-%x+%-%x+%-%x+$')
    if it.doi and sid and not DA_MO[sid] then
      DA_MO[sid] = true
      wezterm.GLOBAL.phien_da_mo = DA_MO
      local home = ''
      for _, t in ipairs((read_json(HOME .. '\\.codex-tai-khoan.json') or {}).taiKhoan or {}) do
        if tostring(t.so) == tostring(it.tk) then home = '$env:CODEX_HOME = ' .. q(t.thuMuc) .. '; ' end
      end
      return PS(home .. 'codex.cmd --no-daemon resume ' .. sid .. tiep, true)
    end
    return PS("Write-Host 'Ô Codex này chưa có mã phiên riêng (hoặc phiên đã mở ở ô khác) nên không tự mở lại — tránh nhiều ô cùng một phiên. Cần thì: wez.ps1 doi <dự án>, hoặc gõ codex resume rồi chọn đúng phiên.' -ForegroundColor DarkGray")
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

-- 04/10/2026: mở lại theo 2 PHA, lần lượt từng ô. Trước đây cả bố cục (vd 6 tab, 20 ô) dựng trong MỘT lượt chạy Lua:
--   GUI đứng hình suốt lúc đó (con trỏ quay mãi) · 20 PowerShell + 20 Claude/Codex khởi động cùng lúc giành CPU/ổ đĩa ·
--   mỗi lần tách ô sau làm ô AI có sẵn đổi cỡ → Claude/Codex vẽ lại CẢ hội thoại (phiên dài = rất nặng), lặp n² lần ·
--   thanh tên 🏷 / bảng 📊 chen vào tách ô giữa chừng → dựng đi dựng lại (log 04/10 03:40: "dựng quá 8 ô / phút").
-- Giờ: PHA 1 dựng khung — mỗi ô một nhịp GAP_KHUNG giây, ô AI chỉ là PowerShell "⏳ chờ tới lượt" (nhẹ, đổi cỡ thoải mái);
--      PHA 2 bật AI — xếp xong mới thả từng ô một (ghi file mo-*.go cho ô đó), cách nhau GAP_AI giây.
-- Trong lúc xếp: dang_xep() = true → tạm dừng thanh tên, bảng 📊, tự ngủ, tự lưu. Giữa các nhịp GUI vẫn chạy bình thường.
local GAP_KHUNG, GAP_AI = 0.25, 2.0
local GO_N = 0
local function la_ai(it) return it.kind == 'claude' or it.kind == 'codex' end
-- Bọc lệnh của ô AI: đợi file .go xuất hiện rồi mới chạy (args = PS()/PSN(): phần tử cuối là câu lệnh)
local function cho_luot(args)
  GO_N = GO_N + 1
  local go = AIDIR .. '\\mo-' .. wezterm.procinfo.pid() .. '-' .. os.time() .. '-' .. GO_N .. '.go'
  local a = {}
  for i, v in ipairs(args) do a[i] = v end
  a[#a] = '$go = ' .. q(go) .. "; Write-Host '⏳ Chờ tới lượt mở (đang xếp ô)…' -ForegroundColor DarkGray; "
    .. 'while (-not (Test-Path -LiteralPath $go)) { Start-Sleep -Milliseconds 300 }; Remove-Item -LiteralPath $go -ErrorAction SilentlyContinue; Clear-Host; '
    .. a[#a]
  return a, go
end

-- Kế hoạch một tab: danh sách bước theo thứ tự; bước 1 mở tab, các bước sau tách từ ô của bước `from`
local function plan_tab(t)
  local keep = {} -- bỏ ô không có thư mục (ô tên 🏷 lỡ bị lưu ở bản cũ)
  for _, it in ipairs(t.panes or {}) do if it.cwd or it.kind ~= 'shell' then table.insert(keep, it) end end
  if #keep == 0 then return nil end
  local cols, by_left = {}, {}
  for _, it in ipairs(keep) do -- gom ô thành cột theo mép trái
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

  local steps, head = { { it = cols[1].items[1] } }, { 1 }
  for i = 2, #cols do -- tách dần sang phải, giữ tỉ lệ chiều rộng
    local rest = 0
    for j = i, #cols do rest = rest + cols[j].width end
    table.insert(steps, { it = cols[i].items[1], from = head[i - 1], dir = 'Right', size = rest / (rest + cols[i - 1].width) })
    head[i] = #steps
  end
  for i, c in ipairs(cols) do -- trong mỗi cột: tách dần xuống dưới
    local from = head[i]
    for k = 2, #c.items do
      local rest = 0
      for j = k, #c.items do rest = rest + c.items[j].height end
      table.insert(steps, { it = c.items[k], from = from, dir = 'Bottom', size = rest / (rest + c.items[k - 1].height) })
      from = #steps
    end
  end
  return { title = t.title, steps = steps, made = {} }
end

-- Sổ đội: ô của đội vừa mở lại có số ô mới → ghi lại để thanh tên, statusline, wez.ps1 (Chatbot.Engineer…) trỏ đúng
local function ghi_so_doi(plan)
  local by_doi = {}
  for k, s in ipairs(plan.steps) do
    local p = plan.made[k]
    if p and s.it.doi then by_doi[s.it.doi] = by_doi[s.it.doi] or {}; by_doi[s.it.doi][s.it.vai] = tostring(p:pane_id()) end
  end
  for du_an, vai_o in pairs(by_doi) do
    local path = AIDIR .. '\\doi\\' .. du_an .. '.json'
    local r = read_json(path)
    if r then
      if r.manager and vai_o[r.manager.vai] then r.manager.o = vai_o[r.manager.vai] end
      for _, w in ipairs(r.worker or {}) do if vai_o[w.vai] then w.o = vai_o[w.vai] end end
      ghi_so_doi_file(path, r)
    end
  end
end

-- Mở lại cả bố cục đã lưu vào cửa sổ — đường DUY NHẤT cho Resume lúc mở WezTerm, Ctrl+Shift+O và menu `ai`.
-- Trả về số tab sẽ mở; xong hết (cả 2 pha) thì gọi xong(số ô đã mở).
local function restore_layout(window, d, xong)
  local g = wezterm.GLOBAL
  if (g.xep_den or 0) > os.time() and g.dang_mo_lai then
    window:toast_notification('WezTerm · đội AI', '⏳ Đang mở lại phiên trước, đợi xong rồi hãy mở tiếp', nil, 4000)
    return 0
  end
  local mw = window:mux_window()
  local plans, tong, so_ai = {}, 0, 0
  for _, t in ipairs(d and d.tabs or {}) do
    local ok, plan = pcall(plan_tab, t)
    if not ok then wezterm.log_error('plan_tab: ' .. tostring(plan))
    elseif plan then
      table.insert(plans, plan)
      for _, s in ipairs(plan.steps) do tong = tong + 1; if la_ai(s.it) then so_ai = so_ai + 1 end end
    end
  end
  if #plans == 0 then return 0 end
  g.phien_da_mo = {} -- mỗi lần mở lại: đếm lại phiên nào đã có ô giữ (chống 2 ô cùng một phiên)
  g.dang_mo_lai = true
  -- tạm dừng thanh tên 🏷 / bảng 📊 / tự ngủ / tự lưu trong lúc xếp; mỗi nhịp gia hạn thêm
  local function giu(sec) g.xep_den = os.time() + sec; g.ten_o_hoan = os.time() + sec + 15 end
  giu(30)
  local giay = math.ceil(tong * GAP_KHUNG + so_ai * GAP_AI)
  if giay >= 3 then
    window:toast_notification('WezTerm · đội AI', '⏮ Đang mở lại ' .. tong .. ' ô: xếp khung trước, rồi bật AI lần lượt (~' .. giay .. ' giây) — cứ để yên', nil, 8000)
  end
  local cho = {} -- file .go của các ô AI, theo đúng thứ tự mở
  local da_mo = 0

  -- PHA 2: thả từng ô AI một
  local function bat_ai(k)
    local go = cho[k]
    if not go then -- xong hết
      g.dang_mo_lai = nil
      g.xep_den = os.time() + 3
      g.ten_o_hoan = os.time() + 12 -- đợi bố cục ổn định rồi mới dựng thanh tên
      if xong then pcall(xong, da_mo) end
      return
    end
    local f = io.open(go, 'w')
    if f then f:write('go') f:close() end
    giu(30)
    wezterm.time.call_after(GAP_AI, function() bat_ai(k + 1) end)
  end

  -- PHA 1: dựng khung từng ô một
  local pi, si = 1, 1
  local function buoc()
    local plan = plans[pi]
    if not plan then
      wezterm.time.call_after(1.0, function() bat_ai(1) end) -- 1 giây cho bố cục ổn định rồi mới bật AI
      return
    end
    local s = plan.steps[si]
    local ok, err = pcall(function()
      local it = s.it
      local args, go = restore_args(it), nil
      if la_ai(it) then args, go = cho_luot(args) end
      local p
      if not s.from then
        local tab
        tab, p = mw:spawn_tab { cwd = safe_cwd(it.cwd), args = args }
        plan.tab = tab
        if plan.title and plan.title ~= '' then tab:set_title(plan.title) end
      else
        local parent = plan.made[s.from] or plan.made[1] -- ô cha lỗi → tách từ ô đầu tab cho khỏi mất ô
        if not parent then error('tab chưa mở được ô đầu') end
        p = parent:split { direction = s.dir, size = s.size, cwd = safe_cwd(it.cwd), args = args }
      end
      plan.made[si] = p
      if go then table.insert(cho, go) end
    end)
    if ok then da_mo = da_mo + 1 else wezterm.log_error('restore: ' .. tostring(err)) end
    if not ok and not s.from then si = #plan.steps end -- không mở được tab thì bỏ cả tab
    si = si + 1
    if si > #plan.steps then
      pcall(function() if plan.made[1] then plan.made[1]:activate() end end)
      local okd, errd = pcall(ghi_so_doi, plan)
      if not okd then wezterm.log_error('ghi_so_doi: ' .. tostring(errd)) end
      pi, si = pi + 1, 1
    end
    giu(30)
    wezterm.time.call_after(GAP_KHUNG, buoc)
  end
  buoc()
  return #plans
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
      restore_layout(w, read_json(LAYOUT[id]), function(n)
        w:toast_notification('WezTerm · đội AI', '✅ Đã mở lại ' .. n .. ' ô', nil, 4000)
      end)
    end),
  }, pane)
end)

-- Menu `ai` chọn "2) Mở lại tất cả phiên đang làm dở" → PowerShell gửi biến wez_ai=mo-lai (OSC 1337 SetUserVar)
-- → mở lại bố cục phiên trước (Claude tiếp đúng phiên, Codex resume) rồi đóng ô menu.
wezterm.on('user-var-changed', function(window, pane, name, value)
  if name ~= 'wez_ai' then return end
  -- 04/10: "mo-file:<đường dẫn>" = mở lại từ một file bố cục bất kỳ (dùng để CHẠY THỬ cách mở 2 pha, vd bố cục giả không có AI)
  local tep = value:match('^mo%-file:(.+)$')
  if tep then
    local d = read_json(tep)
    if d and d.tabs and restore_layout(window, d, function(n)
      window:toast_notification('WezTerm · đội AI', '✅ Chạy thử: đã mở ' .. n .. ' ô', nil, 4000)
    end) > 0 then kill_pane(pane) end
    return
  end
  if value ~= 'mo-lai' then return end
  local d
  for _, k in ipairs { 'prev', 'saved', 'auto' } do
    local x = read_json(LAYOUT[k])
    if x and x.tabs and #x.tabs > 0 then d = x break end
  end
  if not d then
    window:toast_notification('WezTerm · đội AI', 'Chưa có phiên nào được lưu để mở lại', nil, 4000)
    return
  end
  if restore_layout(window, d) > 0 then kill_pane(pane) end -- đóng đúng ô menu (CloseCurrentPane có thể đóng nhầm ô đang chọn sau khi mở lại các tab)
end)

-- Tự lưu mỗi 30 giây (03/10: trước là 1 phút — trạng thái "đang làm" mới hơn khi mở lại), chỉ khi có từ 2 ô (để một lần mở thử 1 ô không đè mất bố cục cũ)
local last_autosave = 0
local function autosave()
  if os.time() - last_autosave < 30 then return end
  if dang_xep() then return end -- đang mở lại / xếp đội: bố cục dở dang, lưu lúc này sẽ đè mất bản đầy đủ
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
    -- 04/10: log GUI (wezterm-gui.exe-log-*) giữ 5 bản mới nhất; log lệnh cli (rất nhiều, mỗi lệnh wez.ps1 một file) xoá sau 1 ngày.
    -- Trước đây gộp chung "giữ 5 file" → log cli đẩy mất log GUI của phiên trước, không tra được lỗi treo.
    "$d = \"$HOME\\.local\\share\\wezterm\"; Get-ChildItem $d -Filter 'wezterm-gui*log*' -File | Sort-Object LastWriteTime -Descending | Select-Object -Skip 5 | Remove-Item -ErrorAction SilentlyContinue; "
    .. "Get-ChildItem $d -Filter 'wezterm.exe-log*' -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } | Remove-Item -ErrorAction SilentlyContinue; "
    .. "$w = \"$env:LOCALAPPDATA\\wez-ai\"; Get-ChildItem \"$w\\giao\",\"$w\\git-nho\" -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } | Remove-Item -ErrorAction SilentlyContinue; "
    .. "Get-ChildItem $w -Filter 'ntfy-*.txt' -File -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue; "
    .. "Get-ChildItem $w -Filter 'mo-*.go' -File -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue" } -- vé mở ô (04/10) của ô đã đóng trước khi tới lượt
end)
