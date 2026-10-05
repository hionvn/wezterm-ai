// khoa.js — "khoá file" để Claude và Codex không sửa chồng lên cùng một file.
// Khoá lưu ở %LOCALAPPDATA%\wez-ai\khoa.json, mỗi khoá tự hết hạn sau 30 phút không đụng tới.
// Chủ khoá = ô WezTerm (WEZTERM_PANE); khoá của ô đã đóng coi như hết hiệu lực.
//
// AI tự gọi (Codex — Claude được làm tự động qua hooks):
//   node khoa.js giu <file> [--ai codex] [--ghi "đang sửa phần giá"]   giữ file trước khi sửa (bị người khác giữ → mã thoát 1)
//   node khoa.js tha <file>                                            thả khi sửa xong
//   node khoa.js tha-het                                               thả mọi khoá của ô này
//   node khoa.js kiem <file>                                           xem file có đang bị ô khác giữ không (mã thoát 1 = có)
//   node khoa.js xem                                                   liệt kê các khoá còn hiệu lực
// Hooks của Claude (~/.claude/settings.json):
//   PreToolUse  (Edit|Write|MultiEdit|NotebookEdit) → node khoa.js hook-truoc  : chặn nếu ô khác đang giữ
//   PostToolUse (Edit|Write|MultiEdit|NotebookEdit) → node khoa.js hook-sau    : tự giữ file vừa sửa
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const HAN = 30 * 60; // giây
const base = path.join(process.env.LOCALAPPDATA || '', 'wez-ai');
const FILE = path.join(base, 'khoa.json');
const me = process.env.WEZTERM_PANE || 'ngoai-wezterm';
const now = () => Math.floor(Date.now() / 1000);
const key = (f) => path.resolve(f).toLowerCase();

function load() {
  try { return JSON.parse(fs.readFileSync(FILE, 'utf8')); } catch { return {}; }
}
function save(locks) {
  fs.mkdirSync(base, { recursive: true });
  const tmp = FILE + '.' + process.pid;
  fs.writeFileSync(tmp, JSON.stringify(locks, null, 1));
  fs.renameSync(tmp, FILE);
}

// Cửa sổ WezTerm đang chạy = file gui-sock-<pid> có tiến trình <pid> còn sống (mới nhất).
// Số ô (PANEID) đánh lại từ 0 mỗi lần mở lại WezTerm → khoá ghi kèm tên cửa sổ; khác cửa sổ = khoá cũ, bỏ.
function liveGui() {
  const dir = path.join(process.env.USERPROFILE || '', '.local', 'share', 'wezterm');
  let best = null;
  try {
    for (const n of fs.readdirSync(dir)) {
      const m = /^gui-sock-(\d+)$/.exec(n);
      if (!m) continue;
      try { process.kill(Number(m[1]), 0); } catch { continue; } // tiến trình đã tắt
      const full = path.join(dir, n), t = fs.statSync(full).mtimeMs;
      if (!best || t > best.t) best = { full, name: n, t };
    }
  } catch {}
  return best;
}
const GUI = liveGui();
const myGui = process.env.WEZTERM_UNIX_SOCKET ? path.basename(process.env.WEZTERM_UNIX_SOCKET) : (GUI && GUI.name) || '';

// Các ô WezTerm còn mở (chỉ hỏi khi thật sự có tranh chấp, vì gọi wezterm cli mất ~0.2 giây)
let alivePanes;
function paneAlive(id) {
  if (!/^\d+$/.test(String(id))) return true;
  if (!GUI) return false; // WezTerm không chạy → không ô nào còn mở
  if (!alivePanes) {
    // 04/10: đọc wez-ai\o-list.json (Lua ghi ≤ 10 giây/lần) trước — cli list bắt WezTerm hỏi thư mục mọi ô trên luồng giao diện
    try {
    // 05/10: chấp nhận file cũ tới 2 phút (hook này chạy mỗi lần AI sửa file — gọi cli list lúc WezTerm nghẽn làm nghẽn thêm)
      const ol = path.join(process.env.LOCALAPPDATA || '', 'wez-ai', 'o-list.json');
      if (Date.now() - fs.statSync(ol).mtimeMs < 120000) alivePanes = new Set(JSON.parse(fs.readFileSync(ol, 'utf8')).map((p) => String(p.pane_id)));
    } catch {}
  }
  if (!alivePanes) {
    try {
      let exe = 'C:\\Program Files\\WezTerm\\wezterm.exe';
      try { exe = JSON.parse(fs.readFileSync(path.join(process.env.USERPROFILE || '', '.wez-ai.json'), 'utf8')).wezterm || exe; } catch {}
      // --no-auto-start: không tìm thấy WezTerm thì báo lỗi, KHÔNG tự bật wezterm-mux-server ngầm
      const out = execFileSync(exe, ['cli', '--no-auto-start', 'list', '--format', 'json'],
        { encoding: 'utf8', timeout: 3000, env: { ...process.env, WEZTERM_UNIX_SOCKET: GUI.full } });
      alivePanes = new Set(JSON.parse(out).map((p) => String(p.pane_id)));
    } catch { return true; } // không hỏi được thì coi như còn sống cho chắc
  }
  return alivePanes.has(String(id));
}

