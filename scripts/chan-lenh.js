#!/usr/bin/env node
// Chặn lệnh nguy hiểm trước khi Claude chạy (hook PreToolUse — cách thầy Sơn: always approve + script lọc).
//   PreToolUse (Bash|PowerShell|mcp gửi ra ngoài) → node chan-lenh.js hook
// 3 mức:
//   ⛔ CẤM   — luôn chặn (xoá cả ổ / cả dự án, push --force, xoá DB, công khai repo, publish gói…)
//   🌙 ĐÊM   — 22:00 → 06:30 chặn (push, deploy, merge PR, gửi email…); ban ngày thì hỏi người dùng
//   Còn lại cho chạy.
// Mở tạm cho việc ĐÊM (vd "tổng kết" sau 22h) — NGƯỜI DÙNG tự gõ trong ô Claude:
//   ! node E:\AI\Hion\cai-dat\chan-lenh.js mo 30      (mở 30 phút; agent tự chạy lệnh này sẽ bị chặn)
//   ! node E:\AI\Hion\cai-dat\chan-lenh.js dong
// Thử: node chan-lenh.js thu "git push origin main"
// Nhật ký chặn: %LOCALAPPDATA%\wez-ai\chan-lenh.log
// Đây là lan can, không phải bảo mật tuyệt đối: lệnh viết vòng (script trong file) vẫn lọt.
const fs = require('fs');
const path = require('path');

const base = path.join(process.env.LOCALAPPDATA || '', 'wez-ai');
const MO = path.join(base, 'chan-lenh-mo.json');
const LOG = path.join(base, 'chan-lenh.log');

// Thư mục gốc không bao giờ được xoá cả cụm.
const GOC = String.raw`(?:[a-z]:[\\/]?|~[\\/]?|\$home[\\/]?|\$env:userprofile[\\/]?|/|/[a-z]/?|[a-z]:[\\/]ai[\\/]?(?:[\w.-]+[\\/]?)?|/[a-z]/ai/?(?:[\w.-]+/?)?|c:[\\/]users[\\/][^\\/\s"']+[\\/]?)`;
const HET = String.raw`(?=["'\s;|&)]|$)`;

