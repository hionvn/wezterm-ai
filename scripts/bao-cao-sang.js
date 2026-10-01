// Báo cáo sáng của Tổng quản (giống "Morning Overview" buổi 8 BTO): gom một trang để người dùng đọc đầu ngày.
//   node bao-cao-sang.js [--mo]      # viết E:\AI\Hion\bao-cao\<yyyy-mm-dd>.md; --mo = bật lên ô 📄
// ~/.wezterm.lua tự chạy mỗi ngày từ 7 giờ (lần đầu WezTerm mở). Chỉ đọc file + git, không sửa dự án nào.
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

function aiRoot() {
  try {
    const c = JSON.parse(fs.readFileSync(path.join(process.env.USERPROFILE || '', '.wez-ai.json'), 'utf8').replace(/^\uFEFF/, ''));
    if (c.aiRoot) return c.aiRoot;
  } catch (_) { }
  return 'E:\\AI';
}
const ROOT = aiRoot();
const HUB = path.join(ROOT, 'Hion');
const read = (f) => { try { return fs.readFileSync(f, 'utf8').replace(/^\uFEFF/, '').replace(/\r\n/g, '\n'); } catch (_) { return ''; } };
const git = (dir, ...a) => { try { return execFileSync('git', ['-C', dir, ...a], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch (_) { return null; } };

// Lấy một mục "## <tên>" trong file markdown (tới mục ## kế tiếp)
function section(text, name) {
  const m = text.match(new RegExp(`^## ${name}[^\\n]*\\n([\\s\\S]*?)(?=^## |(?![\\s\\S]))`, 'm'));
  return m ? m[1].trim() : '';
}

const pad = (n) => String(n).padStart(2, '0');
const d = new Date();
const today = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const yday = new Date(d - 864e5);
const ydayVN = `${pad(yday.getDate())}/${pad(yday.getMonth() + 1)}/${yday.getFullYear()}`;
const todayVN = `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()}`;
const thu = ['Chủ nhật', 'Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7'][d.getDay()];

const out = [`# ☀️ Báo cáo sáng · ${thu} ${todayVN}`, ''];

// 1. Việc chờ duyệt
const cho = section(read(path.join(HUB, 'can-duyet.md')), 'Đang chờ');
const items = cho.split('\n').filter((l) => /^- /.test(l));
out.push(`## 🔔 Chờ bạn duyệt (${items.length})`);
out.push(items.length ? items.map((l, i) => `${i + 1}. ${l.slice(2)}`).join('\n') : '✅ Không có.');
out.push('', '👉 Duyệt bằng nút trong ô 📋 (Ctrl+Shift+J), hoặc nhắn Claude Hion "duyệt 1".', '');

// 2. Quyết định hôm qua + hôm nay
const qd = read(path.join(HUB, 'quyet-dinh.md')).split('\n').filter((l) => l.includes(ydayVN) || l.includes(todayVN));
if (qd.length) out.push('## 📝 Quyết định gần đây', ...qd, '');

// 3. Từng dự án: tiến độ + git (Hion, wezterm-ai là hạ tầng → không cần sổ tiến độ)
const HA_TANG = ['Hion', 'wezterm-ai'];
out.push('## 📁 Dự án');
const dirs = fs.readdirSync(ROOT, { withFileTypes: true }).filter((e) => e.isDirectory() && fs.existsSync(path.join(ROOT, e.name, 'AGENTS.md')));
for (const e of dirs) {
  const dir = path.join(ROOT, e.name);
  out.push('', `### ${e.name}`);
  const g = [];
  const last = git(dir, 'log', '-1', '--date=format:%d/%m %H:%M', '--format=%cd · %s');
  if (last) g.push(`commit cuối: ${last}`);
  const n24 = git(dir, 'rev-list', '--count', '--since=24.hours', 'HEAD');
  if (n24 && n24 !== '0') g.push(`${n24} commit trong 24h`);
  const st = git(dir, 'status', '--short');
  if (st) g.push(`⚠️ ${st.split('\n').length} file chưa commit`);
  if (g.length) out.push(`- 🌿 ${g.join(' · ')}`);
  const td = fs.readdirSync(dir).find((f) => /^tien-do-.*\.md$/.test(f));
  if (!td) { if (!HA_TANG.includes(e.name)) out.push('- ⚠️ Chưa có sổ tiến độ `tien-do-*.md`'); continue; }
  const t = read(path.join(dir, td));
  const cap = (t.match(/Cập nhật:\s*([^\n]+)/) || [])[1];
  if (cap) out.push(`- Sổ tiến độ cập nhật: ${cap.trim()}`);
  for (const [name, icon] of [['Đang làm', '⏳'], ['Đang kẹt', '🧱']]) {
    const s = section(t, name);
    if (s) out.push(`- ${icon} **${name}:**`, ...s.split('\n').filter((l) => l.trim()).map((l) => '  ' + l));
  }
}

// 4. Hạn mức AI (statusline.js ghi)
const AIDIR = path.join(process.env.LOCALAPPDATA || '', 'wez-ai');
try {
  const f = JSON.parse(read(path.join(AIDIR, 'fuel-claude.json')));
  const pct = (v) => (typeof v === 'number' ? `${Math.round(v)}%` : null);
  const a = pct(f.five), b = pct(f.week);
  if (a || b) out.push('', '## ⛽ Hạn mức Claude', `- 5 giờ: ${a || '?'} · tuần: ${b || '?'}`);
} catch (_) { }

out.push('', '---', `_Tạo tự động lúc ${pad(d.getHours())}:${pad(d.getMinutes())} bởi cai-dat\\bao-cao-sang.js_`, '');

const dirOut = path.join(HUB, 'bao-cao');
fs.mkdirSync(dirOut, { recursive: true });
const file = path.join(dirOut, `${today}.md`);
fs.writeFileSync(file, out.join('\n'), 'utf8');
console.log('Đã viết ' + file);
if (process.argv.includes('--mo')) {
  execFileSync('node', [path.join(__dirname, 'mo-tai-lieu.js'), file], { stdio: 'inherit' });
}
