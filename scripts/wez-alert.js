// Báo động + trạng thái cho WezTerm khi một ô Claude cần người dùng, đang làm, hoặc vừa làm xong.
// Claude Code gọi file này qua hooks (~/.claude/settings.json):
//   node wez-alert.js need   ← sự kiện Notification (xin quyền, chờ trả lời)
//   node wez-alert.js done   ← sự kiện Stop (trả lời xong)
//   node wez-alert.js work   ← sự kiện UserPromptSubmit / PostToolUse (đang làm)
// Ghi 2 loại file nhỏ trong %LOCALAPPDATA%\wez-ai\:
//   alerts\<PANEID>.json = { kind: 'need'|'done', text, t }  → ~/.wezterm.lua nháy tab + thông báo Windows
//   state\<PANEID>.json  = { state: 'work'|'idle'|'need', ai, session, t } → wez.ps1 send/cho biết ô bận hay rảnh
const fs = require('fs');
const path = require('path');

const kind = ['need', 'done', 'work'].includes(process.argv[2]) ? process.argv[2] : 'done';
const pane = process.env.WEZTERM_PANE;
let input = '';
process.stdin.on('data', (c) => (input += c));
process.stdin.on('end', () => {
  if (!pane) return; // không chạy trong WezTerm thì thôi
  let data = {};
  try { data = JSON.parse(input.replace(/^﻿/, '')); } catch {}
  const base = path.join(process.env.LOCALAPPDATA || '', 'wez-ai');
  const alertFile = path.join(base, 'alerts', pane + '.json');
  const now = Math.floor(Date.now() / 1000);
  const asksPermission = /permission/i.test(String(data.message || ''));

  // "Đang chờ trả lời" (đã xong, ngồi chờ) vẫn tính là rảnh; chỉ xin quyền mới là 'need'
  const state = kind === 'work' ? 'work' : kind === 'need' && asksPermission ? 'need' : 'idle';
  try {
    fs.mkdirSync(path.join(base, 'state'), { recursive: true });
    fs.writeFileSync(path.join(base, 'state', pane + '.json'),
      JSON.stringify({ state, ai: 'claude', session: data.session_id || '', t: now }));
  } catch {}

  if (kind === 'work') { // bắt đầu làm lại → tắt báo động cũ của ô này
    try { fs.unlinkSync(alertFile); } catch {}
    return;
  }
  const project = path.basename(data.cwd || process.cwd());
  const who = project.toLowerCase() === 'hion' ? '👑 Tổng quản' : `🧭 Manager ${project}`;
  let text;
  if (kind === 'done') text = `${who} đã trả lời xong`;
  else if (asksPermission) text = `${who} cần bạn cho phép`;
  else text = `${who} đang chờ bạn trả lời`;
  try {
    fs.mkdirSync(path.dirname(alertFile), { recursive: true });
    fs.writeFileSync(alertFile, JSON.stringify({ kind, text, t: now }));
  } catch {}
});
