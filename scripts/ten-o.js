// Thanh tên 1 dòng trên đỉnh mỗi ô AI trong WezTerm: "🤖 Claude · Chatbot › thư-mục-con", nền màu dự án, giãn theo bề ngang ô.
// WezTerm (~\.wezterm.lua, hàm process_headers) tự tách ô này phía trên ô AI và ghi thông tin vào %LOCALAPPDATA%\wez-ai\ten-o.json:
//   { "tat": false, "o": { "<id ô tên>": { "icon": "🤖", "ai": "Claude", "proj": "Chatbot", "logo": "💬", "sub": "...", "color": "#c678dd" } } }
// Ô tên tự đóng khi không còn trong file (ô AI bên dưới đã đóng, chuyển tab, hoặc tắt bằng Ctrl+Shift+T).
// Sổ đội %LOCALAPPDATA%\wez-ai\doi\<dự án>.json (manager + worker theo số ô AI) → thanh tên ghi vai + ai quản lý:
//   worker:  "● ⚙️ Engineer · 💬 CHATBOT ← 🧭 Manager ô 25"   manager: "🧭 Manager · 💬 CHATBOT → 4 worker: ô 20-23"
const fs = require('fs');
const path = require('path');

const ME = process.env.WEZTERM_PANE || '';
const WEZAI = path.join(process.env.LOCALAPPDATA || path.join(require('os').homedir(), 'AppData', 'Local'), 'wez-ai');
const FILE = path.join(WEZAI, 'ten-o.json');
const DOI_DIR = path.join(WEZAI, 'doi');
const ESC = '\x1b';
let info = null, missing = 0, last = '';

// Tìm ô AI trong các sổ đội: trả về { vai, quanLy } để thêm vào thanh tên
function roleOf(pane) {
  if (!pane) return null;
  let files = [];
  try { files = fs.readdirSync(DOI_DIR).filter(f => f.endsWith('.json')); } catch { return null; }
  for (const f of files) {
    let d;
    try { d = JSON.parse(fs.readFileSync(path.join(DOI_DIR, f), 'utf8').replace(/^﻿/, '')); } catch { continue; }
    const m = d.manager;
    const ws = d.worker || [];
    if (m && String(m.o) === String(pane)) {
      return { vai: '🧭 Manager', mau: m.mau, them: `→ ${ws.length} worker: ô ${ws.map(w => w.o).join(',')}` };
    }
    const w = ws.find(x => String(x.o) === String(pane));
    if (w) return { vai: `${w.icon} ${w.vai}`, mau: w.mau, them: m ? `← 🧭 Manager ô ${m.o}` : '← chưa có Manager' };
  }
  return null;
}

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
    const r = roleOf(info.pane);
    const proj = `${info.logo ? info.logo + ' ' : ''}${String(info.proj || '?').toUpperCase()}`;
    text = r
      ? ` ${info.active ? '▶' : ' '} ${r.vai} · ${proj}  ${r.them}  (${info.ai})`
      : ` ${info.active ? '▶' : ' '} ${info.icon || '▪️'} ${info.ai} · ${proj}` + (info.sub ? `  › ${String(info.sub).replace(/\\/g, '/')}` : '');
    // ô không chọn mà có vai: nền tối pha màu vai để 4 worker nhìn khác nhau
    if (r && r.mau && !info.active) bg = hex(r.mau).map(c => Math.round(c * 0.45));
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
