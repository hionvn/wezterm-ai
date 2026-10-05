// Bảng tổng quan đội AI (03/10/2026) — 1 tab "📊 Tổng quan", tự cập nhật mỗi 3 giây.
// Mỗi dòng = 1 ô AI: dự án · vai · ⏳ đang làm / 🔔 cần duyệt / 🟢 rảnh · bao lâu rồi. Bấm vào dòng → nhảy tới ô đó
// (link wezai-o:<số ô>, ~/.wezterm.lua sự kiện open-uri xử lý). Tự hiện bên phải ô Tổng quản khi agent làm việc; Ctrl+Shift+U bật/tắt.
// Đọc: wezterm cli list · sổ đội %LOCALAPPDATA%\wez-ai\doi\*.json · trạng thái wez-ai\state · báo động wez-ai\alerts
//       · hạn mức wez-ai\fuel-claude.json, fuel-codex.json · thứ tự + logo dự án Hion\cay-du-an.json
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const WEZAI = path.join(process.env.LOCALAPPDATA || '', 'wez-ai');
// WEZTERM_EXECUTABLE có thể là wezterm-gui.exe (không có lệnh cli) → luôn dùng wezterm.exe cùng thư mục
const EXE = path.join(path.dirname(process.env.WEZTERM_EXECUTABLE || 'C:\\Program Files\\WezTerm\\wezterm.exe'), 'wezterm.exe');
const HUB = path.resolve(__dirname, '..');
const E = '\x1b';
const R = `${E}[0m`, B = `${E}[1m`, DIM = `${E}[2m`;
const rgb = (hex) => { const m = /^#?(..)(..)(..)$/.exec(hex || '') || [0, '9a', 'a0', 'a6']; return `${E}[38;2;${parseInt(m[1], 16)};${parseInt(m[2], 16)};${parseInt(m[3], 16)}m`; };
const link = (id, text) => `${E}]8;;wezai-o:${id}${E}\\${text}${E}]8;;${E}\\`;
const readJson = (p) => { try { return JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, '')); } catch { return null; } };
// cỡ ô hỏi thẳng console (process.stdout.columns trên Windows có thể cũ khi không nhận được sự kiện resize)
const coO = () => { try { const [c, r] = process.stdout.getWindowSize(); if (c > 0 && r > 0) return [c, r]; } catch {} return [process.stdout.columns || 100, process.stdout.rows || 40]; };
const SPIN = ['◐', '◓', '◑', '◒'];
const ago = (sec) => sec < 60 ? 'vừa xong' : sec < 3600 ? `${Math.floor(sec / 60)} phút` : `${Math.floor(sec / 3600)}h${String(Math.floor((sec % 3600) / 60)).padStart(2, '0')}`;

// Chiều rộng hiển thị gần đúng (emoji tính 2 ô) để canh cột
function width(s) {
  let w = 0;
  for (const ch of s.replace(/\x1b\[[0-9;]*m/g, '').replace(/\x1b\]8;;[^\x1b]*\x1b\\/g, '')) {
    const cp = ch.codePointAt(0);
    if (cp === 0xfe0f || cp === 0x200d) continue;
    w += cp >= 0x1f000 || (cp >= 0x2600 && cp <= 0x27bf) ? 2 : 1;
  }
  return w;
}
const pad = (s, n) => s + ' '.repeat(Math.max(1, n - width(s)));

function shortTitle(t) {
  t = String(t || '');
  const last = /.*\|\s*(.*?)\s*$/.exec(t); if (last) t = last[1];
  const m = /^(\S+)\s+(.*)$/.exec(t); if (m && (SPIN.includes(m[1]) || m[1] === '✳')) t = m[2];
  return t.length > 40 ? t.slice(0, 39) + '…' : t;
}

