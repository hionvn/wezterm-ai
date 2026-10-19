// Hạn mức mọi gói AI cho góc phải thanh tab WezTerm (19/10/2026, người dùng yêu cầu).
// Gom 60 giây/lần → %LOCALAPPDATA%\wez-ai\han-muc.json ({ t, text, parts:[{c,t}] }) + han-muc.txt. Lua (11-cap-nhat.lua) chỉ đọc file.
// Dùng: node han-muc.js        → chạy 1 lần, in dòng hạn mức (tự kiểm)
//       node han-muc.js chay   → chạy nền mãi (Lua tự bật khi file cũ > 5 phút; đã có bản chạy thì thoát)
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const AIDIR = path.join(process.env.LOCALAPPDATA || '', 'wez-ai');
const R9 = path.join(process.env.APPDATA || '', '9router');
const XANH = '#98c379', CAM = '#e5a050', DO = '#e06c75', XAM = '#7f848e', CHU = '#abb2bf';

const docJson = f => { try { return JSON.parse(fs.readFileSync(path.join(AIDIR, f), 'utf8')); } catch { return null; } };
const gio = s => { const d = new Date(s * 1000); return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0'); };
const mau = p => p >= 100 ? DO : p >= 85 ? CAM : XANH;

function claude(parts, ten, file, hetFile, now) {
  const c = docJson(file), het = docJson(hetFile);
  parts.push({ c: CHU, t: ten + ' ' });
  if (het && het.den > now) { parts.push({ c: DO, t: '⛔ ↻' + gio(het.den) }); return; }
  if (!c) { parts.push({ c: XAM, t: '?' }); return; }
  const cu = now - (c.t || 0) > 3600; // > 1 giờ không có ô nào của tài khoản này chạy → số cũ, tô xám
  const five = c.five_reset && c.five_reset < now ? 0 : Math.round(c.five || 0);
  const week = c.week_reset && c.week_reset < now ? 0 : Math.round(c.week || 0);
  parts.push({ c: cu ? XAM : mau(five), t: '5h ' + five + '%' + (five >= 85 && c.five_reset ? ' ↻' + gio(c.five_reset) : '') });
  parts.push({ c: XAM, t: '·T ' });
  parts.push({ c: cu ? XAM : mau(week), t: week + '%' });
}

async function router9(parts, now) {
  parts.push({ c: CHU, t: 'GPT 9r ' });
  try {
    const tok = crypto.createHash('sha256').update(fs.readFileSync(path.join(R9, 'machine-id'), 'utf8').trim() + '9r-cli-auth'
      + fs.readFileSync(path.join(R9, 'auth', 'cli-secret'), 'utf8').trim()).digest('hex').slice(0, 16);
    const get = async u => (await fetch('http://127.0.0.1:20128' + u, { headers: { 'x-9r-cli-token': tok }, signal: AbortSignal.timeout(8000) })).json();
    const p = await get('/api/providers');
    const cs = (p.connections || []).filter(c => c.provider === 'codex' && c.isActive !== false);
    let con = 0, hoi = null, tuan = null;
    for (const c of cs) {
      const u = await get('/api/usage/' + c.id).catch(() => null);
      const s = u && u.quotas && u.quotas.session, w = u && u.quotas && u.quotas.weekly;
      const ws = w && Date.parse(w.resetAt) / 1000 > now ? w.used : 0;
      if (u && !u.limitReached && ws < 100) con++;
      else if (s && u.plan !== 'free') { const r = Date.parse(s.resetAt) / 1000; if (r > now && (!hoi || r < hoi)) hoi = r; }
      if (w && u.plan !== 'free' && (tuan === null || ws < tuan)) tuan = ws; // tuần: tài khoản Plus còn nhiều nhất
    }
    parts.push({ c: con === 0 ? DO : con <= 1 ? CAM : XANH, t: con + '/' + cs.length + ' còn' + (con === 0 && hoi ? ' ↻' + gio(hoi) : '') });
    if (tuan !== null) { parts.push({ c: XAM, t: '·T ' }); parts.push({ c: mau(tuan), t: Math.round(tuan) + '%' }); }
  } catch { parts.push({ c: DO, t: 'tắt' }); }
  const h = docJson('router-het.json'); // ngam.js đang cho worker nghỉ GPT → Sonnet
  if (h && h.den > now) parts.push({ c: CAM, t: ' (nghỉ→Sonnet ↻' + gio(h.den) + ')' });
}

async function gom() {
  const now = Date.now() / 1000, parts = [], SEP = { c: '#5c6370', t: ' │ ' };
  claude(parts, 'Claude hionvn', 'fuel-claude-hionvn.json', 'claude-het-tk2.json', now);
  parts.push(SEP);
  claude(parts, 'vuanh', 'fuel-claude-vuanhtuanfpt.json', 'claude-het-chinh.json', now);
  parts.push(SEP);
  await router9(parts, now);
  parts.push(SEP);
  const g = docJson('grok-het.json');
  parts.push({ c: CHU, t: 'Grok ' }, g && g.den > now ? { c: DO, t: '⛔ ↻' + gio(g.den) } : { c: XANH, t: '✓' });
  for (const c of docJson('fuel-codex.json') || []) { // Lua 07-nhien-lieu.lua ghi; rỗng = không có tài khoản Codex riêng đang có số
    parts.push(SEP, { c: CHU, t: (c.icon || 'Codex') + ' ' }, { c: mau(c.five || 0), t: '5h ' + Math.round(c.five || 0) + '%' });
    if (c.week != null) parts.push({ c: XAM, t: '·T ' }, { c: mau(c.week), t: Math.round(c.week) + '%' });
  }
  parts.push({ c: '#5c6370', t: '  ' + gio(now) + ' ' }); // giờ cập nhật số
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
    if (!j.text.includes('Claude hionvn') || !j.text.includes('GPT 9r') || !j.parts.every(p => /^#[0-9a-f]{6}$/.test(p.c))) {
      console.error('TỰ KIỂM LỖI: thiếu mục hoặc màu sai'); process.exit(1);
    }
    console.log('Tự kiểm OK');
  }).catch(e => { console.error(e); process.exit(1); });
}
