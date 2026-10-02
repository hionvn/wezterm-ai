-- Cấu hình WezTerm của đội AI (Hion) — BỘ NẠP (tách file 03/10/2026).
-- Nội dung thật nằm ở ~\.wezterm\NN-ten.lua (01-co-ban … 12-menu). Bộ nạp ghép các phần theo thứ tự tên
-- rồi chạy như MỘT file → mọi biến `local` dùng chung giữa các phần y như trước khi tách.
-- Sửa phần nào thì mở đúng file đó; WezTerm tự nạp lại khi bất kỳ phần nào đổi.
-- Lỗi được báo theo "tên phần:dòng", vd "06-bo-cuc.lua:42: …".
-- Kiểm tra trước khi lưu: E:\AI\Hion\cai-dat\kiem-cau-hinh.ps1 (cap-nhat.ps1 tự chạy).
local wezterm = require 'wezterm'
local dir = wezterm.home_dir .. '\\.wezterm'
local files = wezterm.glob(dir:gsub('\\', '/') .. '/[0-9][0-9]-*.lua')
table.sort(files)

local parts, map, line = {}, {}, 1
for _, f in ipairs(files) do
  local h = io.open(f, 'rb')
  local s = h and h:read('*a') or ''
  if h then h:close() end
  s = s:gsub('^\239\187\191', '') -- bỏ BOM nếu có
  local n = select(2, s:gsub('\n', '\n')) + 1 -- số dòng của phần này
  table.insert(map, { from = line, to = line + n - 1, name = f:match('[^/\\]+$') })
  table.insert(parts, s)
  line = line + n
  wezterm.add_to_config_reload_watch_list(f)
end

-- đổi "số dòng trong file ghép" → "tên phần:dòng" cho dễ tìm lỗi
local function cho_loi(msg)
  return (tostring(msg):gsub('doi%-ai:(%d+):', function(d)
    d = tonumber(d)
    for _, m in ipairs(map) do
      if d >= m.from and d <= m.to then return m.name .. ':' .. (d - m.from + 1) .. ':' end
    end
    return 'doi-ai:' .. d .. ':'
  end))
end
_G.WEZ_CHO_LOI = cho_loi -- dùng khi đọc log lỗi lúc chạy: WEZ_CHO_LOI(thông báo)

-- WezTerm gặp cấu hình lỗi thì lặng lẽ dùng cấu hình mặc định, không in lỗi ra đâu cả → bộ nạp tự ghi lỗi ra file
-- để kiem-cau-hinh.ps1 đọc (nó đặt biến WEZ_KIEM_LOI = đường dẫn file khi chạy thử).
local function bao_loi(msg)
  local p = os.getenv('WEZ_KIEM_LOI') or ((os.getenv('LOCALAPPDATA') or '') .. '\\wez-ai\\loi-cau-hinh.txt')
  local h = io.open(p, 'w')
  if h then h:write(msg) h:close() end
  error(msg)
end

if #parts == 0 then bao_loi('Không thấy file nào trong ' .. dir .. ' (cần 01-co-ban.lua … 12-menu.lua)') end
local chunk, err = load(table.concat(parts, '\n'), '=doi-ai', 't')
if not chunk then bao_loi(cho_loi(err)) end
local ok, cfg = xpcall(chunk, function(e) return cho_loi(e) .. '\n' .. debug.traceback() end)
if not ok then bao_loi(cfg) end
return cfg
