// Báo động cho WezTerm khi một ô Claude cần người dùng hoặc vừa làm xong.
// Claude Code gọi file này qua hooks (~/.claude/settings.json):
//   node wez-alert.js need   ← sự kiện Notification (xin quyền, chờ trả lời)
//   node wez-alert.js done   ← sự kiện Stop (trả lời xong)
// Ghi một file nhỏ vào %LOCALAPPDATA%\wez-ai\alerts\<PANEID>.json;
// ~/.wezterm.lua đọc file đó để nháy tab + hiện thông báo Windows.
const fs = require('fs');
const path = require('path');

const kind = process.argv[2] === 'need' ? 'need' : 'done';
const pane = process.env.WEZTERM_PANE;
let input = '';
process.stdin.on('data', (c) => (input += c));
process.stdin.on('end', () => {
  if (!pane) return; // không chạy trong WezTerm thì thôi
  let data = {};
  try { data = JSON.parse(input.replace(/^﻿/, '')); } catch {}
  const project = path.basename(data.cwd || process.cwd());
  const who = project.toLowerCase() === '_hub' ? '👑 Tổng quản' : `🧭 Manager ${project}`;
  const msg = String(data.message || '');
  let text;
  if (kind === 'done') text = `${who} đã trả lời xong`;
  else if (/permission/i.test(msg)) text = `${who} cần bạn cho phép`;
  else text = `${who} đang chờ bạn trả lời`;
  const dir = path.join(process.env.LOCALAPPDATA || '', 'wez-ai', 'alerts');
  try {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, pane + '.json'), JSON.stringify({ kind, text, t: Math.floor(Date.now() / 1000) }));
  } catch {}
});
