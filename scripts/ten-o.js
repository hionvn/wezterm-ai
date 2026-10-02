// Thanh tên 1 dòng trên đỉnh mỗi ô AI trong WezTerm: "🤖 Claude · Chatbot › thư-mục-con", nền màu dự án, giãn theo bề ngang ô.
// WezTerm (~\.wezterm.lua, hàm process_headers) tự tách ô này phía trên ô AI và ghi thông tin vào %LOCALAPPDATA%\wez-ai\ten-o.json:
//   { "tat": false, "o": { "<id ô tên>": { "icon": "🤖", "ai": "Claude", "proj": "Chatbot", "logo": "💬", "sub": "...", "color": "#c678dd" } } }
// Ô tên tự đóng khi không còn trong file (ô AI bên dưới đã đóng, chuyển tab, hoặc tắt bằng Ctrl+Shift+T).
const fs = require('fs');
const path = require('path');

const ME = process.env.WEZTERM_PANE || '';
const FILE = path.join(process.env.LOCALAPPDATA || path.join(require('os').homedir(), 'AppData', 'Local'), 'wez-ai', 'ten-o.json');
const ESC = '\x1b';
let info = null, missing = 0, last = '';

function hex(c) {
  const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(c || '');
  return m ? [1, 2, 3].map(i => parseInt(m[i], 16)) : [90, 100, 110];
}
// Chiều rộng hiển thị gần đúng: emoji / ký tự rộng tính 2 ô
function width(s) {
  let w = 0;
  for (const ch of s) {
    const cp = ch.codePointAt(0);
    if (cp === 0xfe0f || cp === 0x200d) continue;
    w += cp >= 0x1f000 || (cp >= 0x2600 && cp <= 0x27bf) ? 2 : 1;
  }
  return w;
}

function draw() {
  const cols = process.stdout.columns || 80;
  let text = '';
  let bg = [60, 66, 78];
  if (info) {
    // ô đang chọn: nền màu dự án + dấu ▶ (nổi lên); ô khác: nền xám tối
    bg = info.active ? hex(info.color) : [52, 56, 62];
    text = ` ${info.active ? '▶' : ' '} ${info.icon || '▪️'} ${info.ai} · ${info.logo ? info.logo + ' ' : ''}${String(info.proj || '?').toUpperCase()}` + (info.sub ? `  › ${String(info.sub).replace(/\\/g, '/')}` : '');
  }
  // cắt bớt nếu ô hẹp, rồi tô kín cả dòng
  while (width(text) > cols - 1 && text.length) text = [...text].slice(0, -1).join('');
  const pad = Math.max(0, cols - width(text));
  const fg = (bg[0] * 0.299 + bg[1] * 0.587 + bg[2] * 0.114) > 150 ? '30;30;30' : '255;255;255';
  const out = `${ESC}[H${ESC}[48;2;${bg.join(';')}m${ESC}[38;2;${fg}m${ESC}[1m${text}${' '.repeat(pad)}${ESC}[0m`;
  if (out !== last) { process.stdout.write(out); last = out; }
}

function tick() {
  let data = null;
  try { data = JSON.parse(fs.readFileSync(FILE, 'utf8')); } catch { /* file đang được ghi: thử lại lần sau */ return; }
  const it = data && !data.tat && data.o && data.o[ME];
  if (!it) {
    if (++missing >= 4) { process.stdout.write(`${ESC}[0m${ESC}[?25h`); process.exit(0); } // ~4 giây không thấy → tự đóng
    return;
  }
  missing = 0;
  info = it;
  draw();
}

process.stdout.write(`${ESC}]0;🏷 ten-o${'\x07'}${ESC}[?25l${ESC}[2J`); // tiêu đề ô (để WezTerm nhận ra), ẩn con trỏ
process.stdout.on('resize', () => { last = ''; process.stdout.write(`${ESC}[2J`); draw(); });
process.stdin.on('data', () => {}); // nuốt phím lỡ gõ vào ô tên
try { process.stdin.setRawMode && process.stdin.setRawMode(true); process.stdin.resume(); } catch {}
setInterval(tick, 1000);
tick();
