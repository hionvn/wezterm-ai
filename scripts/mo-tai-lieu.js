// Bật một tài liệu lên màn hình WezTerm cho người dùng đọc / duyệt (giống Mendex của anh Sơn).
// AI gọi khi vừa làm xong một tài liệu cần người dùng xem:
//   node E:\AI\Hion\cai-dat\mo-tai-lieu.js <đường dẫn file .md>
// Ghi yêu cầu vào %LOCALAPPDATA%\wez-ai\open.json; ~/.wezterm.lua thấy thì mở ô "📄 tên file"
// bên phải tab đang xem (thay ô 📄 cũ nếu có) và hiện thông báo Windows.
const fs = require('fs');
const path = require('path');

const arg = process.argv[2];
if (!arg) { console.error('Cách dùng: node mo-tai-lieu.js <đường dẫn file>'); process.exit(1); }
const file = path.resolve(arg);
if (!fs.existsSync(file)) { console.error('Không thấy file: ' + file); process.exit(1); }
const dir = path.join(process.env.LOCALAPPDATA || '', 'wez-ai');
fs.mkdirSync(dir, { recursive: true });
fs.writeFileSync(path.join(dir, 'open.json'), JSON.stringify({
  path: file, from: process.env.WEZTERM_PANE || '', t: Math.floor(Date.now() / 1000),
}));
console.log('Đã gửi yêu cầu mở: ' + file);
