// ngam.js — worker CHẠY NGẦM (06/10/2026): không mở ô WezTerm, mỗi việc chạy 1 lần `claude -p` / `codex exec` trong nền,
// tiếp tục ĐÚNG phiên của vai (nhớ việc trước). Bật trong Hion\doi\<dự án>.json: "ngam": true cho cả đội, hoặc từng vai
// ("ngam": false ở vai = đưa vai đó trở lại ô). Luôn giữ trong ô (bỏ qua "ngam"): vai Grok · vai "rc": true (Remote Control
// trên điện thoại) · vai "giuO": "<lý do>" (cần dừng lại hỏi duyệt / dùng Chrome) · AI khác Claude/Codex.
// wez.ps1 send / cho / read tự chuyển sang đây khi vai chạy ngầm. Lệnh tay:
//   node ngam.js ds                       bảng mọi vai ngầm: ⏳ chạy · ⌛ hàng chờ · 🟢 rảnh · ⌛ quá hạn · ⛔ lỗi
//   node ngam.js log Sino.Bot [dòng] [-f] xem log việc đang/vừa chạy (-f = theo dõi liên tục, Ctrl+C thoát)
//   node ngam.js cho Sino.Bot[,Sino.SoLieu] [giây]   đợi xong, in kết quả (mã 0 xong · 1 quá hạn/lỗi · 2 hết giờ chờ)
//   node ngam.js dung Sino.Bot            dừng việc đang chạy / bỏ khỏi hàng chờ · dung-het: dừng mọi việc ngầm
// Cấu hình chung ~\.wez-ai.json: "ngam": { "toiDa": 4 (số worker ngầm chạy cùng lúc, dư thì xếp hàng), "phut": 30 (giới hạn
// mỗi việc; vai/đội ghi đè bằng "ngamPhut"), "token": 120000 (phiên dài hơn → tóm tắt rồi mở phiên mới) }
// Dữ liệu: %LOCALAPPDATA%\wez-ai\ngam\<DựÁn.Vai>.json (trạng thái) · log\<DựÁn.Vai>\<giờ>.log · ket-qua\<DựÁn.Vai>-<giờ>.md · tom-tat\
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const crypto = require('crypto');

const HOME = process.env.USERPROFILE || '';
const WEZAI = path.join(process.env.LOCALAPPDATA || '', 'wez-ai');
const DIR = path.join(WEZAI, 'ngam');
const HUB = path.resolve(__dirname, '..');
const readJson = (p) => { try { return JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, '')); } catch { return null; } };
const MAY = readJson(path.join(HOME, '.wez-ai.json')) || {};
const CFG = MAY.ngam || {};
const TOI_DA = CFG.toiDa || 4;
const PHUT = CFG.phut || 30;
const TOKEN = CFG.token || 120000;
const AI_ROOT = MAY.aiRoot || 'E:\\AI';
const CLAUDE = path.join(process.env.APPDATA || '', 'npm', 'node_modules', '@anthropic-ai', 'claude-code', 'bin', 'claude.exe');
const CODEX = path.join(process.env.APPDATA || '', 'npm', 'node_modules', '@openai', 'codex', 'bin', 'codex.js');
const now = () => Math.floor(Date.now() / 1000);
const hhmm = (t) => (t ? new Date(t * 1000).toTimeString().slice(0, 5) : '--:--');
const stamp = () => new Date().toISOString().replace(/[-:]/g, '').replace('T', '-').slice(0, 15);

function ghi(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = file + '.' + process.pid;
  fs.writeFileSync(tmp, typeof data === 'string' ? data : JSON.stringify(data, null, 1));
  fs.renameSync(tmp, file);
}
const stF = (key) => path.join(DIR, key + '.json');
const docSt = (key) => readJson(stF(key));
const luuSt = (key, st) => ghi(stF(key), st);
// trạng thái theo "ô" ngam-<key> → checklist việc (viec.json, bảng 📊) tự ☑ khi xong
const oSt = (key, state) => ghi(path.join(WEZAI, 'state', `ngam-${key}.json`), { state, ai: 'ngam', t: now() });
const song = (pid) => { if (!pid) return false; try { process.kill(pid, 0); return true; } catch { return false; } };

