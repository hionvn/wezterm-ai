// ngam.js — worker CHẠY NGẦM (06/10/2026): không mở ô WezTerm, mỗi việc chạy 1 lần `claude -p` / `codex exec` trong nền,
// tiếp tục ĐÚNG phiên của vai (nhớ việc trước). Bật trong TongQuanAI\doi\<dự án>.json: "ngam": true cho cả đội, hoặc từng vai
// ("ngam": false ở vai = đưa vai đó trở lại ô). Luôn giữ trong ô (bỏ qua "ngam"): vai Grok · vai "rc": true (Remote Control
// trên điện thoại) · vai "giuO": "<lý do>" (cần dừng lại hỏi duyệt / dùng Chrome) · AI khác Claude/Codex.
// wez.ps1 send / cho / read tự chuyển sang đây khi vai chạy ngầm. Lệnh tay:
//   node ngam.js ds                       bảng mọi vai ngầm: ⏳ chạy · ⌛ hàng chờ · 🟢 rảnh · ⌛ quá hạn · ⛔ lỗi
//   node ngam.js log DuAnB.Bot [dòng] [-f] xem log việc đang/vừa chạy (-f = theo dõi liên tục, Ctrl+C thoát)
//   node ngam.js cho DuAnB.Bot[,DuAnB.SoLieu] [giây]   đợi xong, in kết quả (mã 0 xong · 1 quá hạn/lỗi · 2 hết giờ chờ)
//   node ngam.js dung DuAnB.Bot            dừng việc đang chạy / bỏ khỏi hàng chờ · dung-het: dừng mọi việc ngầm
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
const GROK = path.join(HOME, '.grok', 'bin', 'grok.exe');
const CODEX = path.join(process.env.APPDATA || '', 'npm', 'node_modules', '@openai', 'codex', 'bin', 'codex.js');
// 07/10: ngủ ngay trong Node — trước gọi ping qua cmd.exe, tiến trình ngầm không có console nên mỗi lần bật 1 ô đen
const ngu = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
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
  if (w.rc) return 'dùng Remote Control trên điện thoại';
  if (w.giuO) return String(w.giuO);
  if (!['claude', 'codex', 'grok'].includes(w.ai)) return `AI ${w.ai} chưa hỗ trợ chạy ngầm`;
  return '';
}
const muonNgam = (d, w) => !w.tat && (w.ngam != null ? !!w.ngam : !!d.ngam); // "tat": true = vai đang tắt (không chạy ngầm, không mở ô)
const batNgam = (d, w) => muonNgam(d, w) && !giuO(w);
// AI thật đang dùng: vai Codex hết hạn mức đang tạm Claude/Grok (ai-tam.json, do wez.ps1 Chon-AI ghi) → ngầm thì chạy Claude
// 07/10 (người dùng: "ưu tiên GPT, hết hạn mức chuyển sang Sonnet"): vai router mà 9router báo hết hạn mức → ghi router-het.json,
// mọi vai router chạy Claude Sonnet tới giờ "den" (nghỉ "routerNghiPhut", mặc định 60) rồi tự thử lại GPT.
const ROUTER_HET = path.join(WEZAI, 'router-het.json');
const routerHet = () => ((readJson(ROUTER_HET) || {}).den || 0) > now();
const HET_MUC = /usage limit|rate.?limit|\b429\b|quota|exhaust|insufficient|out of credits|no (available|active) (account|connection)s?|too many requests/i;
// Grok hết hạn mức (grok-het.json, cùng file wez.ps1 dùng) → vai Grok chạy Claude tới giờ "den"
const GROK_HET = path.join(WEZAI, 'grok-het.json');
const API_KEY_F = path.join(WEZAI, 'anthropic-key.txt'), API_CHI = path.join(WEZAI, 'api-chi.json');
const grokHet = () => ((readJson(GROK_HET) || {}).den || 0) > now();
// 18/10: vai còn để "claude" mà cả 2 Claude hết → chạy GPT qua 9router (hết thì Codex tài khoản riêng). Vai router (mặc định đội DuAnG)
// đi GPT trước, 9router hết → Claude chính → Claude tkchinh (claudeTk). Grok chỉ chạy trong ô (wez.ps1), không có ở chạy ngầm.
// 19/10 người dùng: "Hết grok hết 9router mới chuyển sang tkphumail, hết tkphumail mới chuyển sang tkchinh"
// → mọi worker (trừ vai Codex tài khoản riêng, vai chỉ đọc "chan" = Claude) đi Grok → 9router → Claude (claudeTk: tkphumail → tkchinh).
// 23/10 (người dùng: "anthropic còn nhiều"): còn ngân sách API thì Claude (khoá API trực tiếp) đi TRƯỚC Grok/9router
const thuTu = () => (apiCon() && !MAY.apiChiEp ? 'claude' : fs.existsSync(GROK) && !grokHet() ? 'grok' : !routerHet() ? 'router' : 'claude');
const riengVai = (w) => !!w.chan || !!w.epClaude; // 19/10: cả vai Codex thường cũng theo thứ tự (Codex tài khoản riêng hết 5h → 403/usage limit hàng loạt)
const vaiDuPhong = (w) => (riengVai(w) ? w : { ...w, router: thuTu() === 'router' });
function aiThat(d, w) {
  if (w.chan || w.epClaude) return 'claude'; // epClaude (23/10): Tổng quản tạm ép 1 vai chạy Claude cho việc code khó
  if (!riengVai(w)) { const t = thuTu(); return t === 'router' ? 'codex' : t; }
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
      ngu(100);
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
// 18/10 (người dùng: "thêm acc claude cũ tkchinh, hết hạn mức thì chuyển"): hồ sơ Claude thứ 2 ở ~\.claude-tk2
// (đăng nhập 1 lần: $env:CLAUDE_CONFIG_DIR="$HOME\.claude-tk2"; claude → /login). projects\ nối junction về ~\.claude\projects
// để --resume phiên cũ chạy được ở cả 2 tài khoản. Tài khoản đang hết (báo lỗi hạn mức) ghi claude-het-<tk>.json.
const TK2 = path.join(require('os').homedir(), '.claude-tk2');
// 22/10 (người dùng: "tkchinh điều khiển lâu dài, tkphumail chỉ để code"): app Claude trên máy chuyển sang tkchinh nên ~\.claude
// không còn là tkphu → tài khoản chính của worker ở hồ sơ riêng ~\.claude-tkphu. Chưa đăng nhập hồ sơ đó thì vẫn dùng ~\.claude như cũ.
const TKPHU = path.join(require('os').homedir(), '.claude-tkphu');
const tkHetF = (tk) => path.join(WEZAI, `claude-het-${tk}.json`);
const tkHet = (tk) => ((readJson(tkHetF(tk)) || {}).den || 0) > now();
// Trả 'chinh' | 'tk2' | '' (cả 2 đang hết). Ưu tiên tài khoản chính; chính hồi là quay về.
function claudeTk() {
  // 18/10 người dùng chốt: worker = GPT qua 9router trước; 9router hết → Claude chính → Claude tkchinh (tk2) CUỐI CÙNG
  // (tkchinh ưu tiên cho Tổng quản điều khiển).
  // 19/10 người dùng: "worker làm với grok, 9router và claude tkchinh, phiên này giữ làm tổng quản" → worker KHÔNG dùng tài khoản chính
  // 19/10 sau: "Chuyển tổng quản sang tkchinh" → đảo lại: Tổng quản dùng tkchinh, worker CHỈ dùng tài khoản chính tkphumail
  // 19/10 cuối: tkchinh là tài khoản chính (Tổng quản + mọi ô Claude) → fuel-claude.json giờ là hạn mức tkchinh;
  // worker dùng tkphumail trước (chỉ đổi khi báo lỗi hạn mức), hết mới mượn tkchinh tới ngưỡng "claudeDung".
  if (!tkHet('chinh')) return 'chinh';
  if (fs.existsSync(path.join(TK2, '.credentials.json')) && !tkHet('tk2') && !claudeGanHet()) return 'tk2';
  return '';
}
// 23/10 (người dùng: "cho các worker dùng trực tiếp api"): còn ngân sách API ("apiNganSach" USD, cộng dồn api-chi.json) thì việc Claude
// không phải chờ gói hồi — chạy bằng ANTHROPIC_API_KEY (gắn ở chayAI).
const apiCon = () => { try { return !!fs.readFileSync(path.join(WEZAI, 'anthropic-key.txt'), 'utf8').trim() && ((readJson(path.join(WEZAI, 'api-chi.json')) || {}).usd || 0) < (MAY.apiNganSach ?? 100); } catch { return false; } };
// apiChiEp (23/10): tiền API chỉ cho vai epClaude, cả đội vẫn Grok/9router
const claudeHetHan = () => (claudeTk() || (apiCon() && !MAY.apiChiEp) ? '' : (claudeGanHet() || 'cả 2 tài khoản Claude đang hết hạn mức'));
// ===== Tự lấy việc (07/10, người dùng: "không cho phép các worker nghỉ, hãy cho làm việc liên tục") =====
// Vai ngầm rảnh > 1 phút (Manager chưa giao lô kế) → tự xếp 1 việc "tự lấy việc". Trả lời "KHÔNG CÒN VIỆC" / lỗi
// → nghỉ 2 phút rồi tự lấy lại. 08/10 (người dùng: "giao việc liên tục chứ để nghỉ thế"): đo lượt TB 2 phút, 45% báo
// KHÔNG CÒN VIỆC, luật cũ "xong < 2 phút → nghỉ 10 phút" làm worker đứng ~80% thời gian → bỏ luật đó, 180/600 → 60/120,
// lời giao bắt làm nối nhiều việc ~20 phút + việc nền. Tắt: "ngam": {"tuLam": false} (cả máy) · "tuLam": false ở đội / vai.
const TU_LAM_SAU = 10, TU_LAM_NGHI = 30; // 17/10 người dùng: "không cho phép worker nào ngủ" (trước 60 / 120)
function viecTuLam(d, w) {
  const goc = path.join(AI_ROOT, d.du_an), ten = w.ten || w.vai;
  return `TỰ LẤY VIỆC (người dùng 07/10: worker không được nghỉ, làm liên tục). Bạn là ${d.du_an}.${w.vai} (${ten}). ` +
    `Đọc TRƯỚC file việc tồn: ${goc}\\app\\brief\\*viec-ton*.md và ${goc}\\brief\\*viec-ton*.md (nếu có) — mục ☐ của vai bạn là việc PHẢI làm, còn ☐ thì KHÔNG được báo "KHÔNG CÒN VIỆC". Rồi đọc: ${goc}\\tien-do-*.md (mục Đang làm / Việc tiếp / Kẹt), các brief mới nhất trong ${goc}\\brief\\ có nhắc vai bạn, và kết quả lô trước của bạn. ` +
    `Chọn việc 🟢 tiếp theo ĐÚNG VAI bạn mà chưa vai nào nhận (không làm trùng việc Manager đang giao cho vai khác, không sửa file vai khác đang sửa). Làm luôn tới xong, ghi file như thường. ` +
    `LÀM LIÊN TỤC ~20 PHÚT: xong 1 việc thì làm ngay việc kế, KHÔNG dừng sau 1 việc. Hết việc trong brief/tiến độ thì làm VIỆC NỀN đúng vai: ` +
    `(a) soát chéo đầu ra 24 giờ qua của vai khác cùng dự án, ghi lỗi tìm được; (b) kiểm chứng lại số liệu/khẳng định trong file vai mình với nguồn gốc; ` +
    `(c) nâng chất lượng file cũ của vai mình (rõ hơn, gọn hơn, sửa chỗ lỗi thời); (d) chuẩn bị sẵn bản nháp cho việc đang chờ người dùng duyệt/làm tay. ` +
    `Ghi thêm 1 dòng vào ${goc}\\brief\\tu-lam-${w.vai}.md cho mỗi việc: giờ · việc · file (vai chỉ đọc thì chỉ in ra). ` +
    'Câu trả lời cuối: báo 5 trường cho Manager. Chỉ khi đã làm hết cả việc nền mới bắt đầu câu trả lời bằng "KHÔNG CÒN VIỆC" + đề xuất 1–3 việc mới cho Manager.';
}
function tuLay() {
  if (CFG.tuLam === false) return 0;
  let n = 0; const t = now();
  for (const d of moiDoi()) {
    if (d.tuLam === false) continue;
    for (const w of arr(d.worker)) {
      if (!w || w.tuLam === false || w.tamDung || !batNgam(d, w)) continue;
      // 18/10 người dùng "đừng chạy phí token, ngân sách": việc tự lấy chỉ chạy bằng GPT; vai sẽ chạy Claude thì chờ việc giao (bật lại: "tuLamClaude": true)
      if (!CFG.tuLamClaude && aiThat(d, vaiDuPhong(w)) === 'claude') continue;
      const key = `${d.du_an}.${w.vai}`, st = docSt(key) || {};
      if (st.trang_thai === 'cho' || st.trang_thai === 'chay') continue;
      if (t - (st.ket_thuc || 0) < TU_LAM_SAU || (st.tu_lam_nghi && t < st.tu_lam_nghi)) continue;
      luuSt(key, { ...st, trang_thai: 'cho', viec: viecTuLam(d, w), giao_luc: t, bat_dau: null, ket_thuc: null, pid: null, log: null, ket_qua: null, tu: 'tu-lam', tu_lam: true });
      oSt(key, 'work'); n++;
    }
  }
  return n;
}
// Nhịp nền: 1 tiến trình "ngam.js giu" gọi dieuPhoi mỗi phút (tự lấy việc + mở hàng chờ khi không ai gọi lệnh)
const GIU_PID = path.join(DIR, 'giu.pid');
// 14/10: pid bị Windows dùng lại (giu.pid trỏ vào chrome-native-host) → tưởng còn sống, vòng tự lấy việc chết im.
// Vòng giu chạm file mỗi phút → file cũ > 3 phút = vòng đã chết dù pid còn.
const giuConSong = (pid) => song(pid) && Date.now() - fs.statSync(GIU_PID).mtimeMs < 180000;
// 19/10: từng có 2 bản giu cùng ghi đè giu.pid. giu.pid = "pid bản" (bản = giờ sửa ngam.js, giống han-muc.js):
// nhịp nào thấy pid trong file không phải mình thì tự thoát; code vừa sửa → bản mới giành lấy (bản cũ không giành lại).
const GIU_BAN = String(Math.floor(fs.statSync(__filename).mtimeMs));
const docGiu = () => { const [p, b] = (fs.existsSync(GIU_PID) ? fs.readFileSync(GIU_PID, 'utf8') : '').trim().split(/\s+/); return [+p || 0, b || '']; };
function giuSong() {
  const [pid, ban] = docGiu();
  if (giuConSong(pid) && +ban >= +GIU_BAN) return;
  const c = cp.spawn(process.execPath, [__filename, 'giu'], { detached: true, stdio: 'ignore', windowsHide: true, cwd: HUB });
  c.unref(); ghi(GIU_PID, `${c.pid} ${GIU_BAN}`);
}
// 19/10: máy đơ (422 chrome, CPU 80%) vì nhiều worker cùng chạy bài đo Chrome → tải cao thì KHÔNG mở việc mới
// (việc đang chạy không đụng, hàng chờ thử lại nhịp sau). Ngưỡng: "ngam": { "cpuToiDa": 70, "chromeToiDa": 150, "tienTrinhToiDa": 1000 }
const TAI_F = path.join(DIR, 'tai-may.json');
const nguongTai = () => ({ cpu: CFG.cpuToiDa || 70, chrome: CFG.chromeToiDa || 150, tienTrinh: CFG.tienTrinhToiDa || 1000 });
const quaTai = (m, n) => m.cpu >= n.cpu || m.chrome >= n.chrome || m.tienTrinh >= n.tienTrinh;
function doTai() {
  const os = require('os'), cu = readJson(TAI_F) || {}, t = Date.now();
  let idle = 0, tong = 0;
  for (const c of os.cpus()) { const x = c.times; idle += x.idle; tong += x.user + x.nice + x.sys + x.idle + x.irq; }
  // CPU = chênh lệch so với mẫu cũ ≥ 1 phút (nhiều tiến trình gọi dieuPhoi, mẫu chỉ thay mỗi phút → không nhảy theo vài giây)
  let { mau, mau_cu: mauCu } = cu;
  if (!mau || t - mau.luc >= 60000) { mauCu = mau; mau = { idle, tong, luc: t }; }
  const goc = mauCu || mau, cpu = tong > goc.tong ? Math.round(100 * (1 - (idle - goc.idle) / (tong - goc.tong))) : cu.cpu || 0;
  let { chrome = 0, tienTrinh = 0, luc_dem: lucDem = 0 } = cu;
  if (t - lucDem >= 30000) { // tasklist tối đa 1 lần / 30 giây
    try {
      const ds = cp.execFileSync('tasklist', ['/fo', 'csv', '/nh'], { windowsHide: true, encoding: 'utf8', timeout: 15000 }).split(/\r?\n/).filter(Boolean);
      tienTrinh = ds.length; chrome = ds.filter((l) => /^"chrome\.exe"/i.test(l)).length; lucDem = t;
    } catch {}
  }
  const m = { cpu, chrome, tienTrinh }, chan = quaTai(m, nguongTai());
  if (chan !== !!cu.chan) fs.appendFileSync(path.join(DIR, 'log', 'dieu-phoi.log'),
    `[${new Date().toLocaleString('vi-VN')}] ${chan ? '🐢 tải cao → tạm không mở việc ngầm mới' : '✅ tải ổn → mở việc lại'} · CPU ${cpu}% · chrome ${chrome} · tiến trình ${tienTrinh}\n`);
  ghi(TAI_F, { chan, ...m, luc: t, luc_dem: lucDem, mau, mau_cu: mauCu });
  return chan;
}
// 19/10: worker ngầm mở Windows Sandbox / Electron (npm run thu-khach) / cmd để thử rồi chết → cửa sổ mồ côi trên màn hình, máy lag.
// Đóng (taskkill /T) khi: đúng loại (Sandbox · electron.exe chạy từ E:\AI · cmd/node có cửa sổ) + chạy > 10 phút + chuỗi cha
// đứt (cha chết hoặc pid cha bị dùng lại) tại một tiến trình kiểu script, và trên chuỗi không có claude/codex/grok/ngam.js/
// wezterm/explorer còn sống (app người dùng tự mở có explorer làm cha → không đụng). Nhịp giu 5 phút/lần; log don-chrome-an.log.
const GOC_SCRIPT = /^(?:node|cmd|powershell|pwsh|bash|sh|conhost|python|electron|WindowsSandbox\w*)\.exe$/i;
const GIU_LAI = /^(?:claude|codex|grok|wezterm-gui|wezterm|explorer|WindowsTerminal)\.exe$/i;
function moCoi(p, m, cuaSo, t) {
  const loai = /^WindowsSandboxRemoteSession\.exe$/i.test(p.ten)
    || (/^electron\.exe$/i.test(p.ten) && (p.exe || p.cmd || '').replace(/^"/, '').toLowerCase().startsWith(AI_ROOT.toLowerCase() + '\\'))
    || (/^(?:cmd|node)\.exe$/i.test(p.ten) && cuaSo.has(p.pid));
  if (!loai || t - p.tao < 10 * 60000) return false;
  for (let x = p, i = 0; x && i < 64; i++) {
    if (GIU_LAI.test(x.ten) || (/^node\.exe$/i.test(x.ten) && /ngam\.js/i.test(x.cmd))) return false;
    const cha = m.get(x.ppid);
    if (!cha || cha.tao > x.tao) return GOC_SCRIPT.test(x.ten); // chuỗi cha đứt tại x
    x = cha;
  }
  return false;
}
function donCuaSo(thu) {
  const ps = `[Console]::OutputEncoding=[Text.Encoding]::UTF8
$w=@(Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } | ForEach-Object Id)
$p=@(Get-CimInstance Win32_Process | ForEach-Object { [pscustomobject]@{i=$_.ProcessId;p=$_.ParentProcessId;n=$_.Name;e=$_.ExecutablePath;c=$_.CommandLine;t=$(if($_.CreationDate){([DateTimeOffset]$_.CreationDate).ToUnixTimeMilliseconds()}else{0})} })
@{w=$w;p=$p} | ConvertTo-Json -Compress -Depth 3`;
  cp.execFile('powershell', ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(ps, 'utf16le').toString('base64')],
    { windowsHide: true, encoding: 'utf8', maxBuffer: 64 << 20, timeout: 60000 }, (e, out) => {
      let j; try { j = JSON.parse(out); } catch { return; }
      const ds = [].concat(j.p || []).map((x) => ({ pid: x.i, ppid: x.p, ten: x.n || '', tao: x.t || 0, exe: x.e || '', cmd: x.c || '' }));
      const m = new Map(ds.map((x) => [x.pid, x])), cs = new Set([].concat(j.w || [])), t = Date.now();
      const bo = ds.filter((x) => moCoi(x, m, cs, t));
      if (!thu) for (const x of bo) try { cp.execFileSync('taskkill', ['/PID', String(x.pid), '/T', '/F'], { stdio: 'ignore', windowsHide: true }); } catch {}
      if (!bo.length && !thu) return;
      const dong = `${new Date().toLocaleString('sv-SE').slice(0, 16)} don-cua-so: ${bo.length} cửa sổ mồ côi${thu ? ' (thử, chưa đóng)' : ' đã đóng'}` +
        bo.map((x) => ` · ${x.ten}#${x.pid} ${Math.round((t - x.tao) / 60000)}p ${(x.exe || x.cmd).slice(0, 80)}`).join('') + '\r\n';
      try { fs.appendFileSync(path.join(WEZAI, 'don-chrome-an.log'), Buffer.from(dong, 'utf16le')); } catch {} // log PowerShell *>> = UTF-16
      if (thu) process.stdout.write(dong);
    });
}
function dieuPhoi() {
  khoa(() => {
    const ds = moiSt();
    for (const { key, st } of ds) {
      if (st.trang_thai === 'chay' && !song(st.pid)) {
        ketThuc(key, st, 'loi', `# ⛔ ${key} — tiến trình ngầm chết giữa chừng\n- Việc: ${st.viec}\n- Có thể do khởi động lại máy / bị tắt tay. Việc CHƯA xong — giao lại nếu cần.\n- Log: ${st.log || '(chưa có)'}\n`);
      }
    }
    if (tuLay()) ds.splice(0, ds.length, ...moiSt()); // có vai vừa được tự giao việc → đọc lại hàng chờ
    let dangChay = ds.filter((x) => x.st.trang_thai === 'chay').length;
    const hang = ds.filter((x) => x.st.trang_thai === 'cho').sort((a, b) => a.st.giao_luc - b.st.giao_luc);
    const claudeHet = claudeHetHan();
    let taiCao = false; try { taiCao = doTai(); } catch {} // đo mỗi nhịp để CPU là trung bình ~1 phút
    for (const { key, st } of hang) {
      if (dangChay >= TOI_DA || taiCao) break;
      const v = timVai(key);
      if (claudeHet && v && aiThat(v.d, v.w) === 'claude' && !(v.w.epClaude && apiCon())) continue; // Claude gần hết hạn mức → việc Claude chờ, việc Codex vẫn chạy
      const c = cp.spawn(process.execPath, [__filename, 'chay', key], { detached: true, stdio: 'ignore', windowsHide: true, cwd: HUB });
      c.unref();
      st.trang_thai = 'chay'; st.pid = c.pid; st.bat_dau = now();
      luuSt(key, st); dangChay++;
    }
  });
  try { giuSong(); } catch {}
}

// ===== lời giao vai cho phiên mới =====
const LUAT_NGAM = 'BẠN ĐANG CHẠY NGẦM: không có ô màn hình, không ai đọc câu hỏi giữa chừng. Không hỏi lại — tự chọn cách hợp lý và ghi "Đã tự chọn: …". ' +
  'Việc 🔴 (tiền, gửi ra ngoài, xoá dữ liệu, push/deploy, đổi giá, sửa bot thật) → chạy node E:\\AI\\TongQuanAI\\cai-dat\\duyet.js them <dự án> "câu hỏi + gợi ý" rồi bỏ qua phần đó, làm tiếp phần còn lại. ' +
  'Lệnh bị hook chặn → không tìm đường vòng. Có giới hạn thời gian: làm gọn, ghi kết quả vào file sớm. ' +
  'Câu trả lời CUỐI CÙNG của bạn được lưu làm file kết quả gửi Manager: viết đủ 5 trường (Đầu ra · Xong chưa · Bằng chứng · Còn lại · Ai làm tiếp) + "Skill: …".';
function loiVai(d, w) {
  const ten = w.ten || w.vai;
  return `Bạn là worker ${d.logo || ''} ${d.du_an} · ${w.icon || ''} ${ten}. Phụ trách: ${w.viec}. Manager của bạn: ${d.du_an}.Manager.` +
    (w.quyen ? ` QUYỀN CỦA BẠN: ${w.quyen}` : '') +
    ` Luật chung: E:\\AI\\TongQuanAI\\quy-trinh-lien-mach.md. Thư mục làm việc: ${path.join(AI_ROOT, d.du_an, w.thuMuc || '')} (đọc AGENTS.md + tien-do của dự án khi cần). ` +
    'TIẾT KIỆM TOKEN: lệnh shell có output dài thì thêm tiền tố rtk (rtk git status/diff/log, rtk grep, rtk test <lệnh>, rtk err <lệnh>, rtk npm run …; Claude có hook tự gắn); đọc file theo đoạn (grep, sed -n, Read có offset/limit),không đọc lại file vừa đọc, không in log/diff dài (dùng tail, --stat); chạy test liên quan tới file đã sửa thay vì cả bộ (cả bộ chỉ trước khi báo xong việc lớn); trả lời cuối ngắn gọn. '+
    // 18/10: worker không commit → test đã commit mà mã chưa commit → bản sạch đỏ, phát hành hỏng 4 lần
    'Làm đúng phần mình; XONG VIỆC: chạy test liên quan, qua thì commit NGAY đúng file mình sửa (git add <từng file>, cả mã lẫn test đi kèm; không git add -A, không git stash, không commit file vai khác) với lời commit rõ nội dung, không push; KHÔNG commit khi chỉ ghi nhật ký (tu-lam-*.md, ra lại, kiểm lại không đổi) — nhật ký đi kèm commit của việc thật;  không gửi tin/đăng bài/chạm tiền khi chưa được duyệt.\n' + LUAT_NGAM;
}

// 23/10 (người dùng: "làm vòng tự học"): bài học tu-hoc.js rút mỗi tối (learn\bai-hoc\<DựÁn>.md, dòng "- [vai] …")
// → kèm 6 bài mới nhất của đúng vai (và vai *) vào mọi lượt giao việc.
function baiHoc(d, w) {
  let ds = [];
  try { ds = fs.readFileSync(path.join(HUB, 'learn', 'bai-hoc', `${d.du_an}.md`), 'utf8').split(/\r?\n/); } catch { return ''; }
  const cua = ds.filter((l) => l.startsWith(`- [${w.vai}]`) || l.startsWith('- [*]')).slice(-6);
  return cua.length ? `BÀI HỌC CỦA ĐỘI (rút từ lỗi đã gặp — làm theo để khỏi lặp lại):\n${cua.join('\n')}\n\n` : '';
}

// ===== chạy 1 lượt AI, ghi log dễ đọc =====
function chayAI({ ai, d, w, ses, prompt, giay, logF, key }) {
  return new Promise((resolve) => {
    const projDir = path.join(AI_ROOT, d.du_an, w.thuMuc || ''); // "thuMuc": chạy trong thư mục con (vd DuAnF build chỉ thấy app — sạch phòng)
    const env = { ...process.env, WEZTERM_PANE: `ngam-${key}`, WEZ_NGAM: key };
    for (const k of Object.keys(env)) if (/^CLAUDE/.test(k)) delete env[k];
    // 18/10 (người dùng): worker Claude dùng API key trả trước tới trần "apiNganSach" USD (mặc định 100); chi cộng dồn ở api-chi.json
    const tk = ai === 'claude' ? (claudeTk() || 'chinh') : ''; // 19/10: chính trước, hết mới tkchinh
    if (tk === 'tk2') env.CLAUDE_CONFIG_DIR = TK2;
    else if (tk === 'chinh' && fs.existsSync(path.join(TKPHU, '.credentials.json'))) env.CLAUDE_CONFIG_DIR = TKPHU;
    if (ai === 'claude') { try { const k = fs.readFileSync(API_KEY_F, 'utf8').trim(); if (k && (!MAY.apiChiEp || w.epClaude) && ((readJson(API_CHI) || {}).usd || 0) < (MAY.apiNganSach ?? 100)) env.ANTHROPIC_API_KEY = k; } catch {} } /* 19/10: apiNganSach 0 = worker dùng gói tkphumail, không dùng API key */
    const chiDoc = /\bWrite\b/.test(String(w.chan || ''));
    let exe, args, moiSes = ses;
    if (ai === 'claude') {
      if (!moiSes) moiSes = crypto.randomUUID();
      const chan = String(w.chan || '').split(/\s+/).filter(Boolean);
      exe = CLAUDE;
      args = ['-p', '--output-format', 'stream-json', '--verbose', '--permission-mode', 'bypassPermissions',
        '--strict-mcp-config', '--model', 'sonnet', // 18/10 bỏ MCP cho worker (tiết kiệm token) · 14/10 (người dùng): Tổng quản Opus, mọi worker chạy ngầm Sonnet
        '--append-system-prompt', loiVai(d, w), ...(ses ? ['--resume', ses] : ['--session-id', moiSes]),
        ...(chan.length ? [`--disallowedTools=${chan.join(',')}`] : [])];
    } else if (ai === 'grok') {
      // ponytail: --output-format json = 1 kết quả cuối (log không chạy theo từng bước); cần log sống thì đổi streaming-json
      const pf = path.join(DIR, 'prompt', `${key}-${Date.now()}.txt`);
      fs.mkdirSync(path.dirname(pf), { recursive: true }); fs.writeFileSync(pf, prompt);
      exe = GROK;
      args = ['--prompt-file', pf, '--output-format', 'json', '--permission-mode', 'bypassPermissions', ...(ses ? ['-r', ses] : [])];
      prompt = '';
    } else {
      const bang = readJson(path.join(HOME, '.codex-tai-khoan.json')) || {};
      const soTk = w.tk || (bang.duAn || {})[d.du_an];
      const tk = arr(bang.taiKhoan).find((t) => t.so === soTk);
      env.CODEX_HOME = w.router ? path.join(HOME, '.codex') : tk ? tk.thuMuc : path.join(HOME, '.codex');
      exe = process.execPath;
      // router: ghi rõ model từ router.config.toml (07/10 đổi 5.6-luna → 6-luna) — phiên cũ tiếp tục (resume) không giữ model cũ
      let mRouter = '';
      if (w.router) try { mRouter = (/^model\s*=\s*"([^"]+)"/m.exec(fs.readFileSync(path.join(HOME, '.codex', 'router.config.toml'), 'utf8')) || [])[1] || ''; } catch {}
      // 07/10: chạy ngầm thì TẮT plugin trình duyệt (chrome / browser / computer-use: tự mở Chrome điều khiển, dễ sót Chrome ẩn)
      // và bật tìm web phía máy chủ (search_service.web_run) — đã thử: tìm web được, số Chrome không tăng
      const khongTrinhDuyet = ['chrome', 'browser', 'unified-computer-use'].flatMap((p) => ['-c', `plugins."${p}@openai-bundled".enabled=false`]);
      const chung = [...(w.router ? ['-p', 'router'] : []), ...(mRouter ? ['-c', `model="${mRouter}"`] : []), ...khongTrinhDuyet, '-c', 'web_search="live"', ...(chiDoc ? ['-s', 'read-only'] : [])];
      args = [CODEX, 'exec', ...chung, ...(ses ? ['resume', ses] : []), '--json', '--skip-git-repo-check', '-'];
    }
    fs.mkdirSync(path.dirname(logF), { recursive: true });
    const log = (s) => fs.appendFileSync(logF, `[${new Date().toTimeString().slice(0, 8)}] ${s}\n`);
    log(`▶ ${key} · ${ai}${ses ? ' · tiếp phiên ' + ses : ' · phiên mới'} · giới hạn ${Math.round(giay / 60)} phút`);
    const c = cp.spawn(exe, args, { cwd: projDir, env, windowsHide: true });
    let buf = '', cuoi = '', token = 0, quaHan = false, loiRa = '', hetMuc = false;
    // 07/10: GPT qua 9router báo hết hạn mức → Codex tự thử lại tới hết giờ (25 việc phí trọn 30 phút) → dừng ngay để chuyển Sonnet
    const xemHet = (m) => {
      if (hetMuc || ai !== 'codex' || !w.router || !HET_MUC.test(String(m || ''))) return;
      hetMuc = true; log('↪ 9router hết hạn mức → dừng, chuyển Claude Sonnet');
      try { cp.execSync(`taskkill /PID ${c.pid} /T /F`, { stdio: 'ignore', windowsHide: true }); } catch {}
    };
    const cat = (s, n) => { s = String(s == null ? '' : s).replace(/\s+/g, ' ').trim(); return s.length > n ? s.slice(0, n) + '…' : s; };
    // 08/10: cả 7 tài khoản 429 mà 9router TREO (không trả lỗi) → 45 worker đứng im tới hết 30 phút.
    // Im lặng 5 phút (không phải đang chạy lệnh) = coi như hết hạn mức → chuyển Sonnet.
    let lanCuoi = Date.now(), dangLenh = false;
    const canh = setInterval(() => {
      if (!dangLenh && Date.now() - lanCuoi > 5 * 60e3) xemHet('9router treo 5 phút không trả lời (usage limit?)');
    }, 30e3);
    const doc = (line) => {
      lanCuoi = Date.now();
      let e; try { e = JSON.parse(line); } catch { if (line.trim()) log('· ' + cat(line, 300)); return; }
      if (e.item && e.item.type === 'command_execution') dangLenh = e.type === 'item.started';
      if (ai === 'grok') {
        moiSes = e.sessionId || moiSes; cuoi = e.text || cuoi;
        const u = e.usage || {}; token = (u.input_tokens || 0) + (u.cache_read_input_tokens || 0);
        log(`⚙ phiên ${moiSes}`); log('💬 ' + cat(e.text, 600)); log(`🏁 ${e.stopReason || ''} · ${e.num_turns || '?'} lượt`);
        if (e.is_error || e.error) loiRa += ' ' + JSON.stringify(e.error || e).slice(0, 500);
      } else if (ai === 'claude') {
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
          if (env.ANTHROPIC_API_KEY && e.total_cost_usd) { const c = readJson(API_CHI) || { usd: 0 }; c.usd = +(c.usd + e.total_cost_usd).toFixed(4); ghi(API_CHI, c); }
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
        else if (e.type === 'item.completed' && it.type === 'error') { log('⛔ ' + cat(it.message, 300)); loiRa += '\n' + it.message; xemHet(it.message); }
        else if (e.type === 'turn.failed' || e.type === 'error') { const m = (e.error && e.error.message) || e.message; log('⛔ ' + cat(m, 400)); loiRa += '\n' + m; xemHet(m); }
        else if (e.type === 'turn.completed') log(`🏁 xong lượt · vào ${(e.usage || {}).input_tokens || '?'} token`);
      }
    };
    // Grok in 1 JSON nhiều dòng lúc xong → gom hết, đọc 1 lần khi tiến trình đóng
    c.stdout.on('data', (x) => { buf += x; if (ai === 'grok') return; let i; while ((i = buf.indexOf('\n')) >= 0) { doc(buf.slice(0, i)); buf = buf.slice(i + 1); } });
    // 18/10: stderr có cả code worker in ra → chữ 'quota'/'limit' trong code làm báo nhầm 9router hết; chỉ xét dòng lỗi ngắn
    c.stderr.on('data', (x) => { loiRa = (loiRa + x).slice(-2000); String(x).split(/\r?\n/).filter(l => l.length < 400 && !/[{};]/.test(l) && /\bERROR\b|unexpected status|stream error/.test(l)).forEach(xemHet); });
    const hen = setTimeout(() => {
      quaHan = true; log(`⌛ QUÁ HẠN ${Math.round(giay / 60)} phút → dừng`);
      try { cp.execSync(`taskkill /PID ${c.pid} /T /F`, { stdio: 'ignore', windowsHide: true }); } catch {}
    }, giay * 1000);
    c.stdin.end(prompt);
    c.on('error', (er) => { loiRa += String(er); });
    c.on('close', (code) => {
      clearTimeout(hen); clearInterval(canh); if (buf) doc(ai === 'grok' ? buf.replace(/\s*\n\s*/g, ' ') : buf);
      if (code && loiRa.trim()) log('stderr: ' + cat(loiRa, 800));
      if (ai === 'codex' && moiSes) token = tokenCodex(env.CODEX_HOME, moiSes) || token;
      log(`■ kết thúc mã ${code} · context ~${token} token`);
      resolve({ code, quaHan, cuoi, ses: moiSes, token, loiRa, hetMuc, tk });
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
  const { d } = v, w = vaiDuPhong(v.w);
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
  const dau = (ai === 'codex' || ai === 'grok' ? loiVai(d, w) + '\n\n' : '') + baiHoc(d, w) + (tomTat ? `TÓM TẮT PHIÊN TRƯỚC CỦA VAI NÀY:\n${tomTat}\n\n` : '');
  let r = await chayAI({ ...chung, ses, giay, prompt: `${dau}VIỆC MỚI (giới hạn ${phut} phút): ${st.viec}` });
  // GPT qua 9router hết hạn mức → đánh dấu, trả việc về hàng chờ → lượt sau chạy Sonnet
  if (ai === 'codex' && w.router && (r.hetMuc || (r.code && !r.quaHan && HET_MUC.test(r.loiRa || '')))) {
    // nghỉ theo "reset after 6m 30s" của 9router (ít nhất 10 phút); không đọc được thì routerNghiPhut (60)
    const rs = /reset after\s*(?:(\d+)h)?\s*(?:(\d+)m)?\s*(?:(\d+)s)?/i.exec(r.loiRa || '');
    const nghi = rs && (rs[1] || rs[2] || rs[3]) ? Math.max(10, Math.ceil((+rs[1] || 0) * 60 + (+rs[2] || 0) + (+rs[3] || 0) / 60)) : MAY.routerNghiPhut || 60;
    ghi(ROUTER_HET, { den: now() + nghi * 60, luc: new Date().toLocaleString('vi-VN'), ly: `${key}: ${String(r.loiRa).trim().slice(-200)}` });
    fs.appendFileSync(st.log, `↪ 9router hết hạn mức → mọi vai GPT chạy Claude Sonnet ${nghi} phút, việc này xếp lại hàng chờ\n`);
    luuSt(key, { ...st, trang_thai: 'cho', pid: null, bat_dau: null });
    return dieuPhoi();
  }
  // Claude báo hết hạn mức → đánh dấu tài khoản đó hết 1 giờ (hoặc tới giờ "resets Xam/pm"), việc xếp lại → lượt sau dùng tài khoản kia
  if (ai === 'claude' && r.code && !r.quaHan && /usage limit|hit your (session |weekly |usage )?limit|session limit|limit reached|rate.?limit|\b429\b|out of (extra )?usage/i.test(`${r.loiRa || ''}\n${r.cuoi || ''}`)) {
    const tk = r.tk || 'chinh';
    // "resets 3:20pm" → nghỉ tới đúng giờ đó (qua nửa đêm thì sang hôm sau); không đọc được thì 1 giờ
    const rs = /resets?\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)/i.exec(`${r.loiRa || ''}\n${r.cuoi || ''}`);
    let den = now() + 3600;
    if (rs) { const d = new Date(); d.setHours((+rs[1] % 12) + (/pm/i.test(rs[3]) ? 12 : 0), +(rs[2] || 0), 0, 0); if (d <= Date.now()) d.setDate(d.getDate() + 1); den = Math.floor(d / 1000); }
    ghi(tkHetF(tk), { den, luc: new Date().toLocaleString('vi-VN'), ly: `${key}: ${String(r.loiRa || r.cuoi).trim().slice(-200)}` });
    fs.appendFileSync(st.log, `↪ Claude (${tk}) hết hạn mức → ${claudeTk() ? 'chuyển sang tài khoản ' + claudeTk() : 'cả 2 tài khoản hết, việc chờ'}; việc này xếp lại hàng chờ\n`);
    luuSt(key, { ...st, trang_thai: 'cho', pid: null, bat_dau: null });
    return dieuPhoi();
  }
  // Grok hết hạn mức → đánh dấu grok-het.json (grokNghiGio, mặc định 3 giờ), việc xếp lại → lượt sau chạy Claude
  if (ai === 'grok' && r.code && !r.quaHan && HET_MUC.test(r.loiRa || '')) {
    const gio = MAY.grokNghiGio || 3;
    ghi(GROK_HET, { den: now() + gio * 3600, ly: `${key}: ${String(r.loiRa).trim().slice(-200)}` });
    fs.appendFileSync(st.log, `↪ Grok hết hạn mức → mọi vai Grok chạy Claude ${gio} giờ, việc này xếp lại hàng chờ
`);
    luuSt(key, { ...st, trang_thai: 'cho', pid: null, bat_dau: null });
    return dieuPhoi();
  }
  // phiên cũ không mở được (bị xoá / sai tài khoản) → mở phiên mới 1 lần
  if (ses && r.code && !r.cuoi && !r.quaHan) {
    fs.appendFileSync(st.log, '↻ không tiếp được phiên cũ → mở phiên mới\n');
    r = await chayAI({ ...chung, ses: null, giay: Math.max(60, Math.floor((het - Date.now()) / 1000)), prompt: `${ai === 'codex' || ai === 'grok' ? loiVai(d, w) + '\n\n' : ''}VIỆC MỚI (giới hạn ${phut} phút): ${st.viec}` });
  }
  st.session = r.ses || st.session; st.ai_phien = ai; st.token = r.token;
  const tt = r.quaHan ? 'qua-han' : r.code ? 'loi' : 'xong';
  // tự lấy việc mà hết việc / lỗi → nghỉ TU_LAM_NGHI mới tự lấy lại
  if (st.tu_lam && (/^\s*\**\s*KHÔNG CÒN VIỆC/i.test(r.cuoi || '') || tt === 'loi')) st.tu_lam_nghi = now() + TU_LAM_NGHI;
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
      let t = 0; try { t = fs.statSync(path.join(dir, n)).mtimeMs; } catch {} // stat file socket trên Windows có lúc lỗi → vẫn dùng được
      if (!sock || t > sock.t) sock = { f: path.join(dir, n), t };
    }
  } catch {}
  if (!sock) return;
  const exe = MAY.wezterm || 'C:\\Program Files\\WezTerm\\wezterm.exe';
  const opt = { env: { ...process.env, WEZTERM_UNIX_SOCKET: sock.f }, stdio: 'ignore', timeout: 10000, windowsHide: true };
  const msg = `🌙 ${key} ${nhan} — kết quả: ${kqF} . Đọc rồi giao lô việc kế ngay (giao theo lô, mục 15).`;
  try {
    // ô nhập của Manager đang có chữ gõ dở (vd người dùng gõ "duyệt 1, 2, 3" chưa Enter) → không gõ chen, tránh dính chữ
    const man = cp.execFileSync(exe, ['cli', '--no-auto-start', 'get-text', '--escapes', '--pane-id', o], { ...opt, stdio: ['ignore', 'pipe', 'ignore'], encoding: 'utf8' });
    const tron = (s) => s.replace(/\x1b\[[0-9;?]*[A-Za-z]|\x1b\([AB0]/g, '');
    const raw = man.split('\n').filter((l) => /^\s*[❯›]/.test(tron(l))).pop() || '';
    // 08/10: Claude hiện câu gợi ý MỜ (vd "❯ 🌙 DuAnA.Security xong…") → trước đây tưởng chữ gõ dở, bỏ qua MỌI 🌙 → worker đứng không
    const nhap = /[❯›]\s*(?:\x1b\([AB0])?\x1b\[(?:0;)?2m/.test(raw) ? '' : tron(raw);
    // 07/10: ô Codex trống hiện chữ mờ "Ask Codex to do anything" → trước đây tưởng chữ gõ dở, Manager Codex không bao giờ nhận 🌙
    if (nhap.replace(/^\s*[❯›]\s*/, '').replace(/^(Ask Codex to do anything|Explain this codebase|Summarize recent commits|Implement \{feature\}|Find and fix a bug in @filename|Write tests for @filename|Improve documentation in @filename|Run \/review on my current changes|Use \/skills to list available skills)\s*$/, '').trim()) return;
    khoa(() => { // nhiều worker xong cùng lúc → gõ lần lượt, không xen chữ
      cp.execFileSync(exe, ['cli', '--no-auto-start', 'send-text', '--pane-id', o, '--', msg], opt);
      ngu(400);
      cp.execFileSync(exe, ['cli', '--no-auto-start', 'send-text', '--pane-id', o, '--no-paste', '\r'], opt);
      // 06/10: Enter có lúc không ăn (dòng 🌙 nằm ở ô nhập, Manager DuAnA đứng 15 phút) → kiểm lại, còn thì Enter lại
      for (let k = 0; k < 6; k++) { // 07/10: Manager Codex gom dòng dài thành [Pasted Content …] → kiểm cả chữ đó
        ngu(1000);
        const t = cp.execFileSync(exe, ['cli', '--no-auto-start', 'get-text', '--pane-id', o], { ...opt, stdio: ['ignore', 'pipe', 'ignore'], encoding: 'utf8' });
        if (!t.split('\n').some((l) => /^\s*[❯›]\s/.test(l) && (l.includes(`🌙 ${key} `) || l.includes('Pasted Content')))) break;
        cp.execFileSync(exe, ['cli', '--no-auto-start', 'send-text', '--pane-id', o, '--no-paste', '\r'], opt);
      }
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
  if (cmd === 'giu') { // nhịp nền mỗi phút; tiến trình khác đã giữ thì thoát
    const [cu, ban] = docGiu(), toi = `${process.pid} ${GIU_BAN}`;
    if (cu && cu !== process.pid && giuConSong(cu) && +ban >= +GIU_BAN) return;
    ghi(GIU_PID, toi);
    let lan = 0;
    const nhip = () => {
      if (docGiu()[0] !== process.pid) process.exit(0); // bản khác đã giành giu.pid → mình thoát
      try { ghi(GIU_PID, toi); dieuPhoi(); } catch {}
      if (lan++ % 5 === 0) donCuaSo(false); // 5 phút/lần
    };
    nhip(); setInterval(nhip, 60000); return;
  }
  if (cmd === 'don-cua-so') return donCuaSo(/^-?-?thu$/i.test(a1 || '')); // -Thu = chỉ liệt kê
  if (cmd === 'kiem-cua-so') { // tự kiểm hàm moCoi
    const assert = require('assert'), T = 1e12, P = (pid, ppid, ten, tao, them = {}) => ({ pid, ppid, ten, tao, cmd: '', exe: '', ...them });
    const ds = [
      P(10, 1, 'WindowsSandboxRemoteSession.exe', T - 20 * 60000), // cha chết, 20 phút → đóng
      P(11, 1, 'WindowsSandboxRemoteSession.exe', T - 5 * 60000), // mới 5 phút → chưa
      P(20, 1, 'node.exe', T - 30 * 60000, { cmd: 'npm run thu-khach' }), P(21, 20, 'cmd.exe', T - 30 * 60000),
      P(22, 21, 'electron.exe', T - 30 * 60000, { exe: 'E:\\AI\\DuAnG\\app\\node_modules\\electron\\dist\\electron.exe' }), // chuỗi mồ côi → đóng
      P(30, 1, 'explorer.exe', T - 9e6), P(31, 30, 'electron.exe', T - 9e6, { exe: 'E:\\AI\\X\\electron.exe' }), // người dùng mở → không
      P(40, 1, 'node.exe', T - 9e6, { cmd: 'E:\\AI\\TongQuanAI\\cai-dat\\ngam.js giu' }), P(41, 40, 'claude.exe', T - 9e6),
      P(42, 41, 'electron.exe', T - 9e6, { exe: 'E:\\AI\\X\\electron.exe' }), // claude đang chạy → không
      P(50, 1, 'node.exe', T - 9e6), P(51, 50, 'electron.exe', T - 9e6, { exe: 'C:\\Program Files\\App\\electron.exe' }), // ngoài E:\AI → không
      P(60, 1, 'node.exe', T - 9e6), P(61, 60, 'cmd.exe', T - 9e6), // cmd không cửa sổ → không
      P(70, 1, 'svchost.exe', T - 9e6), P(71, 70, 'WindowsSandboxRemoteSession.exe', T - 9e6), // gốc là dịch vụ → không
      P(80, 99, 'cmd.exe', T - 9e6), P(99, 1, 'chrome.exe', T - 1000), // pid cha bị dùng lại (cha mới hơn con) = cha chết → đóng nếu có cửa sổ
    ];
    const m = new Map(ds.map((p) => [p.pid, p])), cs = new Set([80]);
    assert.deepStrictEqual(ds.filter((p) => moCoi(p, m, cs, T)).map((p) => p.pid), [10, 22, 80]);
    console.log('✅ moCoi ok'); return;
  }
  if (cmd === 'kiem-tai') { // tự kiểm hàm quaTai + in số đo hiện tại
    const assert = require('assert'), n = { cpu: 70, chrome: 150, tienTrinh: 1000 };
    assert.strictEqual(quaTai({ cpu: 10, chrome: 5, tienTrinh: 300 }, n), false);
    assert.strictEqual(quaTai({ cpu: 70, chrome: 5, tienTrinh: 300 }, n), true);
    assert.strictEqual(quaTai({ cpu: 10, chrome: 422, tienTrinh: 300 }, n), true);
    assert.strictEqual(quaTai({ cpu: 10, chrome: 5, tienTrinh: 1295 }, n), true);
    doTai(); console.log('✅ quaTai ok · ngưỡng', nguongTai(), '·', readJson(TAI_F)); return;
  }
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
    // "tamDung" ở sổ đội (người dùng cho dự án nghỉ) → không nhận việc mới; xoá trường đó để chạy lại
    const tamDung = v.d.tamDung || v.w.tamDung; // cả đội hoặc 1 vai
    if (tamDung) { console.log(`⏸ ${v.key} đang tạm dừng (${tamDung}) → không nhận việc.`); process.exit(5); }
    const viec = fs.readFileSync(a2, 'utf8').replace(/^\uFEFF/, '').trim();
    const r = khoa(() => {
      const st = docSt(v.key) || {};
      // lượt TỰ LẤY còn trong hàng chờ (chưa chạy) thì việc giao tay thay luôn
      if ((st.trang_thai === 'cho' && !st.tu_lam) || (st.trang_thai === 'chay' && song(st.pid))) return st;
      luuSt(v.key, { ...st, trang_thai: 'cho', viec, giao_luc: now(), bat_dau: null, ket_thuc: null, pid: null, log: null, ket_qua: null, tu: process.env.WEZTERM_PANE || '', tu_lam: false, tu_lam_nghi: null });
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
    else if (claudeHetHan() && aiThat(v.d, v.w) === 'claude') console.log(`⏸ ${v.key} xếp hàng: ${claudeHetHan()}. Tự chạy khi Claude hồi.`);
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
    const het = claudeHetHan(); if (het) console.log(`⏸ Tạm dừng việc Claude mới: ${het} (việc Codex vẫn chạy)`);
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
      if (song(st.pid)) try { cp.execSync(`taskkill /PID ${st.pid} /T /F`, { stdio: 'ignore', windowsHide: true }); } catch {}
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
