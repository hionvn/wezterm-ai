-- ===== Thanh trạng thái (thêm 01/10/2026; bản cũ: .wezterm.lua.bak-before-statusbar) =====
-- Tên tab: số · biểu tượng AI · dự án (màu theo dự án, giống thanh trạng thái Claude)
-- Góc phải: AI · dự án › thư mục con · 🌿 nhánh git · số ô · giờ, ngày
config.use_fancy_tab_bar = false
config.tab_max_width = 28
config.show_new_tab_button_in_tab_bar = false -- bỏ nút "+" cho thanh tab gọn (mở tab: Ctrl+Shift+T)
config.colors = config.colors or {}
config.colors.tab_bar = { background = '#15181c' } -- nền thanh tab tối hẳn để các khối màu dự án nổi lên
config.status_update_interval = 2000
-- 04/10/2026 (chuột đơ khi ~35 ô AI chạy): luồng giao diện WezTerm đo 71% một nhân → bớt việc vẽ:
-- 30 khung/giây (mặc định 60, chữ vẫn mượt) · không vẽ hiệu ứng chuyển mờ · con trỏ không nhấp nháy (nhấp nháy = vẽ lại mọi ô)
config.max_fps = 30
config.animation_fps = 1
config.cursor_blink_rate = 0

-- Màu + logo riêng từng dự án: lấy từ Hion\cay-du-an.json (trường "mau", "logo"); dự án lạ → màu theo tên, logo 📁
local proj_colors = { hion = '#e5c07b', sino = '#e06c75', coolguy = '#61afef', chatbot = '#c678dd' }
local proj_logos = {}
do
  local f = io.open(HUB .. '\\cay-du-an.json', 'rb')
  if f then
    local ok, v = pcall(wezterm.json_parse, (f:read('*a'):gsub('^\239\187\191', '')))
    f:close()
    if ok and v and v.cay then
      for _, n in ipairs(v.cay) do
        if n.mau then proj_colors[n.ten:lower()] = n.mau end
        if n.logo then proj_logos[n.ten:lower()] = n.logo end
      end
    end
  end
end
local function proj_logo(name) return proj_logos[(name or ''):lower()] or '📁' end
local palette = { '#56b6c2', '#98c379', '#d19a66', '#c678dd', '#61afef' }
local function proj_color(name)
  name = name or '?'
  local c = proj_colors[name:lower()]
  if c then return c end
  local h = 0
  for i = 1, #name do h = (h * 31 + name:byte(i)) % 1000003 end
  return palette[h % #palette + 1]
end

-- Lấy đường dẫn thư mục của ô (dạng E:\AI\Sino\...)
local function pane_dir(p)
  local cwd = p.current_working_dir
  if cwd == nil then return nil end
  local s = type(cwd) == 'userdata' and (cwd.file_path or tostring(cwd)) or tostring(cwd)
  s = s:gsub('^file://[^/]*', ''):gsub('^/(%a:)', '%1'):gsub('/', '\\'):gsub('\\$', '')
  return s
end

-- Dự án = thư mục ngay dưới AI_ROOT (E:\AI) ; phần sau là thư mục con
local ROOT_PREFIX = AI_ROOT:lower() .. '\\'
local function split_project(dir)
  if not dir then return '?', nil end
  if dir:lower():sub(1, #ROOT_PREFIX) == ROOT_PREFIX then
    local proj, rest = dir:sub(#ROOT_PREFIX + 1):match('^([^\\]+)\\?(.*)$')
    if proj then return proj, (rest ~= '' and rest or nil) end
  end
  return dir:match('([^\\]+)$') or dir, nil
end

-- AI nào đang chạy trong ô (dựa vào tiến trình + tiêu đề)
local function which_ai(p)
  local s = ((p.foreground_process_name or '') .. ' ' .. (p.title or '')):lower()
  if s:find('codex') then return '🧩', 'Codex' end
  -- tiêu đề Codex kiểu "Chatbot | Ready | tên phiên" / "| Working |" không có chữ codex (03/10: mở lại bị nhận nhầm là PowerShell)
  if s:find('| ready |', 1, true) or s:find('| working |', 1, true) or s:find('| waiting', 1, true) then return '🧩', 'Codex' end
  if s:find('claude') or s:find('✳') or s:find('◐') or s:find('◓') or s:find('◑') or s:find('◒') then return '🤖', 'Claude' end
  if s:find('powershell') or s:find('pwsh') then return '⌨️', 'PowerShell' end
  return '▪️', nil
end

-- Nhánh git: đọc thẳng file .git\HEAD (không chạy lệnh git nên không chậm)
local GIT_MEMO = {} -- [thư mục] = { t, nhánh } — thanh phải vẽ mỗi 2 giây, nhánh hiếm khi đổi
local git_branch_raw
local function git_branch(dir)
  local m = GIT_MEMO[dir]
  if m and os.time() - m.t < 15 then return m.b end
  local b = git_branch_raw(dir)
  GIT_MEMO[dir] = { t = os.time(), b = b }
  return b
end
git_branch_raw = function(dir)
  local d = dir
  while d and d ~= '' do
    local f = io.open(d .. '\\.git\\HEAD', 'r')
    if f then
      local head = f:read('*l') or ''
      f:close()
      return head:match('ref: refs/heads/(.+)') or head:sub(1, 7)
    end
    local parent = d:match('^(.*)\\[^\\]+$')
    if parent == nil or parent == d then break end
    d = parent
  end
  return nil
end
