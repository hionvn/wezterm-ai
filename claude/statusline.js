// Dòng trạng thái Claude Code
//   Dòng 1: dự án (màu riêng) › thư mục con, model, mức suy nghĩ, tên phiên, git (nhánh, file sửa, commit chưa push, stash)
//   Dòng 2: context, hạn mức 5 giờ / 7 ngày (+ giờ reset, dự báo hết), số dòng sửa, thời gian phiên, cache còn ấm, giờ
//   Dòng 3: chỉ hiện khi có cảnh báo (AGENTS.md vừa bị sửa, lâu chưa commit, cache nguội)
// Bản cũ: statusline.js.bak-2026-10-01b
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

let input = '';
process.stdin.on('data', (c) => (input += c));
process.stdin.on('end', () => {
  let data = {};
  try { data = JSON.parse(input.replace(/^﻿/, '')); } catch {}

  const R = '\x1b[0m', dim = '\x1b[2m', bold = '\x1b[1m';
  const yellow = '\x1b[1;33m', cyan = '\x1b[36m', green = '\x1b[32m', red = '\x1b[1;31m',
    magenta = '\x1b[35m', blue = '\x1b[1;34m', orange = '\x1b[38;5;208m';
  const color = (p) => (p >= 80 ? red : p >= 50 ? yellow : green);
  const now = Date.now() / 1000;
  const pad = (n) => String(n).padStart(2, '0');
  const hhmm = (sec) => { const d = new Date(sec * 1000); return pad(d.getHours()) + ':' + pad(d.getMinutes()); };
  const weekday = (sec) => ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'][new Date(sec * 1000).getDay()];
  const kilo = (n) => (n >= 1e6 ? (n / 1e6).toFixed(1).replace(/\.0$/, '') + 'M' : Math.round(n / 1000) + 'k');
  const dur = (sec) => {
    sec = Math.max(0, Math.round(sec));
    const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60);
    if (h >= 24) return `${Math.floor(h / 24)} ngày${h % 24 ? ' ' + (h % 24) + 'h' : ''}`;
    return h ? `${h}h${m ? pad(m) : ''}` : `${m}m`;
  };

  // ---- Dự án & thư mục ----
  const ws = data.workspace || {};
  const dir = ws.current_dir || data.cwd || process.cwd();
  const projDir = ws.project_dir || dir;
  const project = projDir.replace(/[\\/]+$/, '').split(/[\\/]/).pop();
  const projColors = { hion: yellow, sino: red, coolguy: blue, chatbot: magenta };
  const palette = [cyan, green, orange, magenta, blue];
  let pc = projColors[project.toLowerCase()];
  if (!pc) { let h = 0; for (const ch of project) h = (h * 31 + ch.charCodeAt(0)) >>> 0; pc = palette[h % palette.length]; }
  // Màu + logo riêng từng dự án lấy từ Hion\cay-du-an.json (trường "mau", "logo") — giống tab WezTerm
  let logo = '📁';
  try {
    const cay = JSON.parse(fs.readFileSync(path.join(projDir, '..', 'Hion', 'cay-du-an.json'), 'utf8').replace(/^﻿/, '')).cay || [];
    const it = cay.find((n) => String(n.ten).toLowerCase() === project.toLowerCase());
    const m = it && /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(it.mau || '');
    if (m) pc = `[1;38;2;${parseInt(m[1], 16)};${parseInt(m[2], 16)};${parseInt(m[3], 16)}m`;
    if (it && it.logo) logo = it.logo;
  } catch {}
  // Nhãn chức vụ theo sơ đồ tổ chức: Hion = Chief of Staff, thư mục dự án = Manager dự án đó;
  // ô có tên trong sổ đội (%LOCALAPPDATA%\wez-ai\doi\<dự án>.json) là worker → "⚙️ ENGINEER ← MANAGER ô 24"
  let role = project.toLowerCase() === 'hion' ? '👑 TỔNG QUẢN' : `🧭 MANAGER ${project.toUpperCase()}`;
  let isWorker = false; // worker trong đội → thanh trạng thái 1 dòng (ô lưới 2×2 thấp, đỡ mất chỗ)
  try {
    const pane = String(process.env.WEZTERM_PANE || '');
    const doi = JSON.parse(fs.readFileSync(path.join(process.env.LOCALAPPDATA || '', 'wez-ai', 'doi', project + '.json'), 'utf8').replace(/^﻿/, ''));
    const ws = Array.isArray(doi.worker) ? doi.worker : (doi.worker && doi.worker.vai ? [doi.worker] : []); // 04/10: đội không worker có lúc ghi {} thay vì []
    const w = pane && ws.find((x) => String(x.o) === pane);
    if (w) { role = `${w.icon} ${(w.ten || w.vai).toUpperCase()}${R}${dim} ← 🧭 Manager ${doi.manager ? 'ô ' + doi.manager.o : '(chưa có)'}${R}${pc}${bold}`; isWorker = true; }
    // 03/10: dự án đã có đội mà ô này không phải Manager / worker (vd phiên review, phiên mở thêm) → không gắn nhãn Manager
    // 04/10: sau khởi động lại sổ có thể còn số ô Manager cũ (Hion ghi ô 4 trong khi Tổng quản là ô 0) → Manager là Claude
    // mà ô đó không còn file trạng thái (wez-ai\state\<ô>.json, hook Claude ghi) thì coi như ô chết, không gắn "phiên phụ"
    else if (pane && doi.manager && String(doi.manager.o) !== pane) {
      const chet = doi.manager.ai === 'claude' && !fs.existsSync(path.join(process.env.LOCALAPPDATA || '', 'wez-ai', 'state', String(doi.manager.o) + '.json'));
      if (!chet) role = `🔹 PHIÊN PHỤ ${project.toUpperCase()}`;
    }
  } catch {}
  let where = `${pc}${bold}${role}${R}  ${logo} ${pc}${bold}${project}${R}`;
  const rel = path.relative(projDir, dir);
  if (rel && !rel.startsWith('..') && !path.isAbsolute(rel)) where += `${dim} › ${rel.replace(/\\/g, '/')}${R}`;

  // Fast: data.fast_mode = lượt vừa rồi chạy nhanh thật; settings.json "fastMode" = anh đã bật bằng /fast.
  // Bật mà Claude chưa chạy nhanh (chưa có lượt mới, hoặc tạm hết lượt fast) → hiện mờ "⚡ fast chờ".
  const fastLabel = () => {
    if (data.fast_mode) return ` ${orange}${bold}⚡ FAST${R}`;
    let on = false;
    try { on = JSON.parse(fs.readFileSync(path.join(require('os').homedir(), '.claude', 'settings.json'), 'utf8')).fastMode === true; } catch {}
    return on ? ` ${dim}${orange}⚡ fast chờ${R}` : '';
  };
  const line1 = [where];
  const model = (data.model && data.model.display_name) || '?';
  line1.push(`🤖 ${cyan}${model}${R}` + fastLabel());
  if (data.effort && data.effort.level) line1.push(`💭 ${magenta}${data.effort.level}${R}`);
  if (data.session_name) line1.push(`💬 ${dim}${data.session_name}${R}`);
  if (data.output_style && data.output_style.name && data.output_style.name !== 'default') {
    line1.push(`🎨 ${data.output_style.name}`);
  }

  // ---- Git (vài lệnh nhẹ, mỗi lệnh tối đa 1,5 giây) ----
  const alerts = [];
  // 03/10: nhớ kết quả git 8 giây / thư mục (file trong wez-ai\git-nho\) — 9 ô Claude × 4 lệnh git mỗi lần vẽ làm máy chậm
  const gitRaw = (args) => execFileSync('git', ['-C', dir, ...args], { encoding: 'utf8', timeout: 1500, stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  const memoDir = path.join(process.env.LOCALAPPDATA || '', 'wez-ai', 'git-nho');
  const memoFile = path.join(memoDir, dir.replace(/[^A-Za-z0-9]+/g, '_') + '.json');
  let memo = {};
  try { const m = JSON.parse(fs.readFileSync(memoFile, 'utf8')); if (Date.now() - m.t < 8000) memo = m.v || {}; } catch {}
  let memoChanged = false;
  const git = (args) => {
    const k = args.join(' ');
    if (k in memo) { if (memo[k] === null) throw new Error('git'); return memo[k]; }
    try { memo[k] = gitRaw(args); } catch (e) { memo[k] = null; memoChanged = true; throw e; }
    memoChanged = true;
    return memo[k];
  };
  process.on('exit', () => {
    if (!memoChanged) return;
    try { fs.mkdirSync(memoDir, { recursive: true }); fs.writeFileSync(memoFile, JSON.stringify({ t: Date.now(), v: memo })); } catch {}
  });
  let gitRoot = null;
  try {
    const st = git(['status', '--porcelain=v2', '--branch']).split('\n');
    let branch = 'detached', ahead = 0, changed = 0;
    for (const l of st) {
      if (l.startsWith('# branch.head ')) branch = l.slice(14);
      else if (l.startsWith('# branch.ab ')) ahead = parseInt(l.split(' ')[2], 10) || 0;
      else if (l && !l.startsWith('#')) changed++;
    }
    let g = `🌿 ${green}${branch}${R}`;
    g += changed ? ` ${yellow}✎${changed}${R}` : ` ${dim}✓${R}`;
    if (ahead) g += ` ${cyan}↑${ahead}${R}`;
    try { const s = git(['stash', 'list']).split('\n').filter(Boolean).length; if (s) g += ` ${dim}📦${s}${R}`; } catch {}
    line1.push(g);
    try { gitRoot = git(['rev-parse', '--show-toplevel']); } catch {}

    // Có thay đổi chưa commit mà commit cuối đã lâu → nhắc
    if (changed) {
      try {
        const last = parseInt(git(['log', '-1', '--format=%ct']), 10);
        if (last && now - last > 3 * 3600) alerts.push(`${orange}⏰ ${changed} file chưa commit, commit cuối ${dur(now - last)} trước${R}`);
      } catch {}
    }
  } catch {}

  // ---- Dòng 2 ----
  const line2 = [];
  const cw = data.context_window;
  if (cw && cw.used_percentage != null) {
    const p = Math.round(cw.used_percentage);
    const size = cw.context_window_size || 200000;
    const filled = Math.min(10, Math.round(p / 10));
    const bar = '▓'.repeat(filled) + '░'.repeat(10 - filled);
    let s = `🧠 ${color(p)}${bar} ${kilo((size * p) / 100)}/${kilo(size)} (${p}%)${R}`;
    if (p >= 80) s += ` ${red}⚠ /compact${R}`;
    line2.push(s);
  }

  const rl = data.rate_limits || {};
  // Ghi hạn mức ra file cho đồng hồ "nhiên liệu" trên thanh WezTerm (~/.wezterm.lua đọc)
  if (rl.five_hour || rl.seven_day) {
    try {
      const fdir = path.join(process.env.LOCALAPPDATA || '', 'wez-ai');
      fs.mkdirSync(fdir, { recursive: true });
      fs.writeFileSync(path.join(fdir, 'fuel-claude.json'), JSON.stringify({
        five: rl.five_hour && rl.five_hour.used_percentage, five_reset: rl.five_hour && rl.five_hour.resets_at,
        week: rl.seven_day && rl.seven_day.used_percentage, week_reset: rl.seven_day && rl.seven_day.resets_at,
        t: Math.floor(now),
      }));
    } catch {}
  }
  if (rl.five_hour && rl.five_hour.used_percentage != null) {
    const p = Math.round(rl.five_hour.used_percentage);
    const ra = rl.five_hour.resets_at;
    let s = `⏱ 5h: ${color(p)}${p}%${R}`;
    if (ra) {
      s += `${dim} (reset ${hhmm(ra)})${R}`;
      // Dự báo: với tốc độ hiện tại, có hết hạn mức trước giờ reset không?
      const left = ra - now, elapsed = 5 * 3600 - left;
      if (p >= 50 && p < 100 && elapsed > 600) {
        const eta = ((100 - p) * elapsed) / p;
        if (eta < left) s += ` ${red}🔥 hết sau ~${dur(eta)}${R}`;
      }
    }
    line2.push(s);
  }
  if (rl.seven_day && rl.seven_day.used_percentage != null) {
    const p = Math.round(rl.seven_day.used_percentage);
    const ra = rl.seven_day.resets_at;
    line2.push(`📅 7 ngày: ${color(p)}${p}%${R}` + (ra ? `${dim} (reset ${weekday(ra)} ${hhmm(ra)})${R}` : ''));
  }

  const cost = data.cost || {};
  const add = cost.total_lines_added || 0, del = cost.total_lines_removed || 0;
  if (add || del) line2.push(`✏️ ${green}+${add}${R} ${red}−${del}${R}`);
  if (cost.total_duration_ms >= 60000) line2.push(`${dim}⏳ ${dur(cost.total_duration_ms / 1000)}${R}`);

  // Cache còn ấm bao lâu (hết hạn thì tin nhắn sau tốn hạn mức hơn)
  const pc2 = data.prompt_cache || {};
  if (pc2.expires_at && pc2.expires_at > now) {
    const left = pc2.expires_at - now;
    line2.push(`♨️ ${left < 600 ? yellow : dim}cache ${dur(left)}${R}`);
  }
  line2.push(`${dim}🕐 ${hhmm(now)}${R}`);

  // ---- Cảnh báo (dòng 3, chỉ hiện khi có) ----
  // AGENTS.md là file chung của 3 AI: báo khi vừa bị sửa trong 15 phút
  try {
    const f = path.join(gitRoot || projDir, 'AGENTS.md');
    const age = now - fs.statSync(f).mtimeMs / 1000;
    if (age < 15 * 60) alerts.push(`${yellow}👀 AGENTS.md vừa đổi ${dur(age)} trước — kiểm tra trước khi sửa${R}`);
  } catch {}

  // Cache nguội: tin nhắn tiếp theo phải đọc lại toàn bộ hội thoại → tốn hạn mức hơn
  const pcache = data.prompt_cache || {};
  if (pcache.expires_at && now > pcache.expires_at && (pcache.recache_tokens_if_cold || 0) > 50000) {
    alerts.push(`${cyan}🧊 cache nguội (${kilo(pcache.recache_tokens_if_cold)} token đọc lại) — việc mới thì nên /clear${R}`);
  }

  // 03/10: worker trong đội → gọn 1 dòng: vai ← Manager · 🧠 ngữ cảnh · ⏱ 5h · cảnh báo nặng (nếu có)
  if (isWorker) {
    const one = [`${pc}${bold}${role}${R}`];
    if (cw && cw.used_percentage != null) { const p = Math.round(cw.used_percentage); one.push(`🧠 ${color(p)}${p}%${R}` + (p >= 80 ? ` ${red}⚠ /compact${R}` : '')); }
    if (rl.five_hour && rl.five_hour.used_percentage != null) { const p = Math.round(rl.five_hour.used_percentage); one.push(`⏱ 5h ${color(p)}${p}%${R}`); }
    process.stdout.write(one.join('  ·  '));
    return;
  }
  const out = [line1.join('  |  ')];
  if (line2.length) out.push(line2.join('  |  '));
  if (alerts.length) out.push(alerts.join('  |  '));
  process.stdout.write(out.join('\n'));
});