// ===== Checklist việc đã giao (03/10/2026) =====
// Sổ wez-ai\viec.json do wez.ps1 send / giao ghi. Việc tự ☑ khi ô nhận việc chuyển sang rảnh SAU lúc giao
// (trạng thái wez-ai\state\<ô>.json: Claude ghi qua hooks, Codex do WezTerm đoán từ tiêu đề) → ghi lại "xong" vào sổ.
// Tự đánh dấu tay: wez.ps1 viec xong <số> · bỏ: wez.ps1 viec bo <số>
const hhmm = (t) => new Date(t * 1000).toTimeString().slice(0, 5);
function viecList(now) {
  const file = path.join(WEZAI, 'viec.json');
  let vs = arr(readJson(file));
  let changed = false;
  for (const v of vs) {
    if (v.xong || v.bo) continue;
    const st = readJson(path.join(WEZAI, 'state', String(v.o) + '.json'));
    if (st && st.state === 'idle' && st.t >= v.t + 3) { v.xong = st.t; changed = true; }
  }
  if (changed) { try { fs.writeFileSync(file, JSON.stringify(vs, null, 2)); } catch {} }
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const t0 = Math.floor(today.getTime() / 1000);
  const homNay = vs.filter((v) => v.t >= t0 && !v.bo);
  const chua = vs.filter((v) => !v.xong && !v.bo);
  const xong = homNay.filter((v) => v.xong);
  if (!vs.length) return [`${B}📋 VIỆC ĐÃ GIAO${R} ${DIM}— chưa có (giao bằng wez.ps1 send Chatbot.Engineer "việc" thì hiện ở đây)${R}`, ''];
  const lines = [`${B}📋 VIỆC ĐÃ GIAO${R}  hôm nay ${rgb('#98c379')}${B}${xong.length}/${homNay.length} xong${R}` + (chua.length ? `  ·  ${rgb('#e5c07b')}${chua.length} chưa xong${R}` : '')];
  // chưa xong (mọi ngày) trước, rồi 8 việc xong gần nhất hôm nay; giữ đúng số thứ tự
  const show = [...chua, ...xong.slice(-8)].sort((a, b) => a.so - b.so);
  for (const v of show.slice(-18)) {
    const box = v.xong ? `${rgb('#98c379')}${B}☑${R}` : `${rgb('#e5c07b')}☐${R}`;
    const so = String(v.so).padStart(3);
    const ai = pad(String(v.ai || 'ô ' + v.o).slice(0, 30), 30);
    const viec = String(v.viec || '').slice(0, Math.max(20, coO()[0] - 75));
    const thoi = v.xong ? `${DIM}${hhmm(v.t)} → ${hhmm(v.xong)} (${ago(v.xong - v.t)})${R}` : `${rgb('#e5c07b')}từ ${hhmm(v.t)} · ${ago(now - v.t)}${R}`;
    const text = v.xong ? `${DIM}${viec}${R}` : viec;
    lines.push(' ' + box + ' ' + link(v.o, `${so}. ${ai}${pad(text, 4 + width(viec))}`) + thoi);
  }
  lines.push('');
  return lines;
}

// mảng rỗng có lúc bị ghi thành {} (Lua json_encode) → luôn đổi về mảng
const arr = (x) => Array.isArray(x) ? x : (x && typeof x === 'object' ? Object.values(x) : []);