const CAM = [
  [new RegExp(String.raw`\brm\s+(?:-[a-z]*r[a-z]*f?|-[a-z]*f[a-z]*r|--recursive)\b[^;|&]*?\s["']?${GOC}["']?\*?${HET}`, 'i'), 'xoá cả ổ đĩa / thư mục nhà / cả thư mục dự án'],
  [new RegExp(String.raw`\b(?:remove-item|rm|ri|del|rmdir|rd)\b[^;|&]*?\s-?["']?${GOC}["']?\*?${HET}[^;|&]*-r(?:ecurse)?\b`, 'i'), 'xoá cả ổ đĩa / thư mục nhà / cả thư mục dự án'],
  [new RegExp(String.raw`\b(?:remove-item|rm|ri)\b[^;|&]*-r(?:ecurse)?\b[^;|&]*?\s["']?${GOC}["']?\*?${HET}`, 'i'), 'xoá cả ổ đĩa / thư mục nhà / cả thư mục dự án'],
  [/\b(?:rd|rmdir)\s+\/s\b[^;|&]*\s["']?[a-z]:[\\/]?(?:ai[\\/]?(?:[\w.-]+[\\/]?)?)?["']?(?=\s|$)/i, 'xoá cả ổ đĩa / thư mục dự án'],
  [/\b(?:format(?:-volume)?\s+[a-z]:|clear-disk|initialize-disk|diskpart|mkfs|dd\s+if=)/i, 'định dạng / ghi đè ổ đĩa'],
  [/\bgit\s+push\b[^;|&]*(?:\s--force(?!-with-lease)\b|\s-f\b|\s\+\S)/i, 'git push --force (ghi đè lịch sử trên GitHub)'],
  [/\bgit\s+push\b[^;|&]*\s(?:--delete|-d)\b/i, 'xoá nhánh trên GitHub'],
  [/\bgh\s+repo\s+(?:delete|archive)\b/i, 'xoá / lưu trữ repo GitHub'],
  [/\bgh\s+repo\s+(?:edit|create)\b[^;|&]*(?:--visibility[\s=]+public|--public)\b/i, 'đổi / tạo repo công khai (chưa được người dùng đồng ý)'],
  [/\bgh\s+api\b[^;|&]*-X\s*DELETE\b/i, 'gọi API GitHub để xoá'],
  [/\b(?:drop\s+(?:table|database|schema)|truncate\s+(?:table\s+)?\w)/i, 'xoá bảng / database'],
  [/\bdelete\s+from\s+\w+\s*(?:;|"|'|$)/i, 'xoá toàn bộ dữ liệu một bảng (DELETE không có WHERE)'],
  [/\bsupabase\s+(?:db\s+reset|projects\s+delete)\b/i, 'reset / xoá database Supabase'],
  [/\b(?:npm|pnpm|yarn)\s+publish\b/i, 'đăng gói công khai lên npm'],
  [/\bvercel\s+(?:remove|rm|projects\s+rm|domains\s+rm)\b/i, 'xoá dự án / tên miền trên Vercel'],
  [/\bgit\s+clean\s+-[a-z]*f[a-z]*x/i, 'git clean -x (xoá cả file bị .gitignore — .env, dữ liệu)'],
  [/\breg(?:\.exe)?\s+delete\b|\bremove-item\b[^;|&]*\b(?:hklm|hkcu):/i, 'xoá registry Windows'],
  [/\b(?:stop-computer|restart-computer|shutdown(?:\.exe)?\s+[\/-][srp])\b/i, 'tắt / khởi động lại máy'],
  [/chan-lenh(?:\.js)?\s+mo\b|chan-lenh-mo\.json/i, 'tự mở khoá chặn lệnh (chỉ người dùng được mở)'],
];

const DEM = [
  [/\bgit\s+push\b/i, 'git push (đẩy code lên GitHub)'],
  [/\bgh\s+(?:pr\s+merge|release\s+create|workflow\s+run)\b/i, 'merge PR / phát hành trên GitHub'],
  [/\bvercel\b[^;|&]*(?:--prod\b|\bdeploy\b|\bpromote\b)|\bvercel\s*(?:$|;|&|\|)/i, 'deploy Vercel'],
  [/\b(?:netlify|firebase|wrangler|fly|railway)\s+deploy\b/i, 'deploy'],
  [/\bsupabase\s+(?:db\s+push|migration\s+up|functions\s+deploy)\b/i, 'đổi cấu trúc database / deploy Supabase'],
  [/\bsend-mailmessage\b/i, 'gửi email'],
];

// Công cụ MCP gửi ra ngoài / xoá (không có lệnh để soi — chặn theo tên công cụ).
const MCP_CAM = [
  [/__(?:trash_file|delete_label)$/i, 'xoá file / nhãn trên Google'],
];
const MCP_DEM = [
  [/Gmail__(?:send_message|reply|forward)$/i, 'gửi email'],
  [/Drive__share_file$/i, 'chia sẻ file Google Drive ra ngoài'],
];

function laDem(d = new Date()) {
  const p = d.getHours() * 60 + d.getMinutes();
  return p >= 22 * 60 || p < 6 * 60 + 30;
}
function dangMo() {
  try { return JSON.parse(fs.readFileSync(MO, 'utf8')).den > Date.now(); } catch { return false; }
}
function ghiLog(muc, ly, lenh) {
  try {
    fs.mkdirSync(base, { recursive: true });
    const t = new Date().toLocaleString('vi-VN');
    fs.appendFileSync(LOG, `${t}\t${muc}\t${process.env.WEZTERM_PANE || '-'}\t${ly}\t${String(lenh).slice(0, 300).replace(/\s+/g, ' ')}\n`);
  } catch {}
}

// Trả { muc: 'cam'|'dem'|'hoi'|null, ly }
function xet(tool, lenh) {
  const timTrong = (ds, s) => { for (const [re, ly] of ds) if (re.test(s)) return ly; return null; };
  let cam, dem;
  if (/^mcp__/.test(tool)) { cam = timTrong(MCP_CAM, tool); dem = timTrong(MCP_DEM, tool); }
  else { cam = timTrong(CAM, lenh); dem = timTrong(DEM, lenh); }
  if (cam) return { muc: 'cam', ly: cam };
  if (dem) {
    if (dangMo()) return { muc: null, ly: dem };
    return laDem() ? { muc: 'dem', ly: dem } : { muc: 'hoi', ly: dem };
  }
  return { muc: null };
}

function traLoi(quyet, lyDo) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: quyet, permissionDecisionReason: lyDo },
  }));
}

