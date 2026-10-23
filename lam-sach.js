#!/usr/bin/env node
// lam-sach.js — giữ thông tin cá nhân NGOÀI repo công khai.
// Danh sách thay thế ở ~\.wez-ai-rieng.json (KHÔNG commit):
//   { "giu": ["chuỗi giữ nguyên, vd link repo công khai"],
//     "thay": [["giá trị thật", "giá trị mẫu"], ["TenDuAn", "DuAnA", "tu"]] }   // "tu" = chỉ thay cả từ
// Cách chạy:
//   node lam-sach.js            → làm sạch mọi file chữ trong repo (cap-nhat.ps1 tự gọi)
//   node lam-sach.js --kiem     → chỉ kiểm: còn giá trị thật nào thì in ra + mã thoát 1
//   node lam-sach.js --nguoc <thư mục|file>...   → đổi ngược (mẫu → thật) cho bản đã cài trên máy của chính bạn
// Không có ~\.wez-ai-rieng.json → không làm gì (máy người khác).
'use strict';
const fs = require('fs'), path = require('path'), os = require('os');
const RIENG = path.join(os.homedir(), '.wez-ai-rieng.json');
const DUOI = /\.(js|ps1|lua|md|json|toml|vbs|rules|txt|cmd|bat|sh)$/i;

function docMap() {
  try { const m = JSON.parse(fs.readFileSync(RIENG, 'utf8').replace(/^﻿/, '')); return { giu: m.giu || [], thay: (m.thay || []).filter((x) => x[0] && x[1]) }; }
  catch { return null; }
}
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const re = (s, tu) => new RegExp(tu ? `(?<![\\p{L}\\p{N}_])${esc(s)}(?![\\p{L}\\p{N}_])` : esc(s), 'gu');

function doi(text, map, nguoc) {
  const giu = [];
  for (const g of map.giu) text = text.split(g).join(`\u0000${giu.push(g) - 1}\u0000`);
  // dài trước để "abcxyz" không bị "abc" ăn mất
  const cap = map.thay.map(([a, b, k]) => (nguoc ? [b, a, k] : [a, b, k])).sort((x, y) => y[0].length - x[0].length);
  for (const [tu, sang, k] of cap) text = text.replace(re(tu, k === 'tu'), sang);
  return text.replace(/\u0000(\d+)\u0000/g, (_, i) => giu[+i]);
}
function file(dir) {
  const ra = [];
  (function di(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      if (e.name === '.git' || e.name === 'node_modules') continue;
      const p = path.join(d, e.name);
      if (e.isDirectory()) di(p); else if (DUOI.test(e.name) && !['lam-sach.js', 'cap-nhat.ps1'].includes(e.name)) ra.push(p);
    }
  })(dir);
  return ra;
}
function chay(ds, map, nguoc) {
  let n = 0;
  for (const f of ds) {
    const goc = fs.readFileSync(f, 'utf8'), moi = doi(goc, map, nguoc);
    if (moi !== goc) { fs.writeFileSync(f, moi); n++; }   // giữ BOM nếu có (BOM là ký tự đầu chuỗi, không bị thay)
  }
  return n;
}

if (require.main === module) {
  const [cmd, ...rest] = process.argv.slice(2);
  // tự kiểm nhanh: thay cả từ, giữ chuỗi, đổi ngược
  const t = { giu: ['ab/repo'], thay: [['ab', 'MAU'], ['Xa', 'DuAn1', 'tu']] };
  const s = 'ab ab/repo Xa Xay', d = doi(s, t, false);
  if (d !== 'MAU ab/repo DuAn1 Xay' || doi(d, t, true) !== s) { console.error('lam-sach tự kiểm lỗi: ' + d); process.exit(2); }
  const map = docMap();
  if (!map) { console.log('ℹ️  Không có ' + RIENG + ' → bỏ qua làm sạch.'); process.exit(0); }
  if (cmd === '--nguoc') {
    const ds = rest.flatMap((p) => (fs.statSync(p).isDirectory() ? file(p) : [p]));
    console.log(`↩  Đổi ngược ${chay(ds, map, true)} file theo ${RIENG}`);
  } else if (cmd === '--kiem') {
    let con = 0;
    for (const f of file(__dirname)) {
      const s = fs.readFileSync(f, 'utf8');
      const sach = map.giu.reduce((x, g) => x.split(g).join(''), s);
      for (const [a, , k] of map.thay) { const m = sach.match(re(a, k === 'tu')); if (m) { con += m.length; console.log(`  ❌ ${path.relative(__dirname, f)}: còn "${a}" ×${m.length}`); } }
    }
    console.log(con ? `⛔ Còn ${con} chỗ thông tin cá nhân` : '✅ Không còn thông tin cá nhân (theo danh sách riêng)');
    process.exit(con ? 1 : 0);
  } else {
    console.log(`🧹 Làm sạch ${chay(file(__dirname), map, false)} file`);
  }
}
module.exports = { doi };
