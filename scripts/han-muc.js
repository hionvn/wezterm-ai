// Hạn mức mọi gói AI cho góc TRÁI thanh tab WezTerm (19/10 chiều: chuyển từ phải sang trái, có ▶ ĐANG DÙNG / ⏸ CHỜ / ⛔ HẾT) (19/10/2026, người dùng yêu cầu).
// Gom 60 giây/lần → %LOCALAPPDATA%\wez-ai\han-muc.json ({ t, text, parts:[{c,t}] }) + han-muc.txt. Lua (11-cap-nhat.lua) chỉ đọc file.
// Dùng: node han-muc.js        → chạy 1 lần, in dòng hạn mức (tự kiểm)
//       node han-muc.js chay   → chạy nền mãi (Lua tự bật khi file cũ > 5 phút; đã có bản chạy thì thoát)
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const AIDIR = path.join(process.env.LOCALAPPDATA || '', 'wez-ai');
const R9 = path.join(process.env.APPDATA || '', '9router');
const GROK_EXE = path.join(process.env.USERPROFILE || '', '.grok', 'bin', 'grok.exe'); // giống ngam.js: không có Grok thì bỏ qua
const XANH = '#98c379', CAM = '#e5a050', DO = '#e06c75', XAM = '#7f848e', CHU = '#abb2bf';

