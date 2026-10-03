// Đồng bộ công việc mọi dự án lên Linear (team HIO), lấy từ Company Brain (brain\brain.json) — chạy lại bao nhiêu lần cũng không tạo trùng.
//   node linear-sync.js [--thu]     (--thu: chỉ in sẽ làm gì, không gửi)
// Quy tắc:
//   ⏳ "Đang làm" trong tien-do      → ticket cột In Progress · nhãn "Dự án: X"
//   🧱 "Đang kẹt"                    → Todo · nhãn "Kẹt"
//   🔔 việc chờ Hion duyệt (ô 📋)    → Todo · nhãn "Cần Hion" · ưu tiên High
//   Việc đã có ticket mà không còn trong nguồn (đã xong / đã duyệt) → chuyển Done + bình luận.
// Sổ ghi nhớ: %LOCALAPPDATA%\wez-ai\linear-map.json { khoá: { id, cot } }. Key lấy từ 1Password (op://Chatbot/Linear/credential).
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const THU = process.argv.includes('--thu');
const HUB = 'E:\\AI\\Hion';
const MAP = path.join(process.env.LOCALAPPDATA || '.', 'wez-ai', 'linear-map.json');
const TEAM_KEY = 'HIO';
const cut = (s, n) => (s.length > n ? s.slice(0, n - 1).trimEnd() + '…' : s);