// ===== đội / vai =====
const arr = (x) => (Array.isArray(x) ? x : x && typeof x === 'object' ? Object.values(x) : []);
function timVai(key) {
  const m = /^([^./]+)[./](.+)$/.exec(String(key || ''));
  if (!m) return null;
  const d = readJson(path.join(HUB, 'doi', m[1] + '.json'));
  if (!d) return null;
  const w = arr(d.worker).find((x) => x && (x.vai === m[2] || x.ten === m[2]));
  return w ? { d, w, key: `${d.du_an}.${w.vai}` } : null;
}
// lý do vai phải ở lại trong ô ('' = được chạy ngầm)
function giuO(w) {
  if (w.ai === 'grok') return 'dùng Grok (chưa có chế độ ngầm)';
  if (w.rc) return 'dùng Remote Control trên điện thoại';
  if (w.giuO) return String(w.giuO);
  if (!['claude', 'codex'].includes(w.ai)) return `AI ${w.ai} chưa hỗ trợ chạy ngầm`;
  return '';
}
const muonNgam = (d, w) => (w.ngam != null ? !!w.ngam : !!d.ngam);
const batNgam = (d, w) => muonNgam(d, w) && !giuO(w);
// AI thật đang dùng: vai Codex hết hạn mức đang tạm Claude/Grok (ai-tam.json, do wez.ps1 Chon-AI ghi) → ngầm thì chạy Claude
function aiThat(d, w) {
  if (w.ai !== 'codex' || w.router) return w.ai;
  const t = (readJson(path.join(WEZAI, 'ai-tam.json')) || {})[`${d.du_an}.${w.vai}`];
  return t ? 'claude' : 'codex'; // ponytail: Codex hết → Claude luôn (Grok chỉ chạy trong ô)
}
function moiDoi() {
  let fs_ = [];
  try { fs_ = fs.readdirSync(path.join(HUB, 'doi')).filter((x) => x.endsWith('.json')); } catch {}
  return fs_.map((f) => readJson(path.join(HUB, 'doi', f))).filter((d) => d && d.du_an);
}

// ===== điều phối: giới hạn số worker ngầm chạy cùng lúc, dư thì xếp hàng =====
function khoa(fn) {
  const k = path.join(DIR, '.khoa');
  fs.mkdirSync(DIR, { recursive: true });
  for (let i = 0; i < 100; i++) {
    try { fs.mkdirSync(k); break; } catch {
      try { if (Date.now() - fs.statSync(k).mtimeMs > 20000) fs.rmdirSync(k); } catch {}
      cp.execSync('ping -n 1 -w 100 127.0.0.1 >nul 2>&1 & exit 0', { stdio: 'ignore', shell: 'cmd.exe' }); // ngủ ~0,1 giây
    }
  }
  try { return fn(); } finally { try { fs.rmdirSync(k); } catch {} }
}
function moiSt() {
  let ds = [];
  try { ds = fs.readdirSync(DIR).filter((x) => x.endsWith('.json')); } catch {}
  return ds.map((f) => ({ key: f.slice(0, -5), st: readJson(path.join(DIR, f)) })).filter((x) => x.st);
}
function ketThuc(key, st, trangThai, noiDung) {
  st.trang_thai = trangThai; st.ket_thuc = now(); st.pid = null;
  if (!st.ket_qua) st.ket_qua = path.join(DIR, 'ket-qua', `${key}-${stamp()}.md`);
  ghi(st.ket_qua, noiDung);
  luuSt(key, st); oSt(key, 'idle');
}
// Hạn mức Claude (statusline.js ghi wez-ai\fuel-claude.json): 5 giờ ≥ "claudeDung" (85%) hoặc tuần ≥ "claudeDungTuan" (95%)
// → không mở việc Claude MỚI (việc đang chạy làm tiếp). Qua giờ hồi (five_reset / week_reset) thì coi như đã hồi.
// Trả '' = còn dùng được, hoặc lý do đang dừng.
function claudeGanHet() {
  const f = readJson(path.join(WEZAI, 'fuel-claude.json'));
  if (!f) return '';
  const t = now();
  const nam = CFG.claudeDung || 85, tuan = CFG.claudeDungTuan || 95;
  if ((f.five || 0) >= nam && !(f.five_reset && t >= f.five_reset)) return `Claude 5 giờ ${f.five}% ≥ ${nam}% — hồi lúc ${hhmm(f.five_reset)}`;
  if ((f.week || 0) >= tuan && !(f.week_reset && t >= f.week_reset)) return `Claude tuần ${f.week}% ≥ ${tuan}% — hồi ${new Date(f.week_reset * 1000).toLocaleString('vi-VN')}`;
  return '';
}
function dieuPhoi() {
  khoa(() => {
    const ds = moiSt();
    for (const { key, st } of ds) {
      if (st.trang_thai === 'chay' && !song(st.pid)) {
        ketThuc(key, st, 'loi', `# ⛔ ${key} — tiến trình ngầm chết giữa chừng\n- Việc: ${st.viec}\n- Có thể do khởi động lại máy / bị tắt tay. Việc CHƯA xong — giao lại nếu cần.\n- Log: ${st.log || '(chưa có)'}\n`);
      }
    }
    let dangChay = ds.filter((x) => x.st.trang_thai === 'chay').length;
    const hang = ds.filter((x) => x.st.trang_thai === 'cho').sort((a, b) => a.st.giao_luc - b.st.giao_luc);
    const claudeHet = claudeGanHet();
    for (const { key, st } of hang) {
      if (dangChay >= TOI_DA) break;
      const v = timVai(key);
      if (claudeHet && v && aiThat(v.d, v.w) === 'claude') continue; // Claude gần hết hạn mức → việc Claude chờ, việc Codex vẫn chạy
      const c = cp.spawn(process.execPath, [__filename, 'chay', key], { detached: true, stdio: 'ignore', windowsHide: true, cwd: HUB });
      c.unref();
      st.trang_thai = 'chay'; st.pid = c.pid; st.bat_dau = now();
      luuSt(key, st); dangChay++;
    }
  });
}

