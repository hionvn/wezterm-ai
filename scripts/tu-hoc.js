// tu-hoc.js — vòng tự học của đội worker (23/10/2026, người dùng: "làm vòng tự học").
// Mỗi tối (brain-chay.ps1 lượt 21:55): đọc kết quả worker trong ngày theo dự án → 1 lượt Codex qua 9router (miễn phí)
// rút bài học lặp lại → ghi learn\bai-hoc\<DựÁn>.md (ngam.js kèm vào lời giao việc của đúng vai) + đề xuất sửa
// skill/AGENTS/brief vào learn\de-xuat-<DựÁn>-<ngày>.md và bàn duyệt (sửa file thì người dùng duyệt, bài học thì nạp luôn).
// Dùng: node tu-hoc.js [yyyymmdd] [--du-an DuAnG] [--thu]   (--thu: in dữ liệu gom được, không gọi AI, không ghi)
const fs = require('fs'), path = require('path'), os = require('os');
const { spawnSync } = require('child_process');

const HUB = path.resolve(__dirname, '..');
const KQ = path.join(process.env.LOCALAPPDATA || '', 'wez-ai', 'ngam', 'ket-qua');
const LEARN = path.join(HUB, 'learn');
const CODEX = path.join(process.env.APPDATA || '', 'npm', 'node_modules', '@openai', 'codex', 'bin', 'codex.js');
const TOI_DA_BAI = 40; // mỗi dự án giữ 40 bài học mới nhất

const a = process.argv.slice(2);
const ngay = a.find((x) => /^\d{8}$/.test(x)) || new Date().toLocaleDateString('sv-SE').replace(/-/g, '');
const chiDuAn = a.includes('--du-an') ? a[a.indexOf('--du-an') + 1] : '';
const thu = a.includes('--thu');

// Gom phần đáng học của từng file kết quả: tiêu đề + dòng lỗi/kẹt/còn lại/bài học (không lấy cả file — tiết kiệm token).
const DANG_HOC = /⛔|lỗi|kẹt|sai|chặn|thất bại|không (được|chạy|qua)|đỏ|bài học|còn lại|đã tự chọn|làm lại|vì sao/i;
function gom() {
  const theoDuAn = {};
  let ds = [];
  try { ds = fs.readdirSync(KQ).filter((f) => f.includes(`-${ngay}-`) && f.endsWith('.md')); } catch {}
  for (const f of ds) {
    const m = /^([^.]+)\.([^-]+)-/.exec(f);
    if (!m || (chiDuAn && m[1] !== chiDuAn)) continue;
    const dong = fs.readFileSync(path.join(KQ, f), 'utf8').split(/\r?\n/);
    const tieuDe = dong[0] || '';
    const hoc = dong.slice(1).filter((l) => DANG_HOC.test(l) && !l.startsWith('- Việc:')).map((l) => l.trim().slice(0, 240)).slice(0, 8);
    if (!hoc.length && !tieuDe.includes('⛔')) continue;
    (theoDuAn[m[1]] ||= []).push({ vai: m[2], txt: `## ${m[2]} · ${tieuDe.replace(/^#\s*/, '')}\n${hoc.join('\n')}` });
  }
  // Mỗi vai lấy 4 kết quả mới nhất (tên file có giờ → sắp xếp theo tên) để 1 vai chạy 100 lượt không lấn hết chỗ.
  for (const k of Object.keys(theoDuAn)) {
    const dem = {};
    theoDuAn[k] = theoDuAn[k].reverse().filter((x) => (dem[x.vai] = (dem[x.vai] || 0) + 1) <= 4).map((x) => x.txt);
  }
  return theoDuAn;
}

const fileBaiHoc = (duAn) => path.join(LEARN, 'bai-hoc', `${duAn}.md`);
const docBaiHoc = (duAn) => { try { return fs.readFileSync(fileBaiHoc(duAn), 'utf8'); } catch { return ''; } };

