// Linear 2 chiều cho đội agent: tạo ticket khi giao việc, chuyển cột khi làm / xong.
// Key lấy từ 1Password lúc chạy (op://Chatbot/Linear/credential), không ghi ra file / màn hình.
// 1Password đang khoá (ban đêm không ai mở) → lệnh ghi vào hàng chờ %LOCALAPPDATA%\wez-ai\linear-hang-doi.json, "dong-bo" chạy lại sau.
//   node linear.js tao <DựÁn> "tiêu đề" ["mô tả"] [--uu-tien 1-4] [--cot todo|dang|xong]   → in mã HIO-x
//   node linear.js dang <HIO-x>             → In Progress
//   node linear.js xong <HIO-x> ["ghi chú"]  → Done (+ bình luận)
//   node linear.js ds [DựÁn]                → ticket chưa xong
//   node linear.js dong-bo                  → chạy lại hàng chờ
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const TEAM_KEY = 'HIO';
const HANG = path.join(process.env.LOCALAPPDATA || '.', 'wez-ai', 'linear-hang-doi.json');
const COT = { todo: 'unstarted', dang: 'started', xong: 'completed' };

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
  const d = await q('query($k:String!){ teams(filter:{key:{eq:$k}}){ nodes { id states { nodes { id type } } } } }', { k: TEAM_KEY });
  return d.teams.nodes[0];
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
    const [duAn, tieuDe, moTa = ''] = a;
    if (!duAn || !tieuDe) throw new Error('Thiếu <DựÁn> "tiêu đề"');
    const t = await team();
    const stateId = t.states.nodes.find((s) => s.type === COT[cot])?.id;
    const labelId = await nhanDuAn(t.id, duAn);
    const r = await q('mutation($i:IssueCreateInput!){ issueCreate(input:$i){ issue { identifier url } } }',
      { i: { teamId: t.id, title: tieuDe, description: moTa, priority: uu, stateId, labelIds: [labelId] } });
    console.log(`✅ ${r.issueCreate.issue.identifier} ${r.issueCreate.issue.url}`);
  } else if (lenh === 'dang' || lenh === 'xong') {
    const id = args[1]; if (!id) throw new Error('Thiếu mã HIO-x');
    const t = await team();
    const stateId = t.states.nodes.find((s) => s.type === COT[lenh]).id;
    await q('mutation($id:String!,$i:IssueUpdateInput!){ issueUpdate(id:$id,input:$i){ success } }', { id, i: { stateId } });
    if (args[2]) await q('mutation($i:CommentCreateInput!){ commentCreate(input:$i){ success } }', { i: { issueId: id, body: args[2] } });
    console.log(`✅ ${id} → ${lenh === 'xong' ? 'Done' : 'In Progress'}`);
  } else if (lenh === 'ds') {
    const d = await q('query($k:String!){ issues(first:100, filter:{ team:{key:{eq:$k}}, state:{type:{nin:["completed","canceled"]}} }){ nodes { identifier title state { name } labels { nodes { name } } } } }', { k: TEAM_KEY });
    const duAn = args[1];
    for (const i of d.issues.nodes) {
      const nhan = i.labels.nodes.map((l) => l.name);
      if (duAn && !nhan.some((n) => n === `Dự án: ${duAn}`)) continue;
      console.log(`${i.identifier} [${i.state.name}] ${i.title}`);
    }
  } else throw new Error('Lệnh: tao · dang · xong · ds · dong-bo');
}

(async () => {
  const args = process.argv.slice(2);
  if (!args.length) { console.log(fs.readFileSync(__filename, 'utf8').split('\n').slice(0, 9).join('\n')); return; }
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
  if (!K) { if (['tao', 'dang', 'xong'].includes(args[0])) xepHang(args); else console.log('❌ Không mở được 1Password'); return; }
  try { await chay(args); } catch (e) { console.error('❌', e.message); process.exitCode = 1; }
})();