// ===== lời giao vai cho phiên mới =====
const LUAT_NGAM = 'BẠN ĐANG CHẠY NGẦM: không có ô màn hình, không ai đọc câu hỏi giữa chừng. Không hỏi lại — tự chọn cách hợp lý và ghi "Đã tự chọn: …". ' +
  'Việc 🔴 (tiền, gửi ra ngoài, xoá dữ liệu, push/deploy, đổi giá, sửa bot thật) → chạy node E:\\AI\\Hion\\cai-dat\\duyet.js them <dự án> "câu hỏi + gợi ý" rồi bỏ qua phần đó, làm tiếp phần còn lại. ' +
  'Lệnh bị hook chặn → không tìm đường vòng. Có giới hạn thời gian: làm gọn, ghi kết quả vào file sớm. ' +
  'Câu trả lời CUỐI CÙNG của bạn được lưu làm file kết quả gửi Manager: viết đủ 5 trường (Đầu ra · Xong chưa · Bằng chứng · Còn lại · Ai làm tiếp) + "Skill: …".';
function loiVai(d, w) {
  const ten = w.ten || w.vai;
  return `Bạn là worker ${d.logo || ''} ${d.du_an} · ${w.icon || ''} ${ten}. Phụ trách: ${w.viec}. Manager của bạn: ${d.du_an}.Manager.` +
    (w.quyen ? ` QUYỀN CỦA BẠN: ${w.quyen}` : '') +
    ` Luật chung: E:\\AI\\Hion\\quy-trinh-lien-mach.md. Thư mục dự án: ${path.join(AI_ROOT, d.du_an)} (đọc AGENTS.md + tien-do của dự án khi cần). ` +
    'Làm đúng phần mình; không tự commit nếu không được dặn; không gửi tin/đăng bài/chạm tiền khi chưa được duyệt.\n' + LUAT_NGAM;
}

