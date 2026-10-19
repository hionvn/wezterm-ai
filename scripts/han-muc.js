// Hạn mức mọi gói AI cho góc PHẢI thanh tab WezTerm (19/10; nhãn ▶ ĐANG DÙNG / ⏸ CHỜ / ⛔ HẾT, chữ rút gọn cho khỏi chiếm chỗ tab) (19/10/2026, người dùng yêu cầu).
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

// Số liệu 1 tài khoản Claude. 19/10: nguồn chính = API hạn mức của chính tài khoản (api.anthropic.com/api/oauth/usage,
// token đọc từ <thư mục>\.credentials.json — KHÔNG in / ghi token ở đâu, KHÔNG tự làm mới token), tối đa 1 lần / 5 phút;
// lỗi → giữ số lần trước (tô xám); chưa có lần nào → dự phòng file statusline (fuel-claude-<tk>.json).
const OAUTH = {}; // [thư mục] = { at, five, five_reset, week, week_reset, loi }
async function oauthUsage(dir, now) {
  const m = OAUTH[dir] || (OAUTH[dir] = {});
  if (m.at && now - m.at < 300) return m;
  m.at = now;
  try {
    const c = JSON.parse(fs.readFileSync(path.join(process.env.USERPROFILE || '', dir, '.credentials.json'), 'utf8')).claudeAiOauth || {};
    if (!c.accessToken) throw new Error('chưa đăng nhập');
    if (c.expiresAt && c.expiresAt < Date.now()) throw new Error('token hết hạn');
    const r = await fetch('https://api.anthropic.com/api/oauth/usage', {
      headers: { Authorization: 'Bearer ' + c.accessToken, 'anthropic-beta': 'oauth-2025-04-20' }, signal: AbortSignal.timeout(10000) });
    if (!r.ok) throw new Error('lỗi ' + r.status);
    const u = await r.json(), f = u.five_hour || {}, w = u.seven_day || {};
    Object.assign(m, { five: f.utilization, five_reset: Date.parse(f.resets_at) / 1000 || 0, week: w.utilization,
      week_reset: Date.parse(w.resets_at) / 1000 || 0, t: now, loi: '' });
  } catch (e) { m.loi = String(e.message || e).slice(0, 30); }
  return m;
}
async function soClaude(dir, file, hetFile, now) {
  const het = docJson(hetFile);
  if (het && het.den > now) return { het: het.den };
  const o = await oauthUsage(dir, now);
  const c = o.t ? o : docJson(file);
  if (!c) return { loi: o.loi };
  const five = c.five_reset && c.five_reset < now ? 0 : Math.round(c.five || 0);
  const week = c.week_reset && c.week_reset < now ? 0 : Math.round(c.week || 0);
  return { five, week, cu: !!o.loi || now - (c.t || 0) > 3600, het: five >= 100 ? c.five_reset : week >= 100 ? c.week_reset : 0,
    hoi: c.five_reset };
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

// Codex tài khoản riêng (19/10: chuyển từ Lua 07-nhien-lieu.lua sang đây — wezterm.glob + đọc file phiên trong Lua làm lượt
// update-status mất 260–7500 ms). Logic giữ y như Lua: ngày gần nhất (≤ 7 ngày) có phiên, 30 phiên cuối, bỏ phiên 9router,
// lấy khung có giờ làm mới muộn nhất, trong khung lấy % cao nhất. Ghi fuel-codex.json (bang-doi.js, wez.ps1, Lua codex_warn đọc).
const CX_FILE = {}; // [file] = { size, p5, r5, pw, rw }
const CX_ROW = {};  // [số tk] = row cũ (phiên mới chưa có số → giữ số cũ)
function codexRows(now) {
  let bang = null; try { bang = JSON.parse(fs.readFileSync(path.join(process.env.USERPROFILE || '', '.codex-tai-khoan.json'), 'utf8')); } catch {}
  const tks = (bang && bang.taiKhoan) || [{ so: 0, ten: 'Codex', thuMuc: path.join(process.env.USERPROFILE || '', '.codex') }];
  const rows = [];
  for (const tk of tks) {
    let files = [];
    for (let d = 0; d <= 6 && !files.length; d++) {
      const t = new Date((now - d * 86400) * 1000);
      const dir = path.join(tk.thuMuc || '', 'sessions', String(t.getFullYear()), String(t.getMonth() + 1).padStart(2, '0'), String(t.getDate()).padStart(2, '0'));
      try { files = fs.readdirSync(dir).filter(f => f.endsWith('.jsonl')).sort().map(f => path.join(dir, f)); } catch {}
    }
    let s = null;
    for (const f of files.slice(-30)) {
      let sz = 0; try { sz = fs.statSync(f).size; } catch { continue; }
      let c = CX_FILE[f];
      if (!c || c.size !== sz) {
        c = CX_FILE[f] = { size: sz };
        try {
          const fd = fs.openSync(f, 'r'), head = Buffer.alloc(Math.min(4096, sz));
          fs.readSync(fd, head, 0, head.length, 0);
          if (!head.toString('utf8').includes('"model_provider":"nine_router"')) {
            const n = Math.min(98304, sz), b = Buffer.alloc(n);
            fs.readSync(fd, b, 0, n, sz - n);
            const t = b.toString('utf8');
            for (const m of t.matchAll(/"primary":\{"used_percent":([\d.]+),"window_minutes":\d+,"resets_at":(\d+)\}/g)) {
              const u = +m[1], r = +m[2]; if (!c.r5 || r > c.r5 || (r === c.r5 && u > c.p5)) { c.p5 = u; c.r5 = r; } }
            for (const m of t.matchAll(/"secondary":\{"used_percent":([\d.]+),"window_minutes":\d+,"resets_at":(\d+)\}/g)) {
              const u = +m[1], r = +m[2]; if (!c.rw || r > c.rw || (r === c.rw && u > c.pw)) { c.pw = u; c.rw = r; } }
          }
          fs.closeSync(fd);
        } catch {}
      }
      if (c.r5 && (!s || c.r5 > s.r5 || (c.r5 === s.r5 && c.p5 > s.p5))) { s = s || {}; s.p5 = c.p5; s.r5 = c.r5; }
      if (s && c.rw && (!s.rw || c.rw > s.rw || (c.rw === s.rw && c.pw > s.pw))) { s.pw = c.pw; s.rw = c.rw; }
    }
    if (s) {
      const du_an = Object.entries((bang && bang.duAn) || {}).filter(([, v]) => v === tk.so).map(([k]) => k).join(', ');
      CX_ROW[tk.so || 0] = { so: tk.so, ten: tk.ten || 'Codex', icon: (tk.ten || 'Codex').split(/\s/)[0], du_an,
        five_raw: s.p5, five_reset: s.r5, week_raw: s.pw, week_reset: s.rw };
    }
    if (CX_ROW[tk.so || 0]) rows.push(CX_ROW[tk.so || 0]);
  }
  // đã qua giờ làm mới → 0 (06/10: số cũ 100% làm wez.ps1 tưởng Codex vẫn hết)
  const out = rows.map(r => ({ ...r, five: r.five_reset && r.five_reset < now ? 0 : r.five_raw, week: r.week_reset && r.week_reset < now ? 0 : r.week_raw }));
  fs.writeFileSync(path.join(AIDIR, 'fuel-codex.json'), JSON.stringify(out));
  return out;
}

// Thứ tự worker giống ngam.js (thuTu + claudeTk, 19/10): Grok → GPT 9router → Claude vuanhtuanfpt → Claude hionvn.
// Gói đầu tiên chưa hết = ▶ ĐANG DÙNG, gói sau còn hạn mức = ⏸ CHỜ, gói hết = ⛔ HẾT ↻giờ hồi. hionvn luôn chạy ô Tổng quản.
async function gom() {
  const now = Date.now() / 1000, parts = [], SEP = { c: '#5c6370', t: ' │ ' }, chay = demChay();
  const g = docJson('grok-het.json'), rh = docJson('router-het.json');
  const goi = [];
  goi.push({ ten: 'Grok', het: !fs.existsSync(GROK_EXE) ? -1 : g && g.den > now ? g.den : 0, n: chay.grok });
  let r9 = null; try { r9 = await so9r(now); } catch {}
  goi.push({ ten: 'GPT9r', het: rh && rh.den > now ? rh.den : !r9 ? -1 : r9.con === 0 ? (r9.hoi || -1) : 0, n: chay.codex,
    them: r9 ? r9.con + '/' + r9.tong + (r9.tuan !== null ? ' · T' + Math.round(r9.tuan) + '%' : '') : '9router tắt' });
  for (const [ten, dir, f, h] of [['vuanh', '.claude', 'fuel-claude-vuanhtuanfpt.json', 'claude-het-chinh.json'],
    ['hionvn', '.claude-tk2', 'fuel-claude-hionvn.json', 'claude-het-tk2.json']]) {
    const c = await soClaude(dir, f, h, now);
    goi.push({ ten, het: c.het || 0, cu: c.cu, pct: Math.max(c.five || 0, c.week || 0),
      them: c.five == null ? '? ' + (c.loi || 'chưa có số') : '5h' + c.five + '%' + (c.five >= 85 && c.hoi ? '↻' + gio(c.hoi) : '') + ' T' + c.week + '%' });
  }
  goi[3].tq = true;
  const dangDung = goi.findIndex(x => x.het === 0); // -1 = mọi gói hết
  // worker Claude chạy ngầm tính cho tài khoản claudeTk đang chọn (vuanh, hết thì hionvn)
  (goi[2].het === 0 ? goi[2] : goi[3]).n = chay.claude;
  goi.forEach((x, i) => {
    if (i) parts.push(SEP);
    parts.push({ c: CHU, t: x.ten + ' ' });
    if (x.het > 0 || x.het === -1) {
      parts.push({ c: DO, t: (x.het === -1 ? '⛔' : '⛔↻' + gio(x.het)) }); // ⛔ HẾT ↻giờ hồi
    } else if (i === dangDung || x.n > 0 || x.tq) {
      // ▶ ĐANG DÙNG: 18w = 18 worker ngầm đang chạy, TQ = ô Tổng quản
      parts.push({ c: x.pct >= 85 ? CAM : XANH, t: '▶' + [x.n ? x.n + 'w' : '', x.tq ? 'TQ' : ''].filter(Boolean).join('+') });
    } else parts.push({ c: XAM, t: '⏸' }); // ⏸ CHỜ: còn lượt, chưa tới lượt
    if (x.them) parts.push({ c: x.cu ? XAM : x.pct >= 85 ? CAM : XAM, t: ' ' + x.them });
  });
  for (const c of codexRows(now)) // Codex tài khoản riêng, chỉ ô dùng
    parts.push(SEP, { c: CHU, t: (c.icon || 'Codex') + ' ' }, { c: mau(c.five || 0), t: '5h' + Math.round(c.five || 0) + '%' + (c.week != null ? ' T' + Math.round(c.week) + '%' : '') });
  parts.push({ c: '#5c6370', t: ' ' + gio(now) + ' ' }); // giờ lấy số
  const text = parts.map(p => p.t).join('');
  fs.mkdirSync(AIDIR, { recursive: true });
  fs.writeFileSync(path.join(AIDIR, 'han-muc.json.tmp'), JSON.stringify({ t: Math.floor(now), text, parts }));
  fs.renameSync(path.join(AIDIR, 'han-muc.json.tmp'), path.join(AIDIR, 'han-muc.json')); // Lua không đọc phải file ghi dở
  fs.writeFileSync(path.join(AIDIR, 'han-muc.txt'), text + '\n');
  return text;
}

if (process.argv[2] === 'chay') {
  // CHỈ 1 BẢN (19/10: từng có 3 bản chạy cùng lúc — pid trong file bị bản sau ghi đè, bản trước không biết).
  // han-muc.pid = "pid bản" (bản = giờ sửa han-muc.js). Đang có bản sống cùng code → thoát. Khác code (vừa sửa) → giành lấy;
  // mỗi vòng bản nào thấy pid trong file không phải mình thì tự thoát → tối đa 60 giây là còn đúng 1 bản.
  const PID = path.join(AIDIR, 'han-muc.pid'), BAN = String(Math.floor(fs.statSync(__filename).mtimeMs));
  const doc = () => { try { return fs.readFileSync(PID, 'utf8').trim().split(' '); } catch { return []; } };
  const [p0, b0] = doc();
  let song = false; try { song = !!p0 && +p0 !== process.pid && process.kill(+p0, 0); } catch {}
  if (song && b0 === BAN) process.exit(0);
  fs.writeFileSync(PID, process.pid + ' ' + BAN);
  const vong = () => {
    if (doc()[0] !== String(process.pid)) process.exit(0); // có bản khác giành → mình thoát
    gom().catch(() => {}).finally(() => setTimeout(vong, 60000));
  };
  vong();
} else {
  gom().then(t => {
    console.log(t);
    const j = JSON.parse(fs.readFileSync(path.join(AIDIR, 'han-muc.json'), 'utf8'));
    if (!j.text.includes('hionvn') || !j.text.includes('GPT9r') || !j.text.includes('▶') || !j.parts.every(p => /^#[0-9a-f]{6}$/.test(p.c))) {
      console.error('TỰ KIỂM LỖI: thiếu mục hoặc màu sai'); process.exit(1);
    }
    console.log('Tự kiểm OK');
  }).catch(e => { console.error(e); process.exit(1); });
}