function hoiAI(duAn, phan, cu) {
  const de = `Bạn là bộ phận tự học của đội AI dự án ${duAn}. Dưới đây là trích kết quả các worker hôm nay (${ngay}).
Bài học ĐÃ CÓ (không lặp lại):\n${cu.slice(-4000) || '(chưa có)'}\n
Nhiệm vụ: tìm lỗi/kẹt LẶP LẠI hoặc tốn thời gian mà một câu dặn trước có thể tránh. Trả lời DUY NHẤT 1 khối JSON:
{"bai_hoc":[{"vai":"<tên vai hoặc *>","noi_dung":"<câu dặn ngắn, cụ thể, làm gì / tránh gì, ≤ 200 ký tự>"}],
 "de_xuat":[{"file":"<đường dẫn skill/AGENTS/brief nên sửa>","sua":"<sửa gì, ≤ 300 ký tự>","vi_sao":"<bằng chứng hôm nay>"}]}
Tối đa 6 bài học, 3 đề xuất. Không có gì đáng học thì trả mảng rỗng. Không bịa — chỉ dựa trên trích dưới đây.\n\n${phan.join('\n\n').slice(0, 30000)}`;
  const ra = path.join(os.tmpdir(), `tu-hoc-${duAn}-${ngay}.txt`);
  const r = spawnSync(process.execPath, [CODEX, 'exec', '-p', 'router', '-s', 'read-only', '--skip-git-repo-check', '-o', ra, '-'],
    { input: de, encoding: 'utf8', timeout: 15 * 60e3, windowsHide: true, cwd: path.join(path.dirname(HUB), duAn) });
  let txt = ''; try { txt = fs.readFileSync(ra, 'utf8'); } catch { txt = r.stdout || ''; }
  const m = /\{[\s\S]*\}/.exec(txt);
  if (!m) throw new Error(`AI không trả JSON (mã ${r.status}): ${String(r.stderr || txt).slice(-300)}`);
  return JSON.parse(m[0]);
}

function nap(duAn, kq) {
  const moi = (kq.bai_hoc || []).filter((b) => b && b.noi_dung).map((b) => `- [${String(b.vai || '*').replace(/^.*\./, '').replace(/[\]\n]/g, '')}] ${String(b.noi_dung).replace(/\n/g, ' ').slice(0, 240)} (${ngay})`);
  if (moi.length) {
    const cu = docBaiHoc(duAn).split(/\r?\n/).filter((l) => l.startsWith('- ['));
    const tat = [...cu, ...moi].slice(-TOI_DA_BAI);
    fs.mkdirSync(path.dirname(fileBaiHoc(duAn)), { recursive: true });
    fs.writeFileSync(fileBaiHoc(duAn), `# Bài học đội ${duAn} (tu-hoc.js tự rút mỗi tối; ngam.js kèm vào lời giao việc của đúng vai)\n\n${tat.join('\n')}\n`);
  }
  const dx = (kq.de_xuat || []).filter((d) => d && d.sua);
  if (dx.length) {
    const f = path.join(LEARN, `de-xuat-${duAn}-${ngay}.md`);
    fs.writeFileSync(f, `# Đề xuất tự học ${duAn} · ${ngay}\n\n${dx.map((d, i) => `${i + 1}. **${d.file}** — ${d.sua}\n   - Vì sao: ${d.vi_sao || ''}`).join('\n')}\n`);
    spawnSync(process.execPath, [path.join(__dirname, 'duyet.js'), 'them', duAn,
      `Vòng tự học ${ngay}: ${dx.length} đề xuất sửa skill/luật — xem ${f}. Gợi ý: ✅ để Tổng quản áp dụng.`], { windowsHide: true });
  }
  return { moi: moi.length, de_xuat: dx.length };
}

const theoDuAn = gom();
if (thu) { for (const [k, v] of Object.entries(theoDuAn)) console.log(`== ${k}: ${v.length} kết quả đáng học\n${v.slice(0, 3).join('\n\n')}\n`); process.exit(0); }
const tong = [];
for (const [duAn, phan] of Object.entries(theoDuAn)) {
  try { const r = nap(duAn, hoiAI(duAn, phan, docBaiHoc(duAn))); tong.push(`${duAn}: +${r.moi} bài học, ${r.de_xuat} đề xuất (${phan.length} kết quả)`); }
  catch (e) { tong.push(`${duAn}: LỖI ${e.message}`); }
}
const log = `[${new Date().toLocaleString('vi-VN')}] ${ngay} · ${tong.join(' · ') || 'không có kết quả nào'}`;
fs.mkdirSync(LEARN, { recursive: true });
fs.appendFileSync(path.join(LEARN, 'tu-hoc.log'), log + '\n');
console.log(log);
