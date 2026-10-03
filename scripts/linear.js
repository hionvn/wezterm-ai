// Linear 2 chiều cho đội agent (cách thầy Sơn, 03/10/2026): Spec/brief → ticket ngắn → Project theo sản phẩm → agent theo vai.
// Mỗi ticket = 1 việc thật có "Xong khi"; trạng thái dự án KHÔNG để trên Linear (đọc tien-do). Cột: Todo → In Progress → In Review → Done.
// Key lấy từ 1Password lúc chạy (op://Chatbot/Linear/credential), không ghi ra file / màn hình.
// 1Password đang khoá (ban đêm không ai mở) → lệnh ghi vào hàng chờ %LOCALAPPDATA%\wez-ai\linear-hang-doi.json, "dong-bo" chạy lại sau.
//   node linear.js tao <DựÁn> "tiêu đề ngắn" ["mô tả"] [--vai Engineer] [--xong-khi "bằng chứng"] [--brief <file>] [--dem]
//                       [--uu-tien 1-4] [--cot todo|dang|xong]   → in mã HIO-x (tự vào project + cycle tuần này)
//   node linear.js dang <HIO-x>             → In Progress
//   node linear.js soat <HIO-x> ["ghi chú"]  → In Review (làm xong, chờ soát độc lập — người làm không tự duyệt)
//   node linear.js xong <HIO-x> ["ghi chú"]  → Done (+ bình luận bằng chứng)
//   node linear.js ds [DựÁn]                → ticket chưa xong, theo project
//   node linear.js dong-bo                  → chạy lại hàng chờ
// Vai (1 nhãn / ticket = người làm): Manager · Engineer · Design · Marketing · Kiểm soát · Bot · Số liệu · Nội dung · Săn · Chấm điểm · Quảng cáo
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const TEAM_KEY = 'HIO';
const HANG = path.join(process.env.LOCALAPPDATA || '.', 'wez-ai', 'linear-hang-doi.json');
const COT = { todo: 'unstarted', dang: 'started', xong: 'completed' };
// Project theo sản phẩm (tạo 03/10/2026). Hion + wezterm-ai chung project hệ thống.
const PROJECT = { Chatbot: '💬 Chatbot', Sino: '🛏️ Sino', Coolguy: '💈 Coolguy', Aff: '🎯 Aff Radar', '1Bill': '💰 1Bill', Hion: '👑 Hệ thống đội AI', 'wezterm-ai': '👑 Hệ thống đội AI' };

