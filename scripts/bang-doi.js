// Bảng tổng quan đội AI (03/10/2026) — 1 tab "📊 Tổng quan", tự cập nhật mỗi 3 giây.
// Mỗi dòng = 1 ô AI: dự án · vai · ⏳ đang làm / 🔔 cần duyệt / 🟢 rảnh · bao lâu rồi. Bấm vào dòng → nhảy tới ô đó
// (link wezai-o:<số ô>, ~/.wezterm.lua sự kiện open-uri xử lý). Mở / quay lại: Ctrl+Shift+U.
// Đọc: wezterm cli list · sổ đội %LOCALAPPDATA%\wez-ai\doi\*.json · trạng thái wez-ai\state · báo động wez-ai\alerts
//       · hạn mức wez-ai\fuel-claude.json, fuel-codex.json · thứ tự + logo dự án Hion\cay-du-an.json
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const WEZAI = path.join(process.env.LOCALAPPDATA || '', 'wez-ai');
const EXE = process.env.WEZTERM_EXECUTABLE || 'C:\\Program Files\\WezTerm\\wezterm.exe';
const HUB = path.resolve(__dirname, '..');
const E = '\x1b';
const R = `${E}[0m`, B = `${E}[1m`, DIM = `${E}[2m`;
const rgb = (hex) => { const m = /^#?(..)(..)(..)$/.exec(hex || '') || [0, '9a', 'a0', 'a6']; return `${E}[38;2;${parseInt(m[1], 16)};${parseInt(m[2], 16)};${parseInt(m[3], 16)}m`; };
const link = (id, text) => `${E}]8;;wezai-o:${id}${E}\\${text}${E}]8;;${E}\\`;
const readJson = (p) => { try { return JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, '')); } catch { return null; } };
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

function draw() {
  let panes = [];
  try { panes = JSON.parse(execFileSync(EXE, ['cli', '--no-auto-start', 'list', '--format', 'json'], { encoding: 'utf8', timeout: 4000 })); } catch { return; }
  const now = Math.floor(Date.now() / 1000);
  const cay = (readJson(path.join(HUB, 'cay-du-an.json')) || {}).cay || [];
  const projInfo = Object.fromEntries(cay.map((n) => [n.ten.toLowerCase(), n]));
  // sổ đội: số ô → vai
  const role = {};
  for (const f of (() => { try { return fs.readdirSync(path.join(WEZAI, 'doi')).filter((x) => x.endsWith('.json')); } catch { return []; } })()) {
    const d = readJson(path.join(WEZAI, 'doi', f)); if (!d) continue;
    const add = (x, laManager) => { if (x && x.o) role[String(x.o)] = { du_an: d.du_an, icon: x.icon || (laManager ? '🧭' : '•'), ten: x.ten || x.vai, manager: laManager }; };
    add(d.manager, true); (d.worker || []).forEach((w) => add(w, false));
  }
  // gom ô theo dự án
  const groups = {}, docs = [];
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
    if (alert && alert.kind === 'need') state = 'need';
    else if (SPIN.some((s) => t.startsWith(s)) || /Working/.test(t)) state = 'work';
    const since = st && st.t ? now - st.t : null;
    const label = r ? `${r.icon} ${r.ten}` : `🔹 ${shortTitle(t)}`;
    (groups[proj] = groups[proj] || []).push({ id, tabNo, label, state, since, manager: r && r.manager, inTeam: !!r });
  }
  // vẽ
  const cols = process.stdout.columns || 100;
  const out = [];
  const fc = readJson(path.join(WEZAI, 'fuel-claude.json'));
  const fx = readJson(path.join(WEZAI, 'fuel-codex.json')) || [];
  const pc = (v) => (v == null ? '?' : `${Math.round(v)}%`);
  const col = (v) => rgb(v >= 80 ? '#e06c75' : v >= 50 ? '#e5c07b' : '#98c379');
  let fuel = fc ? `⛽ Claude ${col(fc.five || 0)}5h ${pc(fc.five)}${R} · tuần ${pc(fc.week)}` : '⛽ Claude ?';
  for (const c of fx) fuel += `   ${c.icon || '🧩'} ${col(c.five || 0)}5h ${pc(c.five)}${R}`;
  const time = new Date().toTimeString().slice(0, 5);
  out.push(`${B} 📊 TỔNG QUAN ĐỘI AI${R} ${DIM}· ${time}${R}    ${fuel}`);
  out.push(DIM + '─'.repeat(Math.min(cols - 1, 110)) + R);
  const order = [...cay.map((n) => n.ten), ...Object.keys(groups).filter((k) => !projInfo[k.toLowerCase()])];
  let total = { work: 0, need: 0, idle: 0 };
  for (const name of order) {
    const g = groups[name]; if (!g) continue;
    const info = projInfo[name.toLowerCase()] || {};
    const c = rgb(info.mau || '#9aa0a6');
    const n = { work: 0, need: 0 }; g.forEach((x) => { if (x.state !== 'idle') n[x.state]++; total[x.state]++; });
    const head = `${c}${B}${info.logo || '📁'} ${name.toUpperCase()}${R}` + (n.work ? `  ⏳${n.work}` : '') + (n.need ? `  🔔${n.need}` : '');
    out.push(head);
    g.sort((a, b) => (b.manager - a.manager) || (b.inTeam - a.inTeam) || (a.tabNo - b.tabNo));
    for (const x of g) {
      const s = x.state === 'need' ? `${rgb('#e06c75')}${B}🔔 chờ bạn${R}` : x.state === 'work' ? `${rgb('#e5c07b')}⏳ đang làm${R}` : `${rgb('#98c379')}🟢 rảnh${R}`;
      const t = x.since != null ? `${DIM}${ago(x.since)}${R}` : '';
      out.push('   ' + link(x.id, pad(x.label, 34) + pad(s, 16) + pad(t, 12) + `${DIM}tab ${x.tabNo} · ô ${x.id}${R}`));
    }
  }
  if (docs.length) {
    out.push(`${B}📄 TÀI LIỆU ĐANG MỞ${R}`);
    for (const d of docs) out.push('   ' + link(d.id, pad(d.t.slice(0, 50), 54) + `${DIM}tab ${d.tabNo} · ô ${d.id}${R}`));
  }
  out.push(DIM + '─'.repeat(Math.min(cols - 1, 110)) + R);
  out.push(`${DIM}Tổng: ⏳ ${total.work} đang làm · 🔔 ${total.need} chờ bạn · 🟢 ${total.idle} rảnh   ·   Bấm vào dòng để nhảy tới ô · Ctrl+Shift+U quay lại bảng này${R}`);
  const s = out.join('\n');
  if (s !== draw.last) { draw.last = s; process.stdout.write(`${E}[H${E}[2J${s}\n`); }
}

process.stdout.write(`${E}]0;📊 Tổng quan${'\x07'}${E}[?25l`); // tiêu đề ô (WezTerm nhận ra), ẩn con trỏ
process.stdout.on('resize', () => { draw.last = ''; draw(); });
draw();
setInterval(draw, 3000);