function key() {
  const ops = [path.join(process.env.LOCALAPPDATA || '', 'Microsoft', 'WinGet', 'Links', 'op.exe'), 'op'];
  for (const op of ops) {
    if (op !== 'op' && !fs.existsSync(op)) continue;
    try { return execFileSync(op, ['read', 'op://Chatbot/Linear/credential'], { encoding: 'utf8', timeout: 25000, stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch {}
  }
  return null;
}
let K;
async function q(query, variables = {}) {
  const r = await fetch('https://api.linear.app/graphql', { method: 'POST', headers: { Authorization: K, 'Content-Type': 'application/json' }, body: JSON.stringify({ query, variables }) });
  const j = await r.json();
  if (j.errors) throw new Error(j.errors.map((e) => e.message).join('; '));
  return j.data;
}

(async () => {
  // 1) Brain mới nhất
  try { execFileSync('node', [path.join(HUB, 'cai-dat', 'brain.js')], { stdio: 'ignore', timeout: 120000 }); } catch {}
  const b = JSON.parse(fs.readFileSync(path.join(HUB, 'brain', 'brain.json'), 'utf8'));

  // 2) Danh sách việc nên có trên Linear
  const want = [];
  const them = (duAn, loai, text) => {
    const sach = text.replace(/\s+/g, ' ').trim();
    if (!sach || sach === '—') return;
    if (/^(.{0,40})(đã xong|xem mục)/i.test(sach) && sach.length < 80) return; // dòng ghi chú, không phải việc
    const k = crypto.createHash('sha1').update(`${duAn}|${loai}|${sach.slice(0, 80).toLowerCase()}`).digest('hex').slice(0, 16);
    want.push({ k, duAn, loai, title: cut(sach, 120), desc: sach });
  };
  for (const p of b.duAn) {
    for (const x of p.lam) them(p.ten, 'lam', x);
    for (const x of p.ket) them(p.ten, 'ket', x);
  }
  for (const c of b.choDuyet) {
    const m = c.match(/^\[([^\]]+)\]\s*(.*)$/);
    them(m ? m[1] : 'Hion', 'duyet', m ? m[2] : c);
  }

  let map = {};
  try { map = JSON.parse(fs.readFileSync(MAP, 'utf8')); } catch {}
  const moi = want.filter((w) => !map[w.k]);
  const het = Object.entries(map).filter(([k, v]) => !want.some((w) => w.k === k) && v.cot !== 'xong');
  const doiCot = want.filter((w) => map[w.k] && map[w.k].loai !== w.loai);
  console.log(`Nguồn: ${want.length} việc · tạo mới ${moi.length} · chuyển Done ${het.length} · đổi cột ${doiCot.length}`);
  if (THU) { moi.slice(0, 15).forEach((w) => console.log(`  + [${w.duAn}/${w.loai}] ${w.title}`)); return; }

  K = key();
  if (!K) { console.log('⏳ 1Password đang khoá → chưa đồng bộ được (mở khoá rồi chạy lại).'); process.exitCode = 2; return; }

  // 3) Team, cột, nhãn
  const t = (await q('query($k:String!){ teams(filter:{key:{eq:$k}}){ nodes { id states { nodes { id type } } } } }', { k: TEAM_KEY })).teams.nodes[0];
  t.labels = (await q('query{ issueLabels(first:100){ nodes { id name } } }')).issueLabels; // tách riêng: gộp với team bị "Query too complex"
  const cot = { lam: t.states.nodes.find((s) => s.type === 'started').id, ket: t.states.nodes.find((s) => s.type === 'unstarted').id, duyet: t.states.nodes.find((s) => s.type === 'unstarted').id, xong: t.states.nodes.find((s) => s.type === 'completed').id };
  const nhan = Object.fromEntries(t.labels.nodes.map((l) => [l.name, l.id]));
  const lay = async (ten, mau) => {
    if (nhan[ten]) return nhan[ten];
    const r = await q('mutation($i:IssueLabelCreateInput!){ issueLabelCreate(input:$i){ issueLabel { id } } }', { i: { name: ten, teamId: t.id, color: mau } });
    return (nhan[ten] = r.issueLabelCreate.issueLabel.id);
  };
  const UU = { lam: 3, ket: 2, duyet: 2 };

  // 4) Tạo mới
  for (const w of moi) {
    const labels = [await lay(`Dự án: ${w.duAn}`, '#8b5cf6')];
    if (w.loai === 'ket') labels.push(await lay('Kẹt', '#eb5757'));
    if (w.loai === 'duyet') labels.push(await lay('Cần Hion', '#f2c94c'));
    const r = await q('mutation($i:IssueCreateInput!){ issueCreate(input:$i){ issue { identifier } } }',
      { i: { teamId: t.id, title: w.title, description: `${w.desc}\n\n_Tự đồng bộ từ Company Brain (Hion\\brain) — sửa ở file tiến độ của dự án, không sửa ở đây._`, priority: UU[w.loai], stateId: cot[w.loai], labelIds: labels } });
    map[w.k] = { id: r.issueCreate.issue.identifier, loai: w.loai, cot: w.loai };
    console.log(`  + ${r.issueCreate.issue.identifier} [${w.duAn}/${w.loai}] ${cut(w.title, 70)}`);
  }
  // 5) Đổi cột (kẹt ↔ đang làm)
  for (const w of doiCot) {
    await q('mutation($id:String!,$i:IssueUpdateInput!){ issueUpdate(id:$id,input:$i){ success } }', { id: map[w.k].id, i: { stateId: cot[w.loai] } });
    map[w.k].loai = w.loai; map[w.k].cot = w.loai;
    console.log(`  ↔ ${map[w.k].id} → ${w.loai}`);
  }
  // 6) Không còn trong nguồn → Done
  for (const [k, v] of het) {
    try {
      await q('mutation($id:String!,$i:IssueUpdateInput!){ issueUpdate(id:$id,input:$i){ success } }', { id: v.id, i: { stateId: cot.xong } });
      await q('mutation($i:CommentCreateInput!){ commentCreate(input:$i){ success } }', { i: { issueId: v.id, body: `Tự đóng ${new Date().toLocaleString('vi-VN')}: việc không còn trong mục ${v.loai === 'duyet' ? 'chờ duyệt (đã quyết)' : 'Đang làm / Đang kẹt'} của dự án.` } });
      map[k].cot = 'xong';
      console.log(`  ✓ ${v.id} → Done`);
    } catch (e) { console.log(`  ❌ ${v.id}: ${e.message}`); }
  }
  fs.mkdirSync(path.dirname(MAP), { recursive: true });
  fs.writeFileSync(MAP, JSON.stringify(map, null, 2));
  console.log(`✅ Xong. Board: https://linear.app/hionvn/team/${TEAM_KEY}/active`);
})().catch((e) => { console.error('❌', e.message); process.exitCode = 1; });