// ===== chạy 1 lượt AI, ghi log dễ đọc =====
function chayAI({ ai, d, w, ses, prompt, giay, logF, key }) {
  return new Promise((resolve) => {
    const projDir = path.join(AI_ROOT, d.du_an);
    const env = { ...process.env, WEZTERM_PANE: `ngam-${key}`, WEZ_NGAM: key };
    for (const k of Object.keys(env)) if (/^CLAUDE/.test(k)) delete env[k];
    const chiDoc = /\bWrite\b/.test(String(w.chan || ''));
    let exe, args, moiSes = ses;
    if (ai === 'claude') {
      if (!moiSes) moiSes = crypto.randomUUID();
      const chan = String(w.chan || '').split(/\s+/).filter(Boolean);
      exe = CLAUDE;
      args = ['-p', '--output-format', 'stream-json', '--verbose', '--permission-mode', 'bypassPermissions',
        '--append-system-prompt', loiVai(d, w), ...(ses ? ['--resume', ses] : ['--session-id', moiSes]),
        ...(chan.length ? [`--disallowedTools=${chan.join(',')}`] : [])];
    } else {
      const bang = readJson(path.join(HOME, '.codex-tai-khoan.json')) || {};
      const soTk = w.tk || (bang.duAn || {})[d.du_an];
      const tk = arr(bang.taiKhoan).find((t) => t.so === soTk);
      env.CODEX_HOME = w.router ? path.join(HOME, '.codex') : tk ? tk.thuMuc : path.join(HOME, '.codex');
      exe = process.execPath;
      const chung = [...(w.router ? ['-p', 'router'] : []), ...(chiDoc ? ['-s', 'read-only'] : [])];
      args = [CODEX, 'exec', ...chung, ...(ses ? ['resume', ses] : []), '--json', '--skip-git-repo-check', '-'];
    }
    fs.mkdirSync(path.dirname(logF), { recursive: true });
    const log = (s) => fs.appendFileSync(logF, `[${new Date().toTimeString().slice(0, 8)}] ${s}\n`);
    log(`▶ ${key} · ${ai}${ses ? ' · tiếp phiên ' + ses : ' · phiên mới'} · giới hạn ${Math.round(giay / 60)} phút`);
    const c = cp.spawn(exe, args, { cwd: projDir, env, windowsHide: true });
    let buf = '', cuoi = '', token = 0, quaHan = false, loiRa = '';
    const cat = (s, n) => { s = String(s == null ? '' : s).replace(/\s+/g, ' ').trim(); return s.length > n ? s.slice(0, n) + '…' : s; };
    const doc = (line) => {
      let e; try { e = JSON.parse(line); } catch { if (line.trim()) log('· ' + cat(line, 300)); return; }
      if (ai === 'claude') {
        if (e.type === 'system' && e.subtype === 'init') { moiSes = e.session_id || moiSes; log(`⚙ phiên ${moiSes} · ${e.model || ''}`); }
        else if (e.type === 'assistant') {
          const u = e.message && e.message.usage;
          if (u) token = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
          for (const b of (e.message && e.message.content) || []) {
            if (b.type === 'text' && b.text.trim()) { cuoi = b.text; log('💬 ' + cat(b.text, 600)); }
            else if (b.type === 'tool_use') { const i = b.input || {}; log(`🔧 ${b.name}: ` + cat(i.command || i.file_path || i.pattern || i.url || i.description || JSON.stringify(i), 300)); }
          }
        } else if (e.type === 'user') {
          for (const b of (e.message && e.message.content) || []) if (b.type === 'tool_result') {
            const t = Array.isArray(b.content) ? b.content.map((x) => x.text || '').join(' ') : b.content;
            log(`   ${b.is_error ? '⛔' : '↳'} ` + cat(t, 300));
          }
        } else if (e.type === 'result') {
          if (e.result) cuoi = e.result;
          log(`${e.is_error ? '⛔' : '🏁'} ${e.subtype} · ${e.num_turns || '?'} lượt · ${Math.round((e.duration_ms || 0) / 1000)} giây`);
        }
      } else {
        const it = e.item || {};
        if (e.type === 'thread.started') { moiSes = e.thread_id || moiSes; log(`⚙ phiên ${moiSes}`); }
        else if (e.type === 'item.completed' && it.type === 'agent_message') { cuoi = it.text || cuoi; log('💬 ' + cat(it.text, 600)); }
        else if (e.type === 'item.completed' && it.type === 'command_execution') log(`🔧 $ ${cat(it.command, 250)} (mã ${it.exit_code})\n   ↳ ${cat(it.aggregated_output, 300)}`);
        else if (e.type === 'item.completed' && it.type === 'file_change') log('📝 ' + arr(it.changes).map((x) => `${x.kind} ${x.path}`).join(', '));
        else if (e.type === 'item.completed' && it.type === 'mcp_tool_call') log(`🔌 ${it.server}.${it.tool} ${it.status || ''}`);
        else if (e.type === 'item.completed' && it.type === 'web_search') log('🔎 ' + cat(it.query, 200));
        else if (e.type === 'item.completed' && it.type === 'error') log('⛔ ' + cat(it.message, 300));
        else if (e.type === 'turn.failed' || e.type === 'error') log('⛔ ' + cat((e.error && e.error.message) || e.message, 400));
        else if (e.type === 'turn.completed') log(`🏁 xong lượt · vào ${(e.usage || {}).input_tokens || '?'} token`);
      }
    };
    c.stdout.on('data', (x) => { buf += x; let i; while ((i = buf.indexOf('\n')) >= 0) { doc(buf.slice(0, i)); buf = buf.slice(i + 1); } });
    c.stderr.on('data', (x) => { loiRa = (loiRa + x).slice(-2000); });
    const hen = setTimeout(() => {
      quaHan = true; log(`⌛ QUÁ HẠN ${Math.round(giay / 60)} phút → dừng`);
      try { cp.execSync(`taskkill /PID ${c.pid} /T /F`, { stdio: 'ignore' }); } catch {}
    }, giay * 1000);
    c.stdin.end(prompt);
    c.on('error', (er) => { loiRa += String(er); });
    c.on('close', (code) => {
      clearTimeout(hen); if (buf) doc(buf);
      if (code && loiRa.trim()) log('stderr: ' + cat(loiRa, 800));
      if (ai === 'codex' && moiSes) token = tokenCodex(env.CODEX_HOME, moiSes) || token;
      log(`■ kết thúc mã ${code} · context ~${token} token`);
      resolve({ code, quaHan, cuoi, ses: moiSes, token, loiRa });
    });
  });
}
// Codex: context thật = last_token_usage của sự kiện token_count cuối trong file phiên (rollout-*<id>.jsonl)
function tokenCodex(home, id) {
  const goc = path.join(home, 'sessions');
  const tim = (dir, sau) => {
    let ds = []; try { ds = fs.readdirSync(dir, { withFileTypes: true }); } catch { return null; }
    ds.sort((a, b) => b.name.localeCompare(a.name));
    for (const x of ds) {
      const p = path.join(dir, x.name);
      if (x.isDirectory() && sau > 0) { const r = tim(p, sau - 1); if (r) return r; }
      else if (x.isFile() && x.name.includes(id)) return p;
    }
    return null;
  };
  const f = tim(goc, 3); if (!f) return 0;
  const ls = fs.readFileSync(f, 'utf8').trim().split('\n');
  for (let i = ls.length - 1; i >= 0; i--) {
    if (!ls[i].includes('token_count')) continue;
    try { const u = JSON.parse(ls[i]).payload.info.last_token_usage; return u.input_tokens || 0; } catch {}
  }
  return 0;
}