// Khoá của lần mở WezTerm trước (khác cửa sổ) hoặc ô đã đóng / quá hạn → coi như không còn
function stale(l) {
  if (now() - l.t > HAN) return true;
  if (l.gui && GUI && l.gui !== GUI.name) return true;
  return !paneAlive(l.pane);
}

// Khoá do ô khác giữ, còn hạn, ô đó còn mở → trả về khoá; không thì null
function heldByOther(locks, k) {
  const l = locks[k];
  if (!l || (String(l.pane) === String(me) && (!l.gui || l.gui === myGui))) return null;
  if (stale(l)) { delete locks[k]; return null; }
  return l;
}
function describe(l) {
  const phut = Math.max(1, Math.round((now() - l.t) / 60));
  return `${l.ai || 'AI'} ở ô ${l.pane} (${l.du_an || '?'})${l.ghi ? ' — ' + l.ghi : ''}, đụng tới ${phut} phút trước`;
}
function take(locks, file, ai, ghi) {
  locks[key(file)] = { file: path.resolve(file), pane: me, gui: myGui, ai, du_an: path.basename(process.cwd()), ghi: ghi || '', t: now() };
}
function arg(name) {
  const i = process.argv.indexOf('--' + name);
  return i > 0 ? process.argv[i + 1] : undefined;
}

const [cmd, file] = process.argv.slice(2);

if (cmd === 'hook-truoc' || cmd === 'hook-sau') {
  let input = '';
  process.stdin.on('data', (c) => (input += c));
  process.stdin.on('end', () => {
    let data = {};
    try { data = JSON.parse(input.replace(/^\uFEFF/, '')); } catch { return; }
    const ti = data.tool_input || {};
    const f = ti.file_path || ti.notebook_path;
    if (!f) return;
    const locks = load();
    const other = heldByOther(locks, key(f));
    if (cmd === 'hook-truoc') {
      if (other) {
        process.stderr.write(`⛔ File ${f} đang được ${describe(other)} sửa. ` +
          'Đừng sửa file này lúc này: báo người dùng, hoặc làm việc khác rồi thử lại sau. ' +
          '(Người dùng muốn bỏ khoá: node khoa.js tha <file> chạy ở ô đang giữ, hoặc đợi 30 phút.)\n');
        process.exit(2); // mã 2 = chặn công cụ, lý do gửi lại cho Claude
      }
      return;
    }
    if (!other) { take(locks, f, 'Claude'); try { save(locks); } catch {} }
  });
} else if (cmd === 'giu' && file) {
  const locks = load();
  const other = heldByOther(locks, key(file));
  if (other) { console.log(`⛔ Đang bị giữ bởi ${describe(other)}. Đừng sửa file này.`); process.exit(1); }
  take(locks, file, arg('ai') || 'AI', arg('ghi'));
  save(locks);
  console.log(`🔒 Đã giữ ${path.resolve(file)} (hết hạn sau 30 phút không đụng tới).`);
} else if (cmd === 'tha' && file) {
  const locks = load();
  const l = locks[key(file)];
  if (l && (String(l.pane) === String(me) || stale(l))) { delete locks[key(file)]; save(locks); console.log('🔓 Đã thả ' + l.file); }
  else if (l) console.log('Khoá này không phải của ô bạn (' + describe(l) + ').');
  else console.log('File này không bị khoá.');
} else if (cmd === 'tha-het') {
  const locks = load();
  let n = 0;
  for (const k of Object.keys(locks)) if (String(locks[k].pane) === String(me)) { delete locks[k]; n++; }
  save(locks);
  console.log(`🔓 Đã thả ${n} khoá của ô ${me}.`);
} else if (cmd === 'kiem' && file) {
  const locks = load();
  const other = heldByOther(locks, key(file));
  if (other) { console.log('⛔ ' + describe(other)); process.exit(1); }
  console.log('✅ Không ai khác đang giữ file này.');
} else if (cmd === 'xem') {
  const locks = load();
  let n = 0;
  for (const k of Object.keys(locks)) {
    const l = locks[k];
    if (stale(l)) { delete locks[k]; continue; }
    console.log(`🔒 ${l.file}\n    ${describe(l)}${String(l.pane) === String(me) ? '  ← ô này' : ''}`);
    n++;
  }
  try { save(locks); } catch {}
  if (!n) console.log('Không có file nào đang bị khoá.');
} else {
  console.log('Cách dùng: node khoa.js giu|tha|kiem <file> [--ai tên] [--ghi "ghi chú"]  ·  tha-het  ·  xem');
  process.exit(1);
}
