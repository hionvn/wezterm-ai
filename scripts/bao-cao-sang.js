// Báo cáo sáng của Tổng quản: một trang ngắn, nhìn là hiểu (sơ đồ cây đội agent, thanh tiến độ, biểu đồ nhỏ).
//   node bao-cao-sang.js [--mo]   # viết E:\AI\Hion\bao-cao\<yyyy-mm-dd>.html (+ .md ngắn cho AI / điện thoại); --mo = mở trang trên trình duyệt
// ~/.wezterm.lua tự chạy mỗi ngày từ 7 giờ (lần đầu WezTerm mở). Chỉ đọc file + git, không sửa dự án nào.
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const HOME = process.env.USERPROFILE || '';
function aiRoot() {
  try {
    const c = JSON.parse(fs.readFileSync(path.join(HOME, '.wez-ai.json'), 'utf8').replace(/^\uFEFF/, ''));
    if (c.aiRoot) return c.aiRoot;
  } catch (_) { }
  return 'E:\\AI';
}
const ROOT = aiRoot();
const HUB = path.join(ROOT, 'Hion');
const read = (f) => { try { return fs.readFileSync(f, 'utf8').replace(/^\uFEFF/, '').replace(/\r\n/g, '\n'); } catch (_) { return ''; } };
const readJson = (f) => { try { return JSON.parse(read(f)); } catch (_) { return null; } };
const git = (dir, ...a) => { try { return execFileSync('git', ['-C', dir, ...a], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch (_) { return null; } };
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const plain = (s) => s.replace(/\*\*|`/g, '').replace(/^\s*[-*]\s+/, '').trim();          // bỏ ký hiệu markdown
const cut = (s, n) => (s.length > n ? s.slice(0, n - 1).trimEnd() + '…' : s);
function section(text, name) {                                                                   // mục "## <tên>" của file markdown
  const m = text.match(new RegExp(`^## ${name}[^\\n]*\\n([\\s\\S]*?)(?=^## |(?![\\s\\S]))`, 'm'));
  return m ? m[1].trim() : '';
}
const bullets = (s) => s.split('\n').filter((l) => /^\s*[-*] /.test(l) && !/^\s{2,}/.test(l)).map(plain).filter(Boolean);

const pad = (n) => String(n).padStart(2, '0');
const d = new Date();
const today = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const ymd = (x) => `${x.getFullYear()}-${pad(x.getMonth() + 1)}-${pad(x.getDate())}`;
const vn = (x) => `${pad(x.getDate())}/${pad(x.getMonth() + 1)}/${x.getFullYear()}`;
const todayVN = vn(d), ydayVN = vn(new Date(d - 864e5));
const thu = ['Chủ nhật', 'Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7'][d.getDay()];
const days7 = [...Array(7)].map((_, i) => new Date(d - (6 - i) * 864e5));

// ---------- Dữ liệu ----------
// 1Bill: Ngày X/100 + tiền cộng dồn (chỉ tiền đã về, ghi ở so-tien.md)
const START = new Date(2026, 9, 2);
const dayN = Math.min(100, Math.max(1, Math.floor((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - START) / 864e5) + 1));
const tienTxt = (read(path.join(ROOT, '1Bill', 'so-tien.md')).match(/Cộng dồn:\s*([\d.]+)\s*đ/) || [])[1] || '0';
const tien = Number(tienTxt.replace(/\./g, '')) || 0;
const mucTieu = dayN * 10_000_000;
const trieu = (v) => (!v ? '0 đ' : v >= 1e9 ? (v / 1e9).toLocaleString('vi-VN', { maximumFractionDigits: 2 }) + ' tỷ' : Math.round(v / 1e6).toLocaleString('vi-VN') + ' triệu');

// Việc chờ duyệt
const cho = bullets(section(read(path.join(HUB, 'can-duyet.md')), 'Đang chờ')).map((l) => {
  const m = l.match(/^\[([^\]]+)\]\s*(.*)$/);
  return m ? { tag: m[1], text: m[2] } : { tag: '', text: l };
});
const quyetDinh = read(path.join(HUB, 'quyet-dinh.md')).split('\n').filter((l) => l.includes(ydayVN) || l.includes(todayVN)).map(plain);

// Cây dự án (Hion\cay-du-an.json) + mọi thư mục có AGENTS.md
const cay = (readJson(path.join(HUB, 'cay-du-an.json')) || {}).cay || [];
const dirs = fs.readdirSync(ROOT, { withFileTypes: true }).filter((e) => e.isDirectory() && fs.existsSync(path.join(ROOT, e.name, 'AGENTS.md'))).map((e) => e.name);
const order = [...cay.filter((n) => dirs.includes(n.ten)), ...dirs.filter((n) => !cay.some((c) => c.ten === n)).sort().map((n) => ({ ten: n, cap: -1, bieuTuong: '·', vai: 'khác' }))];
const projects = order.map((n) => {
  const dir = path.join(ROOT, n.ten);
  const perDay = Object.fromEntries(days7.map((x) => [ymd(x), 0]));
  (git(dir, 'log', '--since=7.days', '--date=format:%Y-%m-%d', '--format=%cd') || '').split('\n').forEach((x) => { if (x in perDay) perDay[x]++; });
  const st = git(dir, 'status', '--short');
  const last = git(dir, 'log', '-1', '--date=format:%d/%m %H:%M', '--format=%cd|%s');
  const td = fs.readdirSync(dir).find((f) => /^tien-do-.*\.md$/.test(f));
  const t = td ? read(path.join(dir, td)) : '';
  return {
    ...n, commits: Object.values(perDay), dirty: st ? st.split('\n').length : 0,
    last: last ? { when: last.split('|')[0], msg: last.split('|').slice(1).join('|') } : null,
    lam: bullets(section(t, 'Đang làm')), ket: bullets(section(t, 'Đang kẹt')), coSo: !!td,
  };
});

// Hạn mức: Claude (statusline.js ghi) + từng tài khoản Codex (file phiên mới nhất trong CODEX_HOME)
const AIDIR = path.join(process.env.LOCALAPPDATA || '', 'wez-ai');
const fuel = [];
const fc = readJson(path.join(AIDIR, 'fuel-claude.json'));
if (fc) fuel.push({ ten: 'Claude', five: fc.five, week: fc.week });
function newestJsonl(dir, depth = 0) {
  let best = null;
  try {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      const c = e.isDirectory() ? (depth < 4 ? newestJsonl(p, depth + 1) : null) : (e.name.endsWith('.jsonl') ? { p, t: fs.statSync(p).mtimeMs } : null);
      if (c && (!best || c.t > best.t)) best = c;
    }
  } catch (_) { }
  return best;
}
const doiCa = readJson(path.join(HOME, '.codex-tai-khoan.json'));   // bảng tài khoản Codex theo dự án
for (const tk of (doiCa && doiCa.taiKhoan) || [{ ten: 'Codex', thuMuc: path.join(HOME, '.codex') }]) {
  const f = newestJsonl(path.join(tk.thuMuc, 'sessions'));
  if (!f) continue;
  const fd = fs.openSync(f.p, 'r'); const size = fs.fstatSync(fd).size; const buf = Buffer.alloc(Math.min(size, 262144));
  fs.readSync(fd, buf, 0, buf.length, size - buf.length); fs.closeSync(fd);
  const s = buf.toString('utf8');
  const all = (re) => [...s.matchAll(re)].map((m) => Number(m[1]));
  const five = all(/"primary":\{"used_percent":([\d.]+)/g).pop(), week = all(/"secondary":\{"used_percent":([\d.]+)/g).pop();
  const duAn = Object.entries((doiCa && doiCa.duAn) || {}).filter(([, v]) => v === tk.so).map(([k]) => k).join(', ');
  if (five !== undefined) fuel.push({ ten: tk.ten || 'Codex', duAn, five, week, cu: Date.now() - f.t > 5 * 3600e3 });
}

// ---------- Trang HTML ----------
const level = (p) => (p >= 80 ? ['crit', '🔴'] : p >= 50 ? ['warn', '🟡'] : ['good', '🟢']);
function meter(label, p, note) {
  if (typeof p !== 'number') return '';
  const v = Math.round(p), [cls, ic] = level(v);
  return `<div class="meter"><span class="ml">${esc(label)}</span><span class="track"><span class="fill ${cls}" style="width:${Math.min(100, v)}%"></span></span><span class="mv">${ic} ${v}%</span>${note ? `<span class="mn">${esc(note)}</span>` : ''}</div>`;
}
function spark(arr) {                                     // 7 cột commit/ngày, một màu; rê chuột xem số
  const max = Math.max(1, ...arr), W = 7 * 12 - 2, H = 26;
  const bars = arr.map((v, i) => {
    const h = v ? Math.max(3, Math.round((v / max) * (H - 2))) : 1;
    return `<rect x="${i * 12}" y="${H - h}" width="10" height="${h}" rx="${v ? 2 : 0}" class="${v ? 'bar' : 'bar0'}"><title>${vn(days7[i]).slice(0, 5)}: ${v} commit</title></rect>`;
  }).join('');
  return `<svg class="spark" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="Commit 7 ngày: ${arr.join(', ')}">${bars}</svg>`;
}
function node(p) {
  const tong = p.commits.reduce((a, b) => a + b, 0);
  const chips = [
    p.ket.length ? `<span class="chip warn">🧱 ${p.ket.length} kẹt</span>` : '',
    p.dirty ? `<span class="chip muted">✎ ${p.dirty} file chưa lưu</span>` : '',
    p.cap === 1 && !p.coSo ? '<span class="chip warn">⚠ thiếu sổ tiến độ</span>' : '',
  ].join('');
  const lam = p.lam[0] ? `<p class="now">⏳ ${esc(cut(p.lam[0], 110))}</p>` : '';
  const more = (p.lam.length > 1 || p.ket.length) ? `<details><summary>Chi tiết</summary>${p.lam.slice(1).map((l) => `<p>⏳ ${esc(l)}</p>`).join('')}${p.ket.map((l) => `<p>🧱 ${esc(l)}</p>`).join('')}</details>` : '';
  return `<div class="node lv${p.cap}${p.ten === 'Hion' ? ' boss' : ''}"><div class="nh"><span class="ic">${p.bieuTuong || '·'}</span><b>${esc(p.ten)}</b><span class="role">${esc(p.vai || '')}</span></div>
    <div class="nb">${spark(p.commits)}<span class="cnt">${tong} commit / 7 ngày</span></div>${chips ? `<div class="chips">${chips}</div>` : ''}${lam}${more}</div>`;
}
const root = projects.filter((p) => p.cap === 0 && p.ten === 'Hion');
const pms = projects.filter((p) => p.cap === 1);
const tools = projects.filter((p) => !(p.cap === 0 && p.ten === 'Hion') && p.cap !== 1);
const pctTien = Math.min(100, (tien / 1e9) * 100), pctNgay = (dayN / 100) * 100;
const cham = tien < mucTieu;

const html = `<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Báo cáo sáng ${todayVN}</title>
<style>
:root{--bg:#f3f4f2;--panel:#fff;--ink:#1c2226;--muted:#5f6a70;--line:#d9dedc;--accent:#2a6f8f;--accent-soft:#dcebf2;--good:#2e7d4f;--warn:#a86b00;--crit:#b3392f;--bar0:#d9dedc}
@media (prefers-color-scheme:dark){:root{--bg:#14181a;--panel:#1d2326;--ink:#e5e9e8;--muted:#9aa5a9;--line:#323b3f;--accent:#6db8d8;--accent-soft:#1d3540;--good:#6fcf97;--warn:#f0b35e;--crit:#ff8a80;--bar0:#323b3f;color-scheme:dark}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 "Segoe UI",system-ui,sans-serif}
.wrap{max-width:1040px;margin:0 auto;padding:24px 16px 48px;display:grid;gap:20px}
h1{margin:0;font-size:1.5rem}h2{margin:0 0 10px;font-size:1.02rem}.muted{color:var(--muted)}
.card{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:16px 18px;min-width:0}
.hero{display:grid;grid-template-columns:auto 1fr;gap:18px;align-items:center}
.day{font:700 2.4rem/1 "Segoe UI",sans-serif;color:var(--accent);font-variant-numeric:tabular-nums}.day small{font-size:1rem;color:var(--muted)}
.prog{display:grid;gap:8px}.row{display:grid;grid-template-columns:110px 1fr auto;gap:10px;align-items:center;font-size:.9rem;font-variant-numeric:tabular-nums}
.track{height:10px;background:var(--bar0);border-radius:5px;overflow:hidden;display:block}.fill{display:block;height:100%;border-radius:5px;background:var(--accent)}
.fill.good{background:var(--good)}.fill.warn{background:var(--warn)}.fill.crit{background:var(--crit)}
.verdict{font-size:.88rem}.verdict.bad{color:var(--crit)}.verdict.ok{color:var(--good)}
.todo{display:grid;gap:8px;margin:0;padding:0;list-style:none;counter-reset:n}
.todo li{display:grid;grid-template-columns:28px 1fr;gap:8px;align-items:start;font-size:.92rem}
.todo li::before{counter-increment:n;content:counter(n);width:24px;height:24px;border-radius:50%;background:var(--accent-soft);color:var(--accent);font-weight:700;display:grid;place-items:center;font-size:.8rem}
.tag{display:inline-block;font-size:.72rem;font-weight:700;padding:0 6px;border-radius:4px;background:var(--accent-soft);color:var(--accent);margin-right:6px}
/* Sơ đồ cây: Tổng quản ở trên, các PM một hàng, đường nối bằng viền */
.tree{display:grid;gap:0;justify-items:center}
.tree .top{width:min(420px,100%)}
.stem{width:2px;height:18px;background:var(--line)}
.branch{display:grid;grid-template-columns:repeat(${Math.max(1, pms.length)},minmax(0,1fr));gap:12px;width:100%;position:relative;padding-top:18px}
.branch::before{content:"";position:absolute;top:0;left:calc(100%/${Math.max(1, pms.length)}/2);right:calc(100%/${Math.max(1, pms.length)}/2);height:2px;background:var(--line)}
.branch>.node{position:relative}.branch>.node::before{content:"";position:absolute;top:-18px;left:50%;width:2px;height:18px;background:var(--line)}
@media (max-width:760px){.branch{grid-template-columns:minmax(0,1fr)}.branch::before,.branch>.node::before{display:none}}
.node{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:10px 12px;display:grid;gap:6px;min-width:0}
.node.boss{border-color:var(--accent);border-width:2px}
.nh{display:flex;flex-wrap:wrap;gap:4px 8px;align-items:baseline}.nh .role{font-size:.78rem;color:var(--muted)}
.nb{display:flex;gap:8px;align-items:center}.cnt{font-size:.78rem;color:var(--muted);font-variant-numeric:tabular-nums}
.spark .bar{fill:var(--accent)}.spark .bar0{fill:var(--bar0)}
.chips{display:flex;flex-wrap:wrap;gap:4px}.chip{font-size:.74rem;padding:1px 7px;border-radius:999px;border:1px solid var(--line)}
.chip.warn{color:var(--warn);border-color:currentColor}.chip.muted{color:var(--muted)}
.now{margin:0;font-size:.84rem}details{font-size:.82rem;color:var(--muted)}details p{margin:4px 0}summary{cursor:pointer}
.tools{display:flex;flex-wrap:wrap;gap:12px;justify-content:center;margin-top:14px;width:100%}.tools .node{flex:1 1 240px;max-width:340px}
.meter{display:grid;grid-template-columns:150px 1fr 70px;gap:10px;align-items:center;font-size:.88rem;font-variant-numeric:tabular-nums}
.meter .mn{grid-column:1/-1;font-size:.76rem;color:var(--muted);margin-top:-4px}
.fuel{display:grid;gap:12px}.fuelgrp{display:grid;gap:6px}.fuelgrp b{font-size:.88rem}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:20px}@media (max-width:760px){.grid2{grid-template-columns:1fr}.hero{grid-template-columns:1fr}.row{grid-template-columns:90px 1fr auto}.meter{grid-template-columns:110px 1fr 64px}}
ul.qd{margin:0;padding-left:18px;font-size:.86rem;display:grid;gap:4px}
footer{font-size:.78rem;color:var(--muted)}
</style></head><body><div class="wrap">
<header><h1>☀️ Báo cáo sáng · ${thu} ${todayVN}</h1></header>

<section class="card hero" aria-label="Tiến độ 1Bill">
  <div class="day">Ngày ${dayN}<small>/100</small></div>
  <div class="prog">
    <div class="row"><span>💰 Tiền đã về</span><span class="track"><span class="fill" style="width:${pctTien}%"></span></span><b>${trieu(tien)}</b></div>
    <div class="row"><span>📅 Thời gian</span><span class="track"><span class="fill" style="width:${pctNgay}%;opacity:.45"></span></span><span>${dayN}%</span></div>
    <div class="verdict ${cham ? 'bad' : 'ok'}">${cham ? `⚠️ Chậm ${trieu(mucTieu - tien)} so với mục tiêu tới hôm nay (${trieu(mucTieu)}).` : '✅ Đúng hoặc vượt mục tiêu tới hôm nay.'} Nguồn tiền: Chatbot.</div>
  </div>
</section>

<div class="grid2">
  <section class="card"><h2>🔔 Chờ anh duyệt (${cho.length})</h2>
    ${cho.length ? `<ol class="todo">${cho.map((c) => `<li><span>${c.tag ? `<span class="tag">${esc(c.tag)}</span>` : ''}${esc(cut(c.text, 150))}</span></li>`).join('')}</ol>` : '<p class="muted">✅ Không có việc nào.</p>'}
    <p class="muted" style="font-size:.8rem;margin:10px 0 0">Bấm nút trong ô 📋 (Ctrl+Shift+J) hoặc nhắn Hion "duyệt 1".</p>
  </section>
  <section class="card"><h2>⛽ Hạn mức AI</h2><div class="fuel">
    ${fuel.map((f) => `<div class="fuelgrp"><b>${esc(f.ten)}${f.duAn ? ` <span class="muted">· ${esc(f.duAn)}</span>` : ''}</b>${meter('5 giờ', f.five)}${meter('Tuần', f.week, f.cu ? 'số từ phiên cũ hơn 5 giờ, có thể đã làm mới' : '')}</div>`).join('') || '<p class="muted">Chưa có số liệu.</p>'}
  </div></section>
</div>

<section class="card" aria-label="Sơ đồ đội agent"><h2>🗺️ Đội agent · 7 ngày qua</h2>
  <div class="tree">
    ${root.map((p) => `<div class="top">${node(p)}</div><div class="stem"></div>`).join('')}
    <div class="branch">${pms.map(node).join('')}</div>
    ${tools.length ? `<div class="tools">${tools.map(node).join('')}</div>` : ''}
  </div>
</section>

${quyetDinh.length ? `<section class="card"><h2>📝 Quyết định hôm qua / hôm nay</h2><ul class="qd">${quyetDinh.map((q) => `<li>${esc(cut(q, 180))}</li>`).join('')}</ul></section>` : ''}
<footer>Tạo tự động lúc ${pad(d.getHours())}:${pad(d.getMinutes())} bởi Hion\\cai-dat\\bao-cao-sang.js · chỉ đọc file và git, không sửa dự án nào.</footer>
</div></body></html>`;

// ---------- Bản .md ngắn (cho AI và điện thoại) ----------
const md = [
  `# ☀️ Báo cáo sáng · ${thu} ${todayVN}`, '',
  `**Ngày ${dayN}/100** · tiền đã về ${trieu(tien)} / mục tiêu tới hôm nay ${trieu(mucTieu)}${cham ? ' ⚠️ chậm' : ' ✅'}`, '',
  `## 🔔 Chờ duyệt (${cho.length})`, ...(cho.length ? cho.map((c, i) => `${i + 1}. ${c.tag ? `[${c.tag}] ` : ''}${cut(c.text, 150)}`) : ['✅ Không có.']), '',
  '## 🗺️ Dự án', ...projects.map((p) => `- ${p.bieuTuong || '·'} **${p.ten}** · ${p.commits.reduce((a, b) => a + b, 0)} commit/7 ngày${p.ket.length ? ` · 🧱 ${p.ket.length} kẹt` : ''}${p.dirty ? ` · ✎ ${p.dirty} file chưa lưu` : ''}${p.lam[0] ? `\n  ⏳ ${cut(p.lam[0], 110)}` : ''}`), '',
  '## ⛽ Hạn mức', ...fuel.map((f) => `- ${f.ten}: 5 giờ ${Math.round(f.five ?? 0)}% · tuần ${Math.round(f.week ?? 0)}%`), '',
  `_Bản đẹp có sơ đồ: bao-cao\\${today}.html_`, '',
].join('\n');

const dirOut = path.join(HUB, 'bao-cao');
fs.mkdirSync(dirOut, { recursive: true });
const fileHtml = path.join(dirOut, `${today}.html`);
fs.writeFileSync(fileHtml, html, 'utf8');
fs.writeFileSync(path.join(dirOut, `${today}.md`), md, 'utf8');
console.log('Đã viết ' + fileHtml);
if (process.argv.includes('--mo')) {
  execFileSync('cmd.exe', ['/c', 'start', '""', fileHtml], { stdio: 'ignore' });   // mở trên trình duyệt mặc định
}