// ===== runner: 1 việc của 1 vai (tiến trình nền do dieuPhoi mở) =====
async function chay(key) {
  const v = timVai(key); const st = docSt(key);
  if (!v || !st) return;
  const { d, w } = v;
  const ai = aiThat(d, w);
  const phut = w.ngamPhut || d.ngamPhut || PHUT;
  const het = Date.now() + phut * 60000;
  const ts = stamp();
  st.trang_thai = 'chay'; st.pid = process.pid; st.bat_dau = now(); st.ai = ai;
  st.log = path.join(DIR, 'log', key, `${ts}.log`);
  st.ket_qua = path.join(DIR, 'ket-qua', `${key}-${ts}.md`);
  if (st.ai_phien && st.ai_phien !== ai) st.session = ''; // đổi AI → phiên cũ không dùng được
  if (!st.session) st.session = phienSoDoi(d.du_an, w.vai, ai) || '';
  luuSt(key, st); oSt(key, 'work');
  let ses = st.session || null, tomTat = '';
  const chung = { ai, d, w, logF: st.log, key };
  // 7) phiên quá dài → tóm tắt phiên cũ, mở phiên mới kèm tóm tắt (đỡ đọc lại cả phiên dài mỗi việc)
  if (ses && (st.token || 0) > TOKEN) {
    const r = await chayAI({ ...chung, ses, giay: 300, prompt: 'Phiên này sắp được đóng vì quá dài. Viết TÓM TẮT (≤ 300 từ) những gì phiên sau cần nhớ: việc đã làm, file đã tạo/sửa, quyết định, việc dở, lưu ý. Không làm việc gì khác, không gọi công cụ.' });
    if (r.cuoi && !r.quaHan) {
      tomTat = r.cuoi; ses = null;
      ghi(path.join(DIR, 'tom-tat', `${key}-${ts}.md`), `# Tóm tắt phiên ${st.session} (${st.token} token)\n\n${tomTat}\n`);
    }
  }
  const giay = Math.max(60, Math.floor((het - Date.now()) / 1000));
  // Codex không có system prompt riêng, và resume phiên không tồn tại thì lặng lẽ mở phiên mới → luôn kèm lời giao vai
  const dau = (ai === 'codex' ? loiVai(d, w) + '\n\n' : '') + (tomTat ? `TÓM TẮT PHIÊN TRƯỚC CỦA VAI NÀY:\n${tomTat}\n\n` : '');
  let r = await chayAI({ ...chung, ses, giay, prompt: `${dau}VIỆC MỚI (giới hạn ${phut} phút): ${st.viec}` });
  // phiên cũ không mở được (bị xoá / sai tài khoản) → mở phiên mới 1 lần
  if (ses && r.code && !r.cuoi && !r.quaHan) {
    fs.appendFileSync(st.log, '↻ không tiếp được phiên cũ → mở phiên mới\n');
    r = await chayAI({ ...chung, ses: null, giay: Math.max(60, Math.floor((het - Date.now()) / 1000)), prompt: `${ai === 'codex' ? loiVai(d, w) + '\n\n' : ''}VIỆC MỚI (giới hạn ${phut} phút): ${st.viec}` });
  }
  st.session = r.ses || st.session; st.ai_phien = ai; st.token = r.token;
  const tt = r.quaHan ? 'qua-han' : r.code ? 'loi' : 'xong';
  const dauDe = { xong: '✅ xong', 'qua-han': `⌛ QUÁ HẠN — đã dừng sau ${phut} phút, việc CHƯA xong`, loi: `⛔ lỗi (mã ${r.code})` }[tt];
  const bd = st.bat_dau, kt = now();
  ketThuc(key, st, tt, `# ${dauDe} · ${key}\n` +
    `- Việc: ${st.viec}\n- Giao ${hhmm(st.giao_luc)} · chạy ${hhmm(bd)} → ${hhmm(kt)} (${Math.round((kt - bd) / 60)} phút, giới hạn ${phut})\n` +
    `- AI: ${ai} · phiên ${st.session} · context ~${st.token} token${tomTat ? ' · đã tóm tắt + mở phiên mới' : ''}\n- Log: ${st.log}\n\n` +
    (r.quaHan ? `## ⌛ Quá hạn\nĐã dừng tiến trình. Phần đã làm xem log. Câu trả lời cuối trước khi dừng:\n\n` : '## Kết quả\n') +
    (r.cuoi || '(không có câu trả lời)') + (tt === 'loi' && r.loiRa ? `\n\n## Lỗi\n\`\`\`\n${r.loiRa.slice(-1500)}\n\`\`\`\n` : '') + '\n');
  dieuPhoi();
  baoManager(d.du_an, key, { xong: 'xong (✅)', 'qua-han': 'QUÁ HẠN (⌛, chưa xong)', loi: 'LỖI (⛔)' }[tt], st.ket_qua);
}
// Tự báo Manager (06/10, người dùng chốt): việc ngầm kết thúc → gõ 1 dòng vào ô Manager của đội (Claude đang bận thì
// dòng nằm hàng chờ, xong lượt sẽ đọc). Manager đang chờ duyệt (🔔) thì không gõ — tránh trả lời nhầm hộp hỏi.
// Tắt: "ngam": {"baoManager": false} trong ~\.wez-ai.json.
function baoManager(proj, key, nhan, kqF) {
  if (CFG.baoManager === false) return;
  const so = readJson(path.join(WEZAI, 'doi', proj + '.json'));
  const o = so && so.manager && String(so.manager.o || '');
  if (!/^\d+$/.test(o)) return;
  const s = readJson(path.join(WEZAI, 'state', o + '.json'));
  if (s && s.state === 'need') return;
  const dir = path.join(HOME, '.local', 'share', 'wezterm');
  let sock = null;
  try {
    for (const n of fs.readdirSync(dir)) {
      const m = /^gui-sock-(\d+)$/.exec(n); if (!m || !song(+m[1])) continue;
      const t = fs.statSync(path.join(dir, n)).mtimeMs; if (!sock || t > sock.t) sock = { f: path.join(dir, n), t };
    }
  } catch {}
  if (!sock) return;
  const exe = MAY.wezterm || 'C:\\Program Files\\WezTerm\\wezterm.exe';
  const opt = { env: { ...process.env, WEZTERM_UNIX_SOCKET: sock.f }, stdio: 'ignore', timeout: 10000, windowsHide: true };
  const msg = `🌙 ${key} ${nhan} — kết quả: ${kqF} . Đọc rồi giao lô việc kế ngay (giao theo lô, mục 15).`;
  try {
    khoa(() => { // nhiều worker xong cùng lúc → gõ lần lượt, không xen chữ
      cp.execFileSync(exe, ['cli', '--no-auto-start', 'send-text', '--pane-id', o, '--', msg], opt);
      cp.execSync('ping -n 1 -w 400 127.0.0.1 >nul 2>&1 & exit 0', { stdio: 'ignore', shell: 'cmd.exe' });
      cp.execFileSync(exe, ['cli', '--no-auto-start', 'send-text', '--pane-id', o, '--no-paste', '\r'], opt);
    });
  } catch {}
}
// phiên Claude của vai lúc còn chạy trong ô (sổ đội) → ngầm tiếp tục đúng phiên đó
function phienSoDoi(proj, vai, ai) {
  const so = readJson(path.join(WEZAI, 'doi', proj + '.json'));
  const m = so && arr(so.worker).find((x) => x && x.vai === vai);
  if (!m || (m.ai && m.ai !== ai)) return '';
  return ai === 'claude' ? m.session || '' : ''; // Codex: tên luồng sai thì exec resume mở phiên mới không báo → chỉ tiếp theo mã phiên ngầm tự ghi
}