const docJson = f => { try { return JSON.parse(fs.readFileSync(path.join(AIDIR, f), 'utf8')); } catch { return null; } };
const gio = s => { const d = new Date(s * 1000); return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0'); };
const mau = p => p >= 100 ? DO : p >= 85 ? CAM : XANH;

// Số liệu 1 tài khoản Claude (statusline.js ghi theo CLAUDE_CONFIG_DIR); het = claude-het-*.json của ngam.js
function soClaude(file, hetFile, now) {
  const c = docJson(file), het = docJson(hetFile);
  if (het && het.den > now) return { het: het.den };
  if (!c) return {};
  const five = c.five_reset && c.five_reset < now ? 0 : Math.round(c.five || 0);
  const week = c.week_reset && c.week_reset < now ? 0 : Math.round(c.week || 0);
  return { five, week, cu: now - (c.t || 0) > 3600, het: five >= 100 ? c.five_reset : week >= 100 ? c.week_reset : 0 };
}

async function so9r(now) {
  const tok = crypto.createHash('sha256').update(fs.readFileSync(path.join(R9, 'machine-id'), 'utf8').trim() + '9r-cli-auth'
    + fs.readFileSync(path.join(R9, 'auth', 'cli-secret'), 'utf8').trim()).digest('hex').slice(0, 16);
  const get = async u => (await fetch('http://127.0.0.1:20128' + u, { headers: { 'x-9r-cli-token': tok }, signal: AbortSignal.timeout(8000) })).json();
  const cs = ((await get('/api/providers')).connections || []).filter(c => c.provider === 'codex' && c.isActive !== false);
  let con = 0, hoi = 0, tuan = null;
  for (const c of cs) {
    const u = await get('/api/usage/' + c.id).catch(() => null);
    const s = u && u.quotas && u.quotas.session, w = u && u.quotas && u.quotas.weekly;
    const ws = w && Date.parse(w.resetAt) / 1000 > now ? w.used : 0;
    if (u && !u.limitReached && ws < 100) con++;
    else if (s && u.plan !== 'free') { const r = Date.parse(s.resetAt) / 1000; if (r > now && (!hoi || r < hoi)) hoi = r; }
    if (w && u.plan !== 'free' && (tuan === null || ws < tuan)) tuan = ws; // tuần: tài khoản Plus còn nhiều nhất
  }
  return { con, tong: cs.length, hoi, tuan };
}

// Số worker ngầm đang chạy theo AI (ngam\*.json, trang_thai "chay"): codex = GPT qua 9router
function demChay() {
  const n = { claude: 0, codex: 0, grok: 0 }, dir = path.join(AIDIR, 'ngam');
  let fs_ = []; try { fs_ = fs.readdirSync(dir).filter(f => f.endsWith('.json')); } catch {}
  for (const f of fs_) { try { const s = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')); if (s.trang_thai === 'chay' && s.ai in n) n[s.ai]++; } catch {} }
  return n;
}

// Thứ tự worker giống ngam.js (thuTu + claudeTk, 19/10): Grok → GPT 9router → Claude vuanhtuanfpt → Claude hionvn.
// Gói đầu tiên chưa hết = ▶ ĐANG DÙNG, gói sau còn hạn mức = ⏸ CHỜ, gói hết = ⛔ HẾT ↻giờ hồi. hionvn luôn chạy ô Tổng quản.
async function gom() {
  const now = Date.now() / 1000, parts = [], SEP = { c: '#5c6370', t: ' │ ' }, chay = demChay();
  const g = docJson('grok-het.json'), rh = docJson('router-het.json');
  const goi = [];
  goi.push({ ten: 'Grok', het: !fs.existsSync(GROK_EXE) ? -1 : g && g.den > now ? g.den : 0, n: chay.grok });
  let r9 = null; try { r9 = await so9r(now); } catch {}
  goi.push({ ten: 'GPT 9router', het: rh && rh.den > now ? rh.den : !r9 ? -1 : r9.con === 0 ? (r9.hoi || -1) : 0, n: chay.codex,
    them: r9 ? r9.con + '/' + r9.tong + ' tk còn' + (r9.tuan !== null ? ' · tuần ' + Math.round(r9.tuan) + '%' : '') : '9router tắt' });
  for (const [ten, f, h] of [['Claude vuanh', 'fuel-claude-vuanhtuanfpt.json', 'claude-het-chinh.json'], ['Claude hionvn', 'fuel-claude-hionvn.json', 'claude-het-tk2.json']]) {
    const c = soClaude(f, h, now);
    goi.push({ ten, het: c.het || 0, cu: c.cu, them: c.five == null ? 'chưa có số' : '5h ' + c.five + '% · tuần ' + c.week + '%', pct: c.five });
  }
  goi[3].tq = true;
  const dangDung = goi.findIndex(x => x.het === 0); // -1 = mọi gói hết
  // worker Claude chạy ngầm tính cho tài khoản claudeTk đang chọn (vuanh, hết thì hionvn)
  (goi[2].het === 0 ? goi[2] : goi[3]).n = chay.claude;
  goi.forEach((x, i) => {
    if (i) parts.push(SEP);
    parts.push({ c: CHU, t: x.ten + ' ' });
    if (x.het > 0 || x.het === -1) {
      parts.push({ c: DO, t: (x.het === -1 ? '⛔ KHÔNG DÙNG ĐƯỢC' : '⛔ HẾT ↻' + gio(x.het)) });
    } else if (i === dangDung || x.n > 0 || x.tq) {
      const ai = [x.n ? x.n + ' worker' : i === dangDung ? 'worker' : '', x.tq ? 'Tổng quản' : ''].filter(Boolean).join(' + ');
      parts.push({ c: x.pct >= 85 ? CAM : XANH, t: '▶ ĐANG DÙNG' + (ai ? ' (' + ai + ')' : '') });
    } else parts.push({ c: XAM, t: '⏸ CHỜ' });
    if (x.them) parts.push({ c: x.cu ? XAM : x.pct >= 85 ? CAM : XAM, t: ' ' + x.them });
  });
  for (const c of docJson('fuel-codex.json') || []) // Codex tài khoản riêng (Lua 07-nhien-lieu.lua ghi), chỉ ô dùng
    parts.push(SEP, { c: CHU, t: (c.icon || 'Codex') + ' ' }, { c: mau(c.five || 0), t: '5h ' + Math.round(c.five || 0) + '%' + (c.week != null ? ' · tuần ' + Math.round(c.week) + '%' : '') });
  parts.push({ c: '#5c6370', t: '  ' + gio(now) + '  ' }); // giờ lấy số
  const text = parts.map(p => p.t).join('');
  fs.mkdirSync(AIDIR, { recursive: true });
  fs.writeFileSync(path.join(AIDIR, 'han-muc.json.tmp'), JSON.stringify({ t: Math.floor(now), text, parts }));
  fs.renameSync(path.join(AIDIR, 'han-muc.json.tmp'), path.join(AIDIR, 'han-muc.json')); // Lua không đọc phải file ghi dở
  fs.writeFileSync(path.join(AIDIR, 'han-muc.txt'), text + '\n');
  return text;
}

if (process.argv[2] === 'chay') {
  const PID = path.join(AIDIR, 'han-muc.pid');
  try { process.kill(Number(fs.readFileSync(PID, 'utf8')), 0); process.exit(0); } catch {} // bản cũ còn sống → thoát
  fs.writeFileSync(PID, String(process.pid));
  const vong = () => gom().catch(() => {}).finally(() => setTimeout(vong, 60000));
  vong();
} else {
  gom().then(t => {
    console.log(t);
    const j = JSON.parse(fs.readFileSync(path.join(AIDIR, 'han-muc.json'), 'utf8'));
    if (!j.text.includes('Claude hionvn') || !j.text.includes('GPT 9router') || !/▶ ĐANG DÙNG/.test(j.text) || !j.parts.every(p => /^#[0-9a-f]{6}$/.test(p.c))) {
      console.error('TỰ KIỂM LỖI: thiếu mục hoặc màu sai'); process.exit(1);
    }
    console.log('Tự kiểm OK');
  }).catch(e => { console.error(e); process.exit(1); });
}
