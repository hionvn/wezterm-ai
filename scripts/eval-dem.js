// Eval đội agent theo ngày (phần SỐ — đo được, không đoán). Tổng quản bổ sung phần nhận xét lúc tổng kết ca đêm.
// Dùng: node eval-dem.js [YYYY-MM-DD]   (mặc định: hôm qua nếu trước 12 giờ trưa, không thì hôm nay)
// Đọc %LOCALAPPDATA%\wez-ai\viec.json (mọi việc giao qua wez.ps1 send/giao) trong khung 12:00 ngày đó → 12:00 hôm sau.
// Ghi: E:\AI\Hion\learn\so-lieu-<ngày>.json + E:\AI\Hion\learn\eval-<ngày>.md (phần số; không ghi đè phần nhận xét nếu đã có)
const fs = require('fs');
const path = require('path');

const HUB = 'E:\\AI\\Hion';
const LEARN = path.join(HUB, 'learn');
const VIEC = path.join(process.env.LOCALAPPDATA || '', 'wez-ai', 'viec.json');

function ngayMacDinh() {
  const d = new Date();
  if (d.getHours() < 12) d.setDate(d.getDate() - 1);
  return d.toLocaleDateString('sv-SE'); // YYYY-MM-DD theo giờ máy
}
const ngay = process.argv[2] || ngayMacDinh();
if (!/^\d{4}-\d{2}-\d{2}$/.test(ngay)) { console.error('Ngày phải dạng YYYY-MM-DD'); process.exit(1); }
const tu = new Date(`${ngay}T12:00:00`).getTime() / 1000;
const den = tu + 24 * 3600;

let viec = [];
try { viec = JSON.parse(fs.readFileSync(VIEC, 'utf8').replace(/^\uFEFF/, '')); } catch { console.error('Không đọc được', VIEC); }
if (!Array.isArray(viec)) viec = viec && viec.value ? viec.value : [];
const trong = viec.filter((v) => v && v.t >= tu && v.t < den);

const theoAi = {};
for (const v of trong) {
  const k = v.ai || `ô ${v.o}`;
  const a = (theoAi[k] ||= { giao: 0, xong: 0, bo: 0, dang: 0, phut: [] });
  a.giao++;
  if (v.bo) a.bo++;
  else if (v.xong) { a.xong++; a.phut.push((v.xong - v.t) / 60); }
  else a.dang++;
}
const tb = (xs) => (xs.length ? Math.round(xs.reduce((s, x) => s + x, 0) / xs.length) : null);
const hang = Object.entries(theoAi)
  .map(([ai, a]) => ({ ai, ...a, phut_tb: tb(a.phut), ti_le_xong: a.giao ? Math.round((100 * a.xong) / a.giao) : 0 }))
  .sort((x, y) => y.giao - x.giao);
const tong = hang.reduce((s, h) => ({ giao: s.giao + h.giao, xong: s.xong + h.xong, bo: s.bo + h.bo, dang: s.dang + h.dang }), { giao: 0, xong: 0, bo: 0, dang: 0 });

fs.mkdirSync(LEARN, { recursive: true });
const soLieu = { ngay, khung: '12:00 → 12:00 hôm sau', tong, agent: hang.map(({ phut, ...h }) => h) };
fs.writeFileSync(path.join(LEARN, `so-lieu-${ngay}.json`), JSON.stringify(soLieu, null, 2));

const bang = [
  `## Số liệu (tự đo từ viec.json, ${new Date().toLocaleString('vi-VN')})`,
  `Tổng: giao **${tong.giao}** · xong **${tong.xong}** · bỏ ${tong.bo} · còn dở ${tong.dang}`,
  '',
  '| Agent | Giao | Xong | Tỉ lệ xong | Phút TB/việc | Bỏ | Còn dở |',
  '|---|---:|---:|---:|---:|---:|---:|',
  ...hang.map((h) => `| ${h.ai} | ${h.giao} | ${h.xong} | ${h.ti_le_xong}% | ${h.phut_tb ?? '—'} | ${h.bo} | ${h.dang} |`),
  '',
].join('\n');
const MO = '<!-- so-lieu:bat-dau -->';
const DONG = '<!-- so-lieu:het -->';
const f = path.join(LEARN, `eval-${ngay}.md`);
let cu = fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : '';
const khoi = `${MO}\n${bang}${DONG}`;
if (cu.includes(MO)) cu = cu.replace(new RegExp(`${MO}[\\s\\S]*?${DONG}`), khoi);
else cu = `# Eval đội agent — ${ngay}\n\n${khoi}\n\n## Nhận xét (Tổng quản điền lúc tổng kết)\n- Đúng đề / bị trả lại / lỗi lặp từng agent:\n- Bài học mới (ghi thêm vào bai-hoc.md):\n`;
fs.writeFileSync(f, cu);
console.log(`✅ Eval ${ngay}: giao ${tong.giao} · xong ${tong.xong} · bỏ ${tong.bo} · dở ${tong.dang} → ${f}`);