// ===== lệnh =====
function bangTrangThai() {
  const out = [];
  for (const d of moiDoi()) for (const w of arr(d.worker)) {
    if (!w || !muonNgam(d, w)) continue;
    const key = `${d.du_an}.${w.vai}`, ly = giuO(w), st = docSt(key);
    out.push({ key, d, w, giu: ly, st });
  }
  return out;
}
const NHAN = { chay: '⏳ đang chạy', cho: '⌛ hàng chờ', xong: '🟢 rảnh', 'qua-han': '⌛ quá hạn', loi: '⛔ lỗi', dung: '✖ đã dừng' };

async function main() {
  const [cmd, a1, a2, a3] = process.argv.slice(2);
  if (cmd === 'chay') return chay(a1);
  if (cmd === 'kiem') { // mã 0 = vai chạy ngầm · 1 = trong ô
    const v = timVai(a1); process.exit(v && batNgam(v.d, v.w) ? 0 : 1);
  }
  if (cmd === 'ds-bat') { // vai ngầm của 1 đội: "vai<TAB>phiên" (wez.ps1 doi bỏ khỏi bố cục ô)
    const d = readJson(path.join(HUB, 'doi', a1 + '.json')); if (!d) return;
    for (const w of arr(d.worker)) if (w && batNgam(d, w)) { const st = docSt(`${d.du_an}.${w.vai}`) || {}; console.log(`${w.vai}\t${st.session || ''}\t${st.trang_thai || ''}`); }
    return;
  }
  if (cmd === 'giao') { // giao <key> <file chứa việc>
    const v = timVai(a1);
    if (!v || !batNgam(v.d, v.w)) { console.error(`${a1} không chạy ngầm`); process.exit(4); }
    const viec = fs.readFileSync(a2, 'utf8').replace(/^\uFEFF/, '').trim();
    const r = khoa(() => {
      const st = docSt(v.key) || {};
      if (st.trang_thai === 'cho' || (st.trang_thai === 'chay' && song(st.pid))) return st;
      luuSt(v.key, { ...st, trang_thai: 'cho', viec, giao_luc: now(), bat_dau: null, ket_thuc: null, pid: null, log: null, ket_qua: null, tu: process.env.WEZTERM_PANE || '' });
      oSt(v.key, 'work');
      return null;
    });
    if (r) {
      console.log(`⛔ ${v.key} đang bận (${NHAN[r.trang_thai]} từ ${hhmm(r.bat_dau || r.giao_luc)}): "${String(r.viec).slice(0, 80)}" → chưa nhận việc mới.`);
      console.log(`   Đợi xong: wez.ps1 cho ${v.key}  ·  xem log: wez.ps1 read ${v.key}  ·  dừng việc cũ: node ${__filename} dung ${v.key}`);
      process.exit(3);
    }
    dieuPhoi();
    const st = docSt(v.key);
    if (st.trang_thai === 'chay') console.log(`🌙 ${v.key} nhận việc, đang chạy ngầm (giới hạn ${v.w.ngamPhut || v.d.ngamPhut || PHUT} phút). Đợi: wez.ps1 cho ${v.key} · log: wez.ps1 read ${v.key}`);
    else if (claudeGanHet() && aiThat(v.d, v.w) === 'claude') console.log(`⏸ ${v.key} xếp hàng: ${claudeGanHet()}. Tự chạy khi Claude hồi.`);
    else {
      const hang = moiSt().filter((x) => x.st.trang_thai === 'cho').sort((a, b) => a.st.giao_luc - b.st.giao_luc);
      console.log(`⌛ ${v.key} xếp hàng (thứ ${hang.findIndex((x) => x.key === v.key) + 1}/${hang.length}) — đang có ${TOI_DA} worker ngầm chạy (tối đa ${TOI_DA}).`);
    }
    return;
  }
  if (cmd === 'ds') {
    dieuPhoi();
    const ds = bangTrangThai();
    console.log(`🌙 Worker chạy ngầm · tối đa ${TOI_DA} cùng lúc · giới hạn mặc định ${PHUT} phút/việc · phiên > ${TOKEN} token thì mở phiên mới`);
    const het = claudeGanHet(); if (het) console.log(`⏸ Tạm dừng việc Claude mới: ${het} (việc Codex vẫn chạy)`);
    for (const x of ds) {
      const s = x.st || {};
      const tt = x.giu ? `🪟 trong ô (${x.giu})` : NHAN[s.trang_thai] || '🟢 rảnh (chưa giao)';
      const tg = s.trang_thai === 'chay' ? ` từ ${hhmm(s.bat_dau)}` : s.trang_thai === 'cho' ? ` giao ${hhmm(s.giao_luc)}` : s.ket_thuc ? ` lúc ${hhmm(s.ket_thuc)}` : '';
      console.log(`  ${x.key.padEnd(22)} ${tt}${tg}${s.viec && !x.giu ? ' — ' + String(s.viec).replace(/\s+/g, ' ').slice(0, 60) : ''}`);
    }
    if (!ds.length) console.log('  (chưa đội nào bật "ngam")');
    return;
  }
  if (cmd === 'log') {
    const v = timVai(a1); if (!v) { console.error('Không thấy vai ' + a1); process.exit(1); }
    const st = docSt(v.key) || {};
    const n = /^\d+$/.test(a2 || '') ? +a2 : 40, theo = [a2, a3].includes('-f');
    if (!st.log || !fs.existsSync(st.log)) { console.log(`${v.key}: chưa có log (${NHAN[st.trang_thai] || 'chưa giao việc'})`); return; }
    console.log(`── ${v.key} · ${NHAN[st.trang_thai] || ''} · ${st.log}`);
    let pos = 0;
    const in_ = () => { const s = fs.readFileSync(st.log, 'utf8'); const moi = s.slice(pos); pos = s.length; return moi; };
    process.stdout.write(in_().split('\n').slice(-n - 1).join('\n'));
    if (st.ket_qua && fs.existsSync(st.ket_qua) && st.trang_thai !== 'chay') console.log(`\n── Kết quả: ${st.ket_qua}`);
    if (theo) setInterval(() => { const m = in_(); if (m) process.stdout.write(m); }, 1000);
    return;
  }
  if (cmd === 'cho') {
    const keys = String(a1 || '').split(',').map((k) => timVai(k.trim())).filter(Boolean).map((v) => v.key);
    const max = (+a2 || 1800) * 1000, t0 = Date.now(); let ma = 0;
    const con = new Set(keys);
    while (con.size) {
      for (const k of [...con]) {
        const st = docSt(k) || {};
        if (st.trang_thai === 'cho' || st.trang_thai === 'chay') continue;
        con.delete(k);
        console.log(`── ${k}: ${NHAN[st.trang_thai] || 'chưa giao việc'} ──`);
        if (st.ket_qua && fs.existsSync(st.ket_qua)) console.log(fs.readFileSync(st.ket_qua, 'utf8').slice(-4000));
        if (['qua-han', 'loi'].includes(st.trang_thai)) ma = Math.max(ma, 1);
      }
      if (!con.size) break;
      if (Date.now() - t0 > max) { for (const k of con) console.log(`⌛ Hết giờ chờ, ${k} vẫn đang chạy — xem: wez.ps1 read ${k}`); process.exit(2); }
      dieuPhoi(); // tiện dọn tiến trình chết
      await new Promise((r) => setTimeout(r, 3000));
    }
    process.exit(ma);
  }
  if (cmd === 'dung' || cmd === 'dung-het') {
    const keys = cmd === 'dung-het' ? moiSt().map((x) => x.key) : [timVai(a1) && timVai(a1).key].filter(Boolean);
    for (const k of keys) {
      const st = docSt(k); if (!st || !['chay', 'cho'].includes(st.trang_thai)) continue;
      if (song(st.pid)) try { cp.execSync(`taskkill /PID ${st.pid} /T /F`, { stdio: 'ignore' }); } catch {}
      ketThuc(k, st, 'dung', `# ✖ ${k} — đã dừng tay\n- Việc: ${st.viec}\n- Log: ${st.log || '(chưa chạy)'}\n`);
      console.log(`✖ Đã dừng ${k}`);
    }
    dieuPhoi();
    return;
  }
  console.log('Dùng: node ngam.js ds | log <DựÁn.Vai> [dòng] [-f] | cho <DựÁn.Vai,...> [giây] | dung <DựÁn.Vai> | dung-het');
}

if (require.main === module) main();
module.exports = { batNgam, muonNgam, giuO, docSt, NHAN, bangTrangThai, dieuPhoi };
