// Bàn duyệt của Tổng quản: thêm / duyệt / yêu cầu sửa / bỏ một việc trong E:\AI\Hion\can-duyet.md
// và ghi lại quyết định vào E:\AI\Hion\quyet-dinh.md (sổ quyết định — AI dự án đọc để làm tiếp).
//   node duyet.js list                          # xem việc đang chờ (số thứ tự + mã)
//   node duyet.js them <dự án> "câu hỏi"        # AI thêm việc cần người dùng quyết
//   node duyet.js ok   <số|mã> [ghi chú]        # ✅ duyệt
//   node duyet.js sua  <số|mã> "yêu cầu"        # ✏️ trả lời / yêu cầu làm khác
//   node duyet.js bo   <số|mã> [lý do]          # ❌ bỏ, không làm
//   node duyet.js json                          # cho ô 📋 vẽ nút bấm
// Nút trong ô 📋 (can-duyet-view.ps1) là link wezai-duyet:<việc>/<mã>; ~/.wezterm.lua bắt link đó và gọi file này.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function aiRoot() {
  try {
    const c = JSON.parse(fs.readFileSync(path.join(process.env.USERPROFILE || '', '.wez-ai.json'), 'utf8').replace(/^\uFEFF/, ''));
    if (c.aiRoot) return c.aiRoot;
  } catch (_) { }
  return 'E:\\AI';
}
const HUB = path.join(aiRoot(), 'Hion');
const FILE = path.join(HUB, 'can-duyet.md');
const LOG = path.join(HUB, 'quyet-dinh.md');
const HEAD_CHO = '## Đang chờ';
const HEAD_XONG = '## Đã xử lý';
const VERB = { ok: '✅ Duyệt', sua: '✏️ Yêu cầu sửa', bo: '❌ Bỏ' };

const pad = (n) => String(n).padStart(2, '0');
const now = new Date();
const ngay = `${pad(now.getDate())}/${pad(now.getMonth() + 1)}`;
const gio = `${pad(now.getHours())}:${pad(now.getMinutes())}`;

function read() {
  if (!fs.existsSync(FILE)) {
    return `# Cần duyệt\n\nViệc đang chờ người dùng (CEO) quyết định.\n\n${HEAD_CHO}\n\n${HEAD_XONG}\n`;
  }
  return fs.readFileSync(FILE, 'utf8').replace(/^\uFEFF/, '').replace(/\r\n/g, '\n');
}
function write(text) { fs.writeFileSync(FILE, text, 'utf8'); }

// Việc đang chờ = mỗi dòng "- ..." trong mục "Đang chờ" (dòng thụt vào bên dưới là chi tiết của việc đó)
function pending(text) {
  const lines = text.split('\n');
  const start = lines.findIndex((l) => l.trim() === HEAD_CHO);
  if (start < 0) return { lines, items: [], start };
  const items = [];
  for (let i = start + 1; i < lines.length && !/^#{1,2} /.test(lines[i]); i++) {
    const l = lines[i];
    if (/^- /.test(l)) {
      const body = l.slice(2).trim();
      const m = body.match(/^\[([^\]]+)\]\s*(.*)$/);
      items.push({
        n: items.length + 1, line: i, end: i,
        id: crypto.createHash('sha1').update(body).digest('hex').slice(0, 6),
        proj: m ? m[1] : '', text: m ? m[2] : body, raw: body,
      });
    } else if (items.length && /^\s+\S/.test(l)) {
      items[items.length - 1].end = i;
    }
  }
  return { lines, items, start };
}

function find(items, key) {
  const k = String(key || '').trim();
  return items.find((it) => it.id === k || String(it.n) === k);
}

function decide(verb, key, note) {
  const text = read();
  const { lines, items } = pending(text);
  const it = find(items, key);
  if (!it) {
    console.error(`Không thấy việc "${key}" trong mục Đang chờ (có thể đã được xử lý). Xem: node duyet.js list`);
    process.exit(1);
  }
  if (verb === 'sua' && !note) { console.error('Yêu cầu sửa cần ghi nội dung.'); process.exit(1); }
  const tag = it.proj ? `[${it.proj}] ` : '';
  const done = `- ${VERB[verb]} ${ngay} · ${tag}${it.text}${note ? ` — **${note}**` : ''}`;
  lines.splice(it.line, it.end - it.line + 1);
  let x = lines.findIndex((l) => l.trim() === HEAD_XONG);
  if (x < 0) { lines.push('', HEAD_XONG); x = lines.length - 1; }
  lines.splice(x + 1, 0, done); // mới nhất lên đầu
  write(lines.join('\n'));

  if (!fs.existsSync(LOG)) {
    fs.writeFileSync(LOG, '# Sổ quyết định\n\nNgười dùng duyệt ở ô 📋 / qua Tổng quản → ghi tự động tại đây (mới nhất ở cuối).\n' +
      'AI dự án: trước khi làm tiếp việc đã hỏi, tìm dòng có [tên dự án] của mình.\n\n', 'utf8');
  }
  const yyyy = now.getFullYear();
  fs.appendFileSync(LOG, `- ${ngay}/${yyyy} ${gio} · ${tag}${VERB[verb]} · ${it.text}${note ? ` → ${note}` : ''}\n`, 'utf8');
  console.log(`${VERB[verb]}: ${tag}${it.text.slice(0, 80)}`);
}

const [cmd = 'list', a, ...rest] = process.argv.slice(2);
switch (cmd) {
  case 'list': {
    const { items } = pending(read());
    if (!items.length) { console.log('✅ Không có việc nào đang chờ duyệt.'); break; }
    for (const it of items) console.log(`${it.n}. (${it.id}) ${it.proj ? `[${it.proj}] ` : ''}${it.text}`);
    break;
  }
  case 'json': {
    const { items } = pending(read());
    process.stdout.write(JSON.stringify(items.map(({ n, id, proj, text }) => ({ n, id, proj, text }))));
    break;
  }
  case 'them': {
    const q = rest.join(' ').trim();
    if (!a || !q) { console.error('Cách dùng: node duyet.js them <dự án> "câu hỏi"'); process.exit(1); }
    const text = read();
    const { lines, items, start } = pending(text);
    let at;
    if (start < 0) { lines.push('', HEAD_CHO); at = lines.length; }
    else at = items.length ? items[items.length - 1].end + 1 : start + 1;
    lines.splice(at, 0, `- [${a}] ${q}`);
    write(lines.join('\n'));
    console.log(`📥 Đã thêm vào Cần duyệt: [${a}] ${q.slice(0, 80)}`);
    break;
  }
  case 'ok': case 'sua': case 'bo':
    decide(cmd, a, rest.join(' ').trim());
    break;
  default:
    console.error('Lệnh: list | them | ok | sua | bo | json');
    process.exit(1);
}
