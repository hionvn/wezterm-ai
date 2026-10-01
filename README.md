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
| Báo động: tab đỏ 🔔 (cần duyệt) / xanh ✅ (xong) + thông báo Windows — cả Claude, Codex, Gemini | tự động |
| Đồng hồ hạn mức ⛽ Claude & Codex trên thanh trên | tự động |
| Nhãn 👑 TỔNG QUẢN / 🧭 MANAGER <DỰ ÁN>, màu theo dự án | tự động |
| AI điều khiển ô khác | `scripts/wez.ps1 list · send · cho · read · nen · chinh · mo` |
| Giao việc rồi đợi xong: `send` từ chối khi ô đang bận / chờ duyệt, `cho` đợi tới khi xong rồi in kết quả | `wez.ps1 send <id> "câu"` → `wez.ps1 cho <id>` |
| Khoá file: 2 AI không sửa chồng một file (Claude tự động, Codex/Gemini theo quy tắc) | `node scripts/khoa.js giu · tha · kiem · xem` |
| Lưu / mở lại bố cục (Claude tiếp tục đúng phiên cũ); tự lưu mỗi phút, có "Phiên trước" | `Ctrl+Shift+S` / `Ctrl+Shift+O` |
| Tự chẩn đoán cài đặt (thiếu gì, sửa thế nào) | `scripts/kiem-tra.ps1` |
| Chặn commit có khoá bí mật | tự động (git hook), hoặc `quet-bi-mat.ps1` |
| Lệnh tắt PowerShell | `ai`, `ai3`, `aiall`, `hub` / `sino` / `cool` / `bot` [-All], `newproj` |

Sổ tay phím tắt + hướng dẫn theo tình huống: https://claude.ai/artifact/MXLJEZVUsnRzNN72AtFbo7

## Cấu trúc
```
wezterm/.wezterm.lua              → ~\.wezterm.lua
scripts/*                         → E:\AI\_Hub\cai-dat\   (wez.ps1, báo động, khoá file, tự bật tài liệu, ô Cần duyệt, kiểm tra)
claude/statusline.js              → ~\.claude\statusline.js
claude/settings.phan-them.json    → gộp vào ~\.claude\settings.json (statusLine + hooks)
codex/config.phan-them.toml       → gộp vào ~\.codex\config.toml (tiêu đề có run-state → báo động Codex)
gemini/settings.phan-them.json    → gộp vào ~\.gemini\settings.json (tiêu đề động → báo động Gemini)
powershell/...profile.ps1         → $PROFILE (lệnh ai, hub, bot...)
quy-tac/chung.md                  → ~\.claude\CLAUDE.md, ~\.codex\AGENTS.md, ~\.gemini\GEMINI.md (1 nguồn cho cả 3)
khoi-phuc.ps1                     cài lại tất cả lên máy mới (-AIRoot D:\AI nếu không có ổ E:)
cap-nhat.ps1                      chép cấu hình đang dùng vào repo để sao lưu + quét khoá bí mật
quet-bi-mat.ps1, .githooks/       quét khoá bí mật; git hook pre-commit chặn commit có khoá
```
Máy lưu thư mục dự án + đường dẫn WezTerm ở `~\.wez-ai.json` (khoi-phuc.ps1 tạo); mọi script đọc từ đó.
Trạng thái chạy nằm ở `%LOCALAPPDATA%\wez-ai\` (alerts, state, khoa.json, bo-cuc-*.json).

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
- Mặc định dự án ở `E:\AI`, script ở `E:\AI\_Hub\cai-dat`. Máy khác ổ đĩa: `khoi-phuc.ps1 -AIRoot D:\AI` (ghi vào `~\.wez-ai.json`, không cần sửa code).
- Cài xong / lỗi lạ: chạy `E:\AI\_Hub\cai-dat\kiem-tra.ps1` để xem thiếu gì.
- Mở lại bố cục dựng theo cột rồi theo hàng: kiểu chia lồng nhau phức tạp chỉ gần đúng.
- Cần WezTerm bản 20240203 trở lên, Node.js, glow (để hiện Markdown có màu).