// Bash của agent thường thiếu thư mục WinGet trong PATH → thử thêm đường dẫn cài mặc định của op
const OP = [process.env.LOCALAPPDATA && path.join(process.env.LOCALAPPDATA, 'Microsoft', 'WinGet', 'Links', 'op.exe'), 'op'].filter(Boolean);
function key() {
  for (const op of OP) {
    if (op !== 'op' && !fs.existsSync(op)) continue;
    try {
      return execFileSync(op, ['read', 'op://Chatbot/Linear/credential'], { encoding: 'utf8', timeout: 25000, stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    } catch {}
  }
  return null;
}
let K = null;
async function q(query, variables = {}) {
  const r = await fetch('https://api.linear.app/graphql', {
    method: 'POST', headers: { Authorization: K, 'Content-Type': 'application/json' }, body: JSON.stringify({ query, variables }),
  });
  const j = await r.json();
  if (j.errors) throw new Error(j.errors.map((e) => e.message).join('; '));
  return j.data;
}
function xepHang(args) {
  let ds = [];
  try { ds = JSON.parse(fs.readFileSync(HANG, 'utf8')); } catch {}
  ds.push({ t: new Date().toISOString(), args });
  fs.mkdirSync(path.dirname(HANG), { recursive: true });
  fs.writeFileSync(HANG, JSON.stringify(ds, null, 2));
  console.log(`⏳ 1Password đang khoá → xếp hàng (${ds.length} lệnh chờ). Sáng chạy: node linear.js dong-bo`);
}
async function team() {
  const d = await q('query($k:String!){ teams(filter:{key:{eq:$k}}){ nodes { id activeCycle { id } states { nodes { id name type } } } } }', { k: TEAM_KEY });
  return d.teams.nodes[0];
}
async function nhanTen(ten) {
  const d = await q('query($n:String!){ issueLabels(filter:{name:{eq:$n}}){ nodes { id } } }', { n: ten });
  return d.issueLabels.nodes[0] ? d.issueLabels.nodes[0].id : null;
}
async function projectId(duAn) {
  const ten = PROJECT[duAn]; if (!ten) return null;
  const d = await q('query($n:String!){ projects(filter:{name:{eq:$n}}){ nodes { id } } }', { n: ten });
  return d.projects.nodes[0] ? d.projects.nodes[0].id : null;
}
async function nhanDuAn(teamId, duAn) {
  const ten = `Dự án: ${duAn}`;
  const d = await q('query($n:String!){ issueLabels(filter:{name:{eq:$n}}){ nodes { id } } }', { n: ten });
  if (d.issueLabels.nodes[0]) return d.issueLabels.nodes[0].id;
  const c = await q('mutation($i:IssueLabelCreateInput!){ issueLabelCreate(input:$i){ issueLabel { id } } }', { i: { name: ten, teamId, color: '#8b5cf6' } });
  return c.issueLabelCreate.issueLabel.id;
}
function opt(args, ten, mac) { const i = args.indexOf(ten); if (i < 0) return mac; const v = args[i + 1]; args.splice(i, 2); return v; }

async function chay(args) {
  const lenh = args[0];
  if (lenh === 'tao') {
    const a = args.slice(1);
    const uu = Number(opt(a, '--uu-tien', 3)); const cot = opt(a, '--cot', 'todo');
    const vai = opt(a, '--vai', null); const xongKhi = opt(a, '--xong-khi', null); const brief = opt(a, '--brief', null);
    const iDem = a.indexOf('--dem'); const dem = iDem >= 0; if (dem) a.splice(iDem, 1);
    const [duAn, tieuDe, moTa = ''] = a;
    if (!duAn || !tieuDe) throw new Error('Thiếu <DựÁn> "tiêu đề"');
    const t = await team();
    const stateId = t.states.nodes.find((s) => s.type === COT[cot])?.id;
    const labelIds = [await nhanDuAn(t.id, duAn)];
    if (vai) { const v = await nhanTen(vai); if (v) labelIds.push(v); else console.log(`⚠️ Không có nhãn vai "${vai}" — bỏ qua`); }
    if (dem) { const v = await nhanTen('Ca đêm'); if (v) labelIds.push(v); }
    // Mô tả theo khuôn spec ngắn: việc · xong khi · brief (nguồn sự thật nằm ở file, không ở ticket)
    const desc = [moTa, xongKhi && `## Xong khi\n${xongKhi}`, brief && `## Brief\n\`${brief}\``].filter(Boolean).join('\n\n');
    const i = { teamId: t.id, title: tieuDe, description: desc, priority: uu, stateId, labelIds };
    const p = await projectId(duAn); if (p) i.projectId = p;
    if (cot !== 'xong' && t.activeCycle) i.cycleId = t.activeCycle.id;
    const r = await q('mutation($i:IssueCreateInput!){ issueCreate(input:$i){ issue { identifier url } } }', { i });
    console.log(`✅ ${r.issueCreate.issue.identifier} ${r.issueCreate.issue.url}`);
  } else if (lenh === 'dang' || lenh === 'xong' || lenh === 'soat') {
    const id = args[1]; if (!id) throw new Error('Thiếu mã HIO-x');
    const t = await team();
    const stateId = lenh === 'soat' ? t.states.nodes.find((s) => s.name === 'In Review')?.id : t.states.nodes.find((s) => s.type === COT[lenh]).id;
    if (!stateId) throw new Error('Team chưa có cột In Review');
    await q('mutation($id:String!,$i:IssueUpdateInput!){ issueUpdate(id:$id,input:$i){ success } }', { id, i: { stateId } });
    if (args[2]) await q('mutation($i:CommentCreateInput!){ commentCreate(input:$i){ success } }', { i: { issueId: id, body: args[2] } });
    console.log(`✅ ${id} → ${{ xong: 'Done', dang: 'In Progress', soat: 'In Review' }[lenh]}`);
  } else if (lenh === 'ds') {
    const d = await q('query($k:String!){ issues(first:150, filter:{ team:{key:{eq:$k}}, state:{type:{nin:["completed","canceled"]}} }){ nodes { identifier title state { name } project { name } labels { nodes { name } } } } }', { k: TEAM_KEY });
    const duAn = args[1]; const nhom = {};
    for (const i of d.issues.nodes) {
      const nhan = i.labels.nodes.map((l) => l.name);
      if (duAn && !nhan.some((n) => n === `Dự án: ${duAn}`)) continue;
      const pj = (i.project && i.project.name) || '(chưa có project)';
      const vai = nhan.filter((n) => !n.startsWith('Dự án: ')).join(', ');
      (nhom[pj] = nhom[pj] || []).push(`  ${i.identifier} [${i.state.name}] ${i.title}${vai ? '  · ' + vai : ''}`);
    }
    for (const [pj, ds] of Object.entries(nhom)) console.log(`${pj} (${ds.length})\n${ds.join('\n')}`);
  } else throw new Error('Lệnh: tao · dang · soat · xong · ds · dong-bo');
}

(async () => {
  const args = process.argv.slice(2);
  if (!args.length) { console.log(fs.readFileSync(__filename, 'utf8').split('\n').slice(0, 14).join('\n')); return; }
  K = key();
  if (args[0] === 'dong-bo') {
    if (!K) { console.log('⏳ 1Password vẫn khoá — để sau.'); return; }
    let ds = []; try { ds = JSON.parse(fs.readFileSync(HANG, 'utf8')); } catch {}
    const con = [];
    for (const x of ds) { try { await chay(x.args); } catch (e) { console.log(`❌ ${x.args.join(' ')}: ${e.message}`); con.push(x); } }
    fs.writeFileSync(HANG, JSON.stringify(con, null, 2));
    console.log(`Đồng bộ xong: ${ds.length - con.length}/${ds.length}`);
    return;
  }
  if (!K) { if (['tao', 'dang', 'soat', 'xong'].includes(args[0])) xepHang(args); else console.log('❌ Không mở được 1Password'); return; }
  try { await chay(args); } catch (e) { console.error('❌', e.message); process.exitCode = 1; }
})();
