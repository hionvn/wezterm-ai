# wezterm-ai — đội AI chạy trong WezTerm trên Windows

Bộ cấu hình biến WezTerm thành "phòng điều hành" cho nhiều AI (Claude Code, Codex, Gemini CLI) chạy song song,
theo mô hình của khóa Build to Own (anh Sơn, buổi 8): **CEO → Tổng quản (Chief of Staff) → Manager từng dự án → Worker**.
Khác bản gốc chỉ chạy trên Mac, bản này chạy trên **Windows + PowerShell 5.1**.

## Có gì
| Tính năng | Phím / lệnh |
|---|---|
| Menu chọn dự án + AI, mở ở ô phải / ô dưới / tab mới | `Ctrl+Shift+A`, hoặc gõ `ai` |
| Tab "Tổng quản": Claude ở `_Hub` + ô 📋 Cần duyệt | `Ctrl+Shift+H` |
| Bật / tắt ô 📋 Cần duyệt (can-duyet.md + sổ tiến độ các dự án, tự cập nhật) | `Ctrl+Shift+J` |
| Tài liệu AI vừa làm xong tự bật lên ô 📄 | AI chạy `node scripts/mo-tai-lieu.js <file>` |
| Đẩy ô ra tab nền / kéo ô ở tab khác về | `Ctrl+Shift+B` / `Ctrl+Shift+G` |
| Báo động: tab đỏ 🔔 (cần duyệt) / xanh ✅ (xong) + thông báo Windows | tự động |
| Đồng hồ hạn mức ⛽ Claude & Codex trên thanh trên | tự động |
| Nhãn 👑 TỔNG QUẢN / 🧭 MANAGER <DỰ ÁN>, màu theo dự án | tự động |
| AI điều khiển ô khác | `scripts/wez.ps1 list · send · read · nen · chinh · mo` |
| Lệnh tắt PowerShell | `ai`, `ai3`, `aiall`, `hub` / `sino` / `cool` / `bot` [-All], `newproj` |

Sổ tay phím tắt + hướng dẫn theo tình huống: https://claude.ai/artifact/MXLJEZVUsnRzNN72AtFbo7

## Cấu trúc
```
wezterm/.wezterm.lua              → ~\.wezterm.lua
scripts/*                         → E:\AI\_Hub\cai-dat\   (wez.ps1, báo động, tự bật tài liệu, ô Cần duyệt)
claude/statusline.js              → ~\.claude\statusline.js
claude/settings.phan-them.json    → gộp vào ~\.claude\settings.json (statusLine + hooks)
powershell/...profile.ps1         → $PROFILE (lệnh ai, hub, bot...)
quy-tac/*                         → ~\.claude\CLAUDE.md, ~\.codex\AGENTS.md, ~\.gemini\GEMINI.md
khoi-phuc.ps1                     cài lại tất cả lên máy mới
cap-nhat.ps1                      chép cấu hình đang dùng vào repo để sao lưu
```

## Cài lên máy mới
```powershell
gh repo clone hionvn/wezterm-ai E:\AI\wezterm-ai
cd E:\AI\wezterm-ai
powershell -ExecutionPolicy Bypass -File .\khoi-phuc.ps1 -CaiAI
```
Mọi file cũ trên máy được sao lưu thành `*.bak-<ngày giờ>` trước khi ghi đè. Sau đó tự đăng nhập từng AI.

## Sao lưu sau khi sửa cấu hình
```powershell
powershell -ExecutionPolicy Bypass -File E:\AI\wezterm-ai\cap-nhat.ps1
```
rồi quét khoá bí mật, commit, push.

## Lưu ý
- Không có API key / mật khẩu trong repo. Đừng thêm vào.
- Đường dẫn đang cố định theo máy gốc: dự án ở `E:\AI`, script ở `E:\AI\_Hub\cai-dat`. Máy khác ổ đĩa thì sửa các biến `AI_ROOT`, `HUB` đầu `.wezterm.lua` và `$AIRoot` trong profile.
- Cần WezTerm bản 20240203 trở lên, Node.js, glow (để hiện Markdown có màu).
