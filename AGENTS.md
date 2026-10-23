# wezterm-ai

## Mục đích
Bản sao lưu + bộ cài cấu hình "đội AI trong WezTerm" (xem README.md). Có thể đóng gói cho học viên dùng Windows sau này.

## Quy ước
- Trả lời người dùng bằng tiếng Việt.
- Bản đang chạy thật nằm ở máy (~\.wezterm.lua, ~\.claude\..., E:\AI\TongQuanAI\cai-dat). Sửa ở đó trước, rồi chạy `cap-nhat.ps1` để chép vào repo.
- Trước khi commit/push: quét khoá bí mật (API key, token, mật khẩu). Repo **CÔNG KHAI** (người dùng cho 02/10, 23/10 làm bản cho người khác dùng): cap-nhat.ps1 tự chạy lam-sach.js — thay giá trị riêng theo ~.wez-ai-rieng.json (ngoài repo) và dừng nếu còn sót. Gặp tên/tài khoản/id riêng mới → thêm cặp vào file đó, KHÔNG sửa tay trong repo. Không đưa brief/báo cáo có tên riêng vào repo.
- File .ps1 phải lưu UTF-8 có BOM (PowerShell 5.1 mới đọc đúng tiếng Việt).
- Không cố định đường dẫn máy: đọc `~\.wez-ai.json` (aiRoot, hub, wezterm), mặc định `E:\AI` + hub `TongQuanAI`. Repo luôn ghi `E:\AI`; khoi-phuc.ps1 hỏi thư mục gốc khi cài lần đầu rồi đổi theo máy.
- Hệ thống chỉ dùng Claude + Codex (đã bỏ Gemini CLI 02/10/2026 — người dùng thấy code kém; đừng thêm lại).
- Quy tắc chung của 2 AI chỉ sửa ở 1 nơi: `~\.claude\CLAUDE.md` → chép sang `~\.codex\AGENTS.md` → cap-nhat.ps1 lưu thành `quy-tac/chung.md`.
- Repo có git hook pre-commit quét khoá bí mật (`git config core.hooksPath .githooks`, khoi-phuc.ps1 tự bật).

## Cách các phần nói chuyện với nhau (%LOCALAPPDATA%\wez-ai\)
- `alerts\<pane>.json`: báo động (Claude ghi qua hooks `wez-alert.js`; Codex do .wezterm.lua đoán từ tiêu đề) → nháy tab.
- `state\<pane>.json`: work / idle / need + session Claude → `wez.ps1 send` (từ chối khi bận) và `cho` (đợi xong); .wezterm.lua sửa 'work' bị kẹt khi tiêu đề Claude có ✳.
- `khoa.json`: khoá file (`khoa.js`; Claude tự khoá qua hooks PreToolUse/PostToolUse; hết hạn 30 phút hoặc khi ô đóng).
- `bo-cuc-luu.json` / `bo-cuc-tu-luu.json` / `bo-cuc-phien-truoc.json`: bố cục (Ctrl+Shift+S / O).
