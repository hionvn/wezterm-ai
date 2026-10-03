// Company Brain (theo thầy Sơn, BTO buổi 8: 03:00 gom mọi dữ liệu về một chỗ) — chỉ đọc file + git, KHÔNG gọi AI (không tốn hạn mức).
//   node brain.js            → E:\AI\Hion\brain\hom-nay.md (≤ 2 trang, Tổng quản đọc file này TRƯỚC thay vì mở từng tien-do)
//                              + brain\du-an\<DựÁn>.md (chi tiết) + brain\brain.json (cho script) + brain\lich-su\<ngày>-<giờ>.md
//   node brain.js --linear   → thêm ticket Linear chưa xong (cần 1Password mở khoá — chỉ dùng ban ngày)
// Task Scheduler: WezAI-Brain-dem 03:00 · WezAI-Brain-trua 12:00 (--linear).
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const HOME = process.env.USERPROFILE || '';
const cfg = (() => { try { return JSON.parse(fs.readFileSync(path.join(HOME, '.wez-ai.json'), 'utf8').replace(/^\uFEFF/, '')); } catch { return {}; } })();
const ROOT = cfg.aiRoot || 'E:\\AI';
const HUB = path.join(ROOT, 'Hion');
const OUT = path.join(HUB, 'brain');
const AIDIR = path.join(process.env.LOCALAPPDATA || '', 'wez-ai');
const read = (f) => { try { return fs.readFileSync(f, 'utf8').replace(/^\uFEFF/, '').replace(/\r\n/g, '\n'); } catch { return ''; } };
const readJson = (f) => { try { return JSON.parse(read(f)); } catch { return null; } };
const git = (dir, ...a) => { try { return execFileSync('git', ['-C', dir, ...a], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch { return ''; } };
const plain = (s) => s.replace(/\*\*|`/g, '').replace(/^\s*[-*]\s+(\[[ x]\]\s*)?/, '').trim();
const cut = (s, n) => (s.length > n ? s.slice(0, n - 1).trimEnd() + '…' : s);
function section(text, name) {
  const m = text.match(new RegExp(`^## ${name}[^\\n]*\\n([\\s\\S]*?)(?=^## |(?![\\s\\S]))`, 'm'));
  return m ? m[1].trim() : '';
}
const bullets = (s) => s.split('\n').filter((l) => /^\s*[-*] /.test(l) && !/^\s{2,}/.test(l)).map(plain).filter(Boolean);
const pad = (n) => String(n).padStart(2, '0');
const d = new Date();
const today = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const gio = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
const vn = (x) => `${pad(x.getDate())}/${pad(x.getMonth() + 1)}/${x.getFullYear()}`;

// ---- Dự án: mọi thư mục có AGENTS.md, xếp theo cay-du-an.json ----
const cay = (readJson(path.join(HUB, 'cay-du-an.json')) || {}).cay || [];
const dirs = fs.readdirSync(ROOT, { withFileTypes: true }).filter((e) => e.isDirectory() && fs.existsSync(path.join(ROOT, e.name, 'AGENTS.md'))).map((e) => e.name);
const order = [...cay.map((c) => c.ten).filter((n) => dirs.includes(n)), ...dirs.filter((n) => !cay.some((c) => c.ten === n)).sort()];
const logo = Object.fromEntries(cay.map((c) => [c.ten, c.logo || c.bieuTuong || '·']));

const duAn = order.map((ten) => {
  const dir = path.join(ROOT, ten);
  const td = fs.readdirSync(dir).find((f) => /^tien-do-.*\.md$/.test(f));
  const t = td ? read(path.join(dir, td)) : '';
  const log24 = git(dir, 'log', '--since=24.hours', '--format=%h %s').split('\n').filter(Boolean);
  const log7 = git(dir, 'log', '--since=7.days', '--date=format:%d/%m', '--format=%cd %s').split('\n').filter(Boolean);
  const doi24 = [...new Set(git(dir, 'log', '--since=24.hours', '--name-only', '--format=').split('\n').filter(Boolean))];
  const ban = git(dir, 'status', '--short').split('\n').filter(Boolean);
  const truoc = git(dir, 'rev-list', '--count', '@{u}..HEAD');
  return {
    ten, logo: logo[ten] || '·', soTienDo: td || null,
    lam: bullets(section(t, 'Đang làm')), ket: bullets(section(t, 'Đang kẹt')), canDuyet: bullets(section(t, 'Cần duyệt')),
    xongGanDay: bullets(section(t, 'Đã xong')).slice(0, 5),
    commit24: log24, commit7: log7.length, log7: log7.slice(0, 15), fileDoi24: doi24, chuaLuu: ban.length, chuaDay: Number(truoc) || 0,
  };
});

// ---- Chung: tiền, việc chờ duyệt, quyết định, việc đang giao, hạn mức, eval ----
const tienTxt = (read(path.join(ROOT, '1Bill', 'so-tien.md')).match(/Cộng dồn:\s*([\d.]+)\s*đ/) || [])[1] || '0';
const START = new Date(2026, 9, 2);
const ngayN = Math.min(100, Math.max(1, Math.floor((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - START) / 864e5) + 1));
const choDuyet = bullets(section(read(path.join(HUB, 'can-duyet.md')), 'Đang chờ'));
const qd = read(path.join(HUB, 'quyet-dinh.md')).split('\n').filter((l) => l.includes(vn(d)) || l.includes(vn(new Date(d - 864e5)))).map(plain);
let viec = readJson(path.join(AIDIR, 'viec.json')) || [];
if (!Array.isArray(viec)) viec = viec.value || [];
const now = Date.now() / 1000;
const dangGiao = viec.filter((v) => v && !v.xong && !v.bo).map((v) => ({ so: v.so, ai: v.ai, viec: cut(String(v.viec || ''), 110), gio: Math.round((now - v.t) / 360) / 10 }));
const xong24 = viec.filter((v) => v && v.xong && now - v.xong < 86400).length;
const fc = readJson(path.join(AIDIR, 'fuel-claude.json'));
const evalMoi = fs.existsSync(path.join(HUB, 'learn')) ? fs.readdirSync(path.join(HUB, 'learn')).filter((f) => /^so-lieu-.*\.json$/.test(f)).sort().pop() : null;
const ev = evalMoi ? readJson(path.join(HUB, 'learn', evalMoi)) : null;
const baiHoc = read(path.join(HUB, 'learn', 'bai-hoc.md')).split('\n').filter((l) => /^\|/.test(l) && !/^\|\s*(Bài học|---)/.test(l)).map((l) => l.split('|').map((x) => x.trim()).filter(Boolean)).filter((c) => c.length >= 2);

// ---- Linear (tuỳ chọn, ban ngày) ----
let linear = null;
if (process.argv.includes('--linear')) {
  try {
    const out = execFileSync('node', [path.join(HUB, 'cai-dat', 'linear.js'), 'ds'], { encoding: 'utf8', timeout: 60000, stdio: ['ignore', 'pipe', 'ignore'] });
    linear = out.split('\n').filter((l) => /^[A-Z]+-\d+/.test(l));
  } catch { linear = null; }
}

// ---- Viết ----
for (const sub of ['du-an', 'lich-su']) fs.mkdirSync(path.join(OUT, sub), { recursive: true });
const ds = (xs, n, rong = '—') => (xs.length ? xs.slice(0, n).map((x) => `  - ${cut(x, 140)}`).join('\n') + (xs.length > n ? `\n  - … +${xs.length - n}` : '') : `  - ${rong}`);
const md = [
  `# 🧠 Company Brain · ${vn(d)} ${gio}`,
  `_Tự gom bởi cai-dat\\brain.js (chỉ đọc file + git). Tổng quản đọc file này trước; cần chi tiết mới mở brain\\du-an\\<DựÁn>.md hoặc tien-do của dự án._`, '',
  `## Toàn cục`,
  `- **1Bill:** Ngày ${ngayN}/100 · tiền đã về ${tienTxt}đ / mục tiêu tới hôm nay ${(ngayN * 10).toLocaleString('vi-VN')} triệu`,
  `- **Chờ Hion duyệt:** ${choDuyet.length} việc${choDuyet.length ? ' — ' + choDuyet.slice(0, 3).map((x) => cut(x, 70)).join(' · ') : ''}`,
  `- **Việc đang giao (chưa xong):** ${dangGiao.length} · xong 24 giờ qua: ${xong24}`,
  `- **Hạn mức Claude:** 5 giờ ${fc ? fc.five : '?'}% · tuần ${fc ? fc.week : '?'}%`,
  ev ? `- **Eval gần nhất (${ev.ngay}):** giao ${ev.tong.giao} · xong ${ev.tong.xong} · bỏ ${ev.tong.bo} · dở ${ev.tong.dang}` : '- **Eval:** chưa có',
  baiHoc.length ? `- **Bài học đang theo dõi:** ${baiHoc.length} — nhiều nhất: ${cut(baiHoc.sort((a, b) => Number(b[1]) - Number(a[1]))[0][0], 90)}` : '',
  '',
  `## Dự án`,
  ...duAn.map((p) => [
    `### ${p.logo} ${p.ten} · ${p.commit24.length} commit/24h · ${p.commit7} commit/7 ngày${p.chuaLuu ? ` · ✎ ${p.chuaLuu} file chưa commit` : ''}${p.chuaDay ? ` · ↑ ${p.chuaDay} commit chưa push` : ''}`,
    `- ⏳ Đang làm:\n${ds(p.lam, 3)}`,
    p.ket.length ? `- 🧱 Kẹt:\n${ds(p.ket, 3)}` : '',
    p.canDuyet.length ? `- 🔔 Cần duyệt:\n${ds(p.canDuyet, 3)}` : '',
    p.commit24.length ? `- 🔨 24 giờ qua:\n${ds(p.commit24.map((c) => c.replace(/^\w+ /, '')), 3)}` : '',
    p.soTienDo ? '' : '- ⚠️ Chưa có file tien-do',
  ].filter(Boolean).join('\n')),
  '',
  dangGiao.length ? `## Việc đang giao (☐)\n${dangGiao.slice(0, 15).map((v) => `- #${v.so} ${v.ai} · ${v.gio} giờ · ${v.viec}`).join('\n')}${dangGiao.length > 15 ? `\n- … +${dangGiao.length - 15}` : ''}\n` : '',
  qd.length ? `## Quyết định hôm qua / hôm nay\n${qd.slice(-10).map((q) => `- ${cut(q, 160)}`).join('\n')}\n` : '',
  linear ? `## Linear (ticket chưa xong: ${linear.length})\n${linear.slice(0, 20).map((l) => `- ${cut(l, 140)}`).join('\n')}\n` : '',
].filter((x) => x !== '').join('\n');
fs.writeFileSync(path.join(OUT, 'hom-nay.md'), md);
fs.writeFileSync(path.join(OUT, 'lich-su', `${today}-${gio.replace(':', '')}.md`), md);

for (const p of duAn) {
  const s = [
    `# ${p.logo} ${p.ten} — chi tiết (Brain ${vn(d)} ${gio})`, '',
    `## Đang làm\n${ds(p.lam, 50)}`, `## Đang kẹt\n${ds(p.ket, 50)}`, `## Cần duyệt\n${ds(p.canDuyet, 50)}`, `## Đã xong gần đây\n${ds(p.xongGanDay, 5)}`,
    `## Commit 7 ngày (${p.commit7})\n${ds(p.log7, 15)}`,
    `## File đổi trong 24 giờ (${p.fileDoi24.length})\n${ds(p.fileDoi24, 40)}`,
    `## Git\n  - chưa commit: ${p.chuaLuu} file · chưa push: ${p.chuaDay} commit`,
  ].join('\n\n');
  fs.writeFileSync(path.join(OUT, 'du-an', `${p.ten}.md`), s);
}
fs.writeFileSync(path.join(OUT, 'brain.json'), JSON.stringify({ luc: d.toISOString(), ngayN, tien: tienTxt, choDuyet, dangGiao, xong24, claude: fc, eval: ev, duAn, linear }, null, 2));

// Lịch sử: giữ 30 ngày
const han = Date.now() - 30 * 864e5;
for (const f of fs.readdirSync(path.join(OUT, 'lich-su'))) { const p = path.join(OUT, 'lich-su', f); if (fs.statSync(p).mtimeMs < han) fs.unlinkSync(p); }
console.log(`🧠 Brain ${gio}: ${duAn.length} dự án · ${choDuyet.length} chờ duyệt · ${dangGiao.length} việc đang giao → ${path.join(OUT, 'hom-nay.md')}`);