// vẽ an toàn: lỗi thì in lỗi lên bảng, KHÔNG thoát (thoát → WezTerm mở lại liên tục → nháy, 03/10)
function draw() {
  try { drawRaw(); } catch (e) { const s = '[H[2J📊 Bảng tạm lỗi, thử lại sau 3 giây: ' + String(e && e.message || e).slice(0, 200); if (s !== draw.last) { draw.last = s; process.stdout.write(s); } }
}
function drawRaw() {
  let panes = [];
  // 04/10 (gõ chữ chậm): `wezterm cli list` bắt WezTerm hỏi Windows thư mục của MỌI ô ngay trên luồng giao diện — 49 ô = 1–3 giây
  // mỗi lần, gọi mỗi 3 giây → luồng giao diện bận gần hết. Giờ đọc wez-ai\o-list.json (Lua ghi sẵn trong update-status, ≤ 10 giây/lần);
  // file thiếu / cũ quá 15 giây (WezTerm bản cũ, Lua lỗi) mới gọi cli list.
  // 05/10: file cũ tới 2 phút vẫn dùng — lúc WezTerm đang nghẽn, file không kịp ghi mới mà bảng lại gọi cli list mỗi 3 giây = càng nghẽn thêm.
  const OL = path.join(WEZAI, 'o-list.json');
  try { if (Date.now() - fs.statSync(OL).mtimeMs < 120000) panes = JSON.parse(fs.readFileSync(OL, 'utf8')); } catch { panes = []; }
  if (!panes.length) try { panes = JSON.parse(execFileSync(EXE, ['cli', '--no-auto-start', 'list', '--format', 'json'], { encoding: 'utf8', timeout: 4000 })); } catch { return; }
  const now = Math.floor(Date.now() / 1000);
  const cay = (readJson(path.join(HUB, 'cay-du-an.json')) || {}).cay || [];
  const projInfo = Object.fromEntries(cay.map((n) => [n.ten.toLowerCase(), n]));
  // sổ đội: số ô → vai
  const role = {}, ngu = []; // ngu: worker đang ngủ 💤 (không có ô, tự thức khi được giao việc)
  for (const f of (() => { try { return fs.readdirSync(path.join(WEZAI, 'doi')).filter((x) => x.endsWith('.json')); } catch { return []; } })()) {
    const d = readJson(path.join(WEZAI, 'doi', f)); if (!d) continue;
    const tam = readJson(path.join(WEZAI, 'ai-tam.json')) || {}; // vai Codex đang tạm chạy Claude (tài khoản Codex sắp hết)
    const add = (x, laManager) => { if (x && x.o) role[String(x.o)] = { du_an: d.du_an, icon: x.icon || (laManager ? '🧭' : '•'), vai: x.vai, ten: (x.ten || x.vai) + (tam[`${d.du_an}.${x.vai}`] ? ' ↪Claude' : ''), manager: laManager }; };
    add(d.manager, true); arr(d.worker).forEach((w) => add(w, false));
    arr(d.worker).forEach((w) => { if (w && w.ngu && !w.o) ngu.push({ du_an: d.du_an, vai: w.vai, label: `${w.icon || '•'} ${w.ten || w.vai}`, since: w.ngu_luc ? now - w.ngu_luc : null }); });
  }
  // gom ô theo dự án
  const groups = {}, docs = [];
  const coMat = new Set(ngu.map((z) => `${z.du_an}.${z.vai}`)); // vai đang có ô hoặc đang ngủ
  for (const z of ngu) (groups[z.du_an] = groups[z.du_an] || []).push({ id: '', tabNo: 99, label: z.label, state: 'ngu', since: z.since, manager: false, inTeam: true });
  const tabOrder = [...new Set(panes.map((p) => p.tab_id))];
  for (const p of panes) {
    const t = p.title || '';
    if (/ten-o|📊 Tổng quan/.test(t)) continue;
    const id = String(p.pane_id);
    const tabNo = tabOrder.indexOf(p.tab_id) + 1;
    if (t.includes('📄') || t.includes('Cần duyệt')) { docs.push({ id, tabNo, t: t.replace('📄', '').trim() }); continue; }
    const cwd = decodeURIComponent(String(p.cwd || '').replace(/^file:\/\/\//, '')).replace(/\//g, '\\');
    const proj = (/^E:\\AI\\([^\\]+)/i.exec(cwd) || [])[1] || 'Khác';
    const r = role[id];
    const isCodex = /codex|Ready|Working/i.test(t) && /\|/.test(t);
    const isClaude = SPIN.some((s) => t.startsWith(s)) || t.startsWith('✳');
    if (!isCodex && !isClaude && !r) continue; // ô PowerShell trống: bỏ
    const alert = readJson(path.join(WEZAI, 'alerts', id + '.json'));
    const st = readJson(path.join(WEZAI, 'state', id + '.json'));
    let state = 'idle';
    // 04/10: chỉ XIN QUYỀN mới là 🔔 (state 'need'); Claude rảnh lâu tự báo "đang chờ nhập" → vẫn là rảnh, không phải chờ duyệt
    if (alert && alert.kind === 'need' && (!st || st.state === 'need' || st.ai !== 'claude')) state = 'need';
    else if (SPIN.some((s) => t.startsWith(s)) || /Working/.test(t)) state = 'work';
    const since = st && st.t ? now - st.t : null;
    const label = r ? `${r.icon} ${r.ten}` : `🔹 ${shortTitle(t)}`;
    if (r) coMat.add(`${r.du_an}.${r.vai}`);
    (groups[proj] = groups[proj] || []).push({ id, tabNo, label, state, since, manager: r && r.manager, inTeam: !!r });
  }
  // 04/10 tối (người dùng: "còn nhiều dự án nữa mà?"): liệt kê ĐỦ mọi agent đã định nghĩa trong Hiondoi*.json —
  // vai không có ô và không ngủ (đội chưa mở / đã đóng) hiện ⚫ tắt, để bảng luôn thấy toàn bộ đội của mọi dự án.
  for (const f of (() => { try { return fs.readdirSync(path.join(HUB, 'doi')).filter((x) => x.endsWith('.json')); } catch { return []; } })()) {
    const d = readJson(path.join(HUB, 'doi', f)); if (!d || !d.du_an) continue;
    const them = (x, laManager) => { if (!x || coMat.has(`${d.du_an}.${x.vai || 'Manager'}`)) return;
      (groups[d.du_an] = groups[d.du_an] || []).push({ id: '', tabNo: 100, label: `${x.icon || (laManager ? '🧭' : '•')} ${x.ten || x.vai || 'Manager'}`, state: 'tat', since: null, manager: laManager, inTeam: true }); };
    them(d.manager, true); arr(d.worker).forEach((w) => them(w, false));
  }
  // vẽ
  const [cols, rows] = coO();
  const out = [];
  viecList(now); // 04/10: KHÔNG hiện checklist nữa (Hion: bảng chỉ để danh sách agent) — vẫn chạy để tự ☑ việc xong trong viec.json (eval, Brain dùng)
  const fc = readJson(path.join(WEZAI, 'fuel-claude.json'));
  let fx = readJson(path.join(WEZAI, 'fuel-codex.json'));
  if (!Array.isArray(fx)) fx = []; // Lua ghi bảng rỗng thành {} (06/10: "fx is not iterable")
  const pc = (v) => (v == null ? '?' : `${Math.round(v)}%`);
  const col = (v) => rgb(v >= 80 ? '#e06c75' : v >= 50 ? '#e5c07b' : '#98c379');
  let fuel = fc ? `⛽ Claude ${col(fc.five || 0)}5h ${pc(fc.five)}${R} · tuần ${pc(fc.week)}` : '⛽ Claude ?';
  for (const c of fx) fuel += `   ${c.icon || '🧩'} ${col(c.five || 0)}5h ${pc(c.five)}${R}`;
  const time = new Date().toTimeString().slice(0, 5);
  out.push(`${B} 📊 TỔNG QUAN ĐỘI AI${R} ${DIM}· ${time}${R}    ${fuel}`);
  out.push(DIM + '─'.repeat(Math.min(cols - 1, 110)) + R);
  // 04/10: chỉ danh sách agent, dòng gọn (vai · trạng thái · bao lâu; bấm để nhảy tới ô). Mỗi dự án 1 khối;
  // không đủ chiều cao mà đủ chiều ngang → chia 2 cột (khối nào nằm trọn 1 cột).
  const W = 44; // bề rộng 1 cột
  const cat = (s, n) => { let o = '', w = 0; for (const ch of s) { const cw = width(ch); if (w + cw > n) return o + '…'; o += ch; w += cw; } return o; };
  const blocks = [];
  const order = [...cay.map((n) => n.ten), ...Object.keys(groups).filter((k) => !projInfo[k.toLowerCase()])];
  let total = { work: 0, need: 0, idle: 0, ngu: 0, tat: 0 };
  for (const name of order) {
    const g = groups[name]; if (!g) continue;
    const info = projInfo[name.toLowerCase()] || {};
    const c = rgb(info.mau || '#9aa0a6');
    const n = { work: 0, need: 0, ngu: 0, tat: 0 }; g.forEach((x) => { if (x.state !== 'idle') n[x.state]++; total[x.state]++; });
    const b = [`${c}${B}${info.logo || '📁'} ${name.toUpperCase()}${R}` + (n.work ? `  ⏳${n.work}` : '') + (n.need ? `  🔔${n.need}` : '')];
    g.sort((a, b) => (b.manager - a.manager) || (b.inTeam - a.inTeam) || (a.tabNo - b.tabNo));
    for (const x of g) {
      const ten = pad(cat(x.label, 24), 26);
      const t = x.since != null ? ago(x.since) : '';
      if (x.state === 'tat') { b.push(' ' + `${DIM}${ten}${pad('⚫ tắt', 9)}${R}`); continue; } // đội chưa mở: wez.ps1 doi <dự án>
      if (x.state === 'ngu') { b.push(' ' + `${DIM}${ten}${pad('💤 ngủ', 9)}${t}${R}`); continue; } // không có ô để nhảy
      const s = x.state === 'need' ? `${rgb('#e06c75')}${B}🔔 chờ${R}` : x.state === 'work' ? `${rgb('#e5c07b')}⏳ làm${R}` : `${rgb('#98c379')}🟢 rảnh${R}`;
      b.push(' ' + link(x.id, ten + pad(s, 9) + `${DIM}${t}${R}`));
    }
    blocks.push(b);
  }
  if (docs.length) blocks.push([`${B}📄 TÀI LIỆU${R}`, ...docs.map((d) => ' ' + link(d.id, cat(d.t, W - 3)))]);
  const tong = blocks.reduce((s, b) => s + b.length, 0);
  if (tong > rows - 5 && cols >= W * 2 + 3 && blocks.length > 1) {
    // 2 cột: dồn khối theo thứ tự vào cột trái tới khi ≥ nửa tổng số dòng, phần còn lại sang phải
    const trai = [], phai = []; let n = 0;
    for (const b of blocks) { (n < tong / 2 ? trai : phai).push(...b); if (n < tong / 2) n += b.length; }
    for (let i = 0; i < Math.max(trai.length, phai.length); i++) out.push(pad(trai[i] || '', W + 2) + (phai[i] || ''));
  } else for (const b of blocks) out.push(...b);
  out.push(DIM + '─'.repeat(Math.min(cols - 1, 110)) + R);
  out.push(`${DIM}Tổng: ⏳ ${total.work} đang làm · 🔔 ${total.need} chờ bạn · 🟢 ${total.idle} rảnh · 💤 ${total.ngu} ngủ · ⚫ ${total.tat} tắt   ·   Bấm vào dòng để nhảy tới ô · Ctrl+Shift+U bật/tắt bảng${R}`);
  const s = out.join('\n');
  if (s !== draw.last) { draw.last = s; process.stdout.write(`${E}[H${E}[2J${s}\n`); }
}

process.stdout.write(`${E}]0;📊 Tổng quan${'\x07'}${E}[?25l`); // tiêu đề ô (WezTerm nhận ra), ẩn con trỏ
// 06/10: kéo đường chia ô → bảng trắng trơn tới khi số liệu đổi. ConPTY xoá/vẽ lại màn hình khi đổi cỡ, còn
// sự kiện 'resize' của Node trên Windows không đáng tin → tự hỏi cỡ ô mỗi 0,4 giây (getWindowSize hỏi thẳng
// console, rẻ); đổi cỡ thì đợi kéo xong 0,25 giây rồi vẽ lại bắt buộc. Thêm 30 giây vẽ lại 1 lần cho chắc.
const veLai = () => { draw.last = ''; draw(); };
let co = '', hen = null;
const kiemCo = () => {
  let c = ''; try { c = process.stdout.getWindowSize().join('x'); } catch { return; }
  if (c === co) return;
  co = c; clearTimeout(hen); hen = setTimeout(veLai, 250);
};
process.stdout.on('resize', kiemCo);
// Node trên Windows chỉ biết ô đổi cỡ khi ĐANG ĐỌC bàn phím (sự kiện đổi cỡ đi chung đường với phím) → đọc phím thô,
// bỏ qua phím thường; Ctrl+C vẫn thoát như cũ. Đo 06/10: không đọc phím thì cỡ ô kẹt ở cỡ lúc mở.
try { process.stdin.setRawMode(true); process.stdin.resume(); process.stdin.on('data', (d) => { if (d.includes(3)) process.exit(0); }); } catch {}
draw();
setInterval(kiemCo, 400);
setInterval(draw, 3000);
setInterval(veLai, 30000);

// không bao giờ thoát vì lỗi lạ (thoát → ô đóng → WezTerm mở lại → nháy)
process.on('uncaughtException', (e) => { try { process.stdout.write('[H[2J📊 Bảng tạm lỗi: ' + String(e && e.message || e).slice(0, 200)); } catch {} });