const [cmd, a1] = process.argv.slice(2);
if (cmd === 'hook') {
  let input = '';
  process.stdin.on('data', (c) => (input += c));
  process.stdin.on('end', () => {
    let data = {};
    try { data = JSON.parse(input.replace(/^\uFEFF/, '')); } catch { return; }
    const tool = data.tool_name || '';
    const lenh = (data.tool_input && data.tool_input.command) || '';
    const { muc, ly } = xet(tool, lenh);
    if (!muc) return;
    ghiLog(muc, ly, lenh || tool);
    if (muc === 'cam') {
      traLoi('deny', `⛔ Chặn cứng: ${ly}. Lệnh này không bao giờ được AI tự chạy. ` +
        'Nếu thật sự cần: ghi vào bàn duyệt (node E:\\AI\\Hion\\cai-dat\\duyet.js them <dự án> "…") để người dùng tự làm tay, rồi làm việc khác.');
    } else if (muc === 'dem') {
      traLoi('deny', `🌙 Ca đêm (22:00–06:30) không được: ${ly}. Ghi vào bàn duyệt (duyet.js them) để sáng người dùng bấm, rồi làm việc kế tiếp — đừng đứng chờ, đừng tìm đường vòng.`);
    } else {
      traLoi('ask', `🔴 ${ly} — việc gửi ra ngoài, cần người dùng đồng ý.`);
    }
  });
} else if (cmd === 'mo') {
  const phut = Math.min(Math.max(parseInt(a1, 10) || 30, 1), 240);
  fs.mkdirSync(base, { recursive: true });
  fs.writeFileSync(MO, JSON.stringify({ den: Date.now() + phut * 60000 }));
  console.log(`🔓 Mở việc ĐÊM (push, deploy, gửi email…) trong ${phut} phút — ban ngày vẫn hỏi. Lệnh CẤM vẫn chặn.`);
} else if (cmd === 'dong') {
  try { fs.unlinkSync(MO); } catch {}
  console.log('🔒 Đã đóng lại.');
} else if (cmd === 'cai-codex') {
  // Chép chan-lenh-codex.rules vào rules\default.rules của mọi CODEX_HOME (~\.codex*), thay khối cũ nếu có.
  const home = process.env.USERPROFILE || '';
  const khoi = fs.readFileSync(path.join(__dirname, 'chan-lenh-codex.rules'), 'utf8').trim() + '\n';
  const KHOI_CU = /# === chan-lenh[\s\S]*?# === hết chan-lenh ===\r?\n?/;
  for (const d of fs.readdirSync(home)) {
    if (!/^\.codex(?:-tk\d+)?$/.test(d) || !fs.existsSync(path.join(home, d, 'config.toml'))) continue;
    const f = path.join(home, d, 'rules', 'default.rules');
    fs.mkdirSync(path.dirname(f), { recursive: true });
    let cu = ''; try { cu = fs.readFileSync(f, 'utf8'); } catch {}
    cu = cu.replace(KHOI_CU, '').replace(/\s*$/, '');
    fs.writeFileSync(f, (cu ? cu + '\n' : '') + khoi);
    console.log('✅ ' + f);
  }
} else if (cmd === 'thu') {
  const lenh = process.argv.slice(3).join(' ');
  const r = xet(/^mcp__/.test(lenh) ? lenh : 'Bash', lenh);
  console.log({ cam: '⛔ CẤM', dem: '🌙 CHẶN (đêm)', hoi: '❓ HỎI (ngày)' }[r.muc] || '✅ cho chạy', r.ly ? '— ' + r.ly : '');
} else {
  console.log('Dùng: chan-lenh.js hook | mo [phút] | dong | thu "<lệnh>"');
}
