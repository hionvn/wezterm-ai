# wezterm-ai — đội AI chạy trong WezTerm trên Windows

Bộ cấu hình biến WezTerm thành "phòng điều hành" cho nhiều AI (Claude Code, Codex) chạy song song (đã bỏ Gemini CLI từ 02/10/2026),
theo mô hình của khóa Build to Own (anh Sơn, buổi 8): **CEO → Tổng quản (Chief of Staff) → Manager từng dự án → Worker**.
Khác bản gốc chỉ chạy trên Mac, bản này chạy trên **Windows + PowerShell 5.1**.

## Có gì
| Tính năng | Phím / lệnh |
|---|---|
| Menu chọn dự án + AI, mở ở ô phải / ô dưới / tab mới | `Ctrl+Shift+A`, hoặc gõ `ai` |
| Tab "Tổng quản": Claude ở `Hion` + ô 📋 Cần duyệt | `Ctrl+Shift+H` |
| Bật / tắt ô 📋 Cần duyệt (can-duyet.md + sổ tiến độ các dự án, tự cập nhật) | `Ctrl+Shift+J` |
| Tài liệu AI vừa làm xong tự bật lên ô 📄 | AI chạy `node scripts/mo-tai-lieu.js <file>` |
| Đẩy ô ra tab nền / kéo ô ở tab khác về | `Ctrl+Shift+B` / `Ctrl+Shift+G` |
| Báo động: tab đỏ 🔔 (cần duyệt) / xanh ✅ (xong) + thông báo Windows — cả Claude và Codex | tự động |
| Đồng hồ hạn mức ⛽ Claude & Codex trên thanh trên | tự động |
| Nhãn 👑 TỔNG QUẢN / 🧭 MANAGER <DỰ ÁN>, màu theo dự án | tự động |
| AI điều khiển ô khác | `scripts/wez.ps1 list · send · cho · read · nen · chinh · mo` |
| Giao việc rồi đợi xong: `send` từ chối khi ô đang bận / chờ duyệt, `cho` đợi tới khi xong rồi in kết quả | `wez.ps1 send <id> "câu"` → `wez.ps1 cho <id>` |
| Giao việc cho AI mới ở dự án khác (tab nền), đợi xong + lưu kết quả; giao song song rồi đợi nhiều ô | `wez.ps1 giao <dự án> <claude\|codex> "việc" [-Cho -Ra file]` · `wez.ps1 cho 12,13` |
| Báo sang điện thoại (app ntfy) khi ô cần duyệt quá N phút mà chưa bấm vào — mặc định tắt | `wez.ps1 dienthoai bat` · `thu` · `tat` |
| Bàn duyệt bấm nút: mỗi việc trong ô 📋 có ✅ Duyệt · ✏️ Trả lời · ❌ Bỏ; quyết định ghi vào `quyet-dinh.md` | bấm chuột · `node scripts/duyet.js list/them/ok/sua/bo` |
| Báo cáo sáng (việc chờ duyệt, quyết định mới, tiến độ + git từng dự án, hạn mức) tự bật lúc mở WezTerm lần đầu từ 7 giờ | tự động · `node scripts/bao-cao-sang.js --mo` |
| **Nhiều tài khoản Codex chạy song song**: mỗi dự án một tài khoản (CODEX_HOME riêng), không văng đăng nhập; bảng tài khoản + Gmail để đăng nhập lại đúng | `doi-ca cai` · `tai-khoan` · `dang-nhap <số>` · `codex <dự án>` |
| **Trực ca tự động**: Codex sắp hết lượt → nhắc ghi bàn giao; hết hẳn → Claude tự vào làm tiếp (ô Codex giữ nguyên, luật đêm: không nhắn khách/đăng bài/tiêu tiền/push); Codex có lượt lại → trả ca | `doi-ca bat` · `tat` · `xem` |
| Tự kiểm chứng đổi ca trong 3 phút (Claude thật + Codex giả, in ✅/❌ từng bước) · soát máy | `doi-ca mo-phong` · `doi-ca kiem-tra` |
| Review chéo: AI kia đọc thay đổi chưa commit, ghi lỗi ra file | `wez.ps1 review <dự án> [codex\|claude]` |
| Khoá file: 2 AI không sửa chồng một file (Claude tự động, Codex theo quy tắc) | `node scripts/khoa.js giu · tha · kiem · xem` |
| Lưu / mở lại bố cục (Claude tiếp tục đúng phiên cũ); tự lưu mỗi phút, có "Phiên trước" | `Ctrl+Shift+S` / `Ctrl+Shift+O` |
| Tự chẩn đoán cài đặt (thiếu gì, sửa thế nào) | `scripts/kiem-tra.ps1` |
| Chặn commit có khoá bí mật | tự động (git hook), hoặc `quet-bi-mat.ps1` |
| Lệnh tắt PowerShell | `doi-ca`, `ai`, `ai2` (Claude | Codex; `ai3` vẫn dùng được), `hion` / `sino` / `cool` / `bot` [-All], `newproj` |

Sổ tay phím tắt + hướng dẫn theo tình huống: https://claude.ai/artifact/MXLJEZVUsnRzNN72AtFbo7

## Cấu trúc
```
wezterm/.wezterm.lua              → ~\.wezterm.lua
scripts/*                         → E:\AI\Hion\cai-dat\   (wez.ps1, báo động, khoá file, tự bật tài liệu, ô Cần duyệt, kiểm tra)
claude/statusline.js              → ~\.claude\statusline.js
claude/settings.phan-them.json    → gộp vào ~\.claude\settings.json (statusLine + hooks)
codex/config.phan-them.toml       → gộp vào ~\.codex\config.toml (tiêu đề có run-state → báo động Codex)
powershell/...profile.ps1         → $PROFILE (lệnh ai, hion, bot...)
quy-tac/chung.md                  → đoạn đánh dấu "wezterm-ai" trong ~\.claude\CLAUDE.md, ~\.codex\AGENTS.md (bản chung, sửa trực tiếp)
mau/Hion/*                        → Tổng quản: AGENTS.md, doi-agent.md, can-duyet.md, quyet-dinh.md, kho-kien-thuc.md (chỉ tạo khi chưa có)
mau/du-an/*                       → mẫu Manager cho newproj / "khởi động đội" (chép vào Hion\cai-dat\mau)
khoi-phuc.ps1                     cài lại tất cả lên máy mới (-AIRoot D:\AI nếu không có ổ E:)
cap-nhat.ps1                      chép cấu hình đang dùng vào repo để sao lưu + quét khoá bí mật
quet-bi-mat.ps1, .githooks/       quét khoá bí mật; git hook pre-commit chặn commit có khoá
thu-cai/mo-may-ao.ps1             thử khoi-phuc.ps1 trên máy Windows sạch (Windows Sandbox), kết quả ở thu-cai/ket-qua/
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

### Sau khi cài: đặt vai cho cả đội (5 phút)
1. Mở WezTerm, đăng nhập `claude` và `codex`.
2. Đặt các thư mục dự án vào thư mục AI (mặc định `E:\AI`, hoặc chỗ bạn chọn bằng `-AIRoot`). Tạo dự án mới: `newproj <tên>` — có sẵn vai 🧭 Manager và sổ tiến độ để bàn giao.
3. Bấm `Ctrl+Shift+H` (tab Tổng quản) và nói **"khởi động đội"**: Tổng quản hỏi từng dự án làm gì, rồi tự điền vai cho cả đội (`Hion\AGENTS.md`, `doi-agent.md`, AGENTS.md từng dự án).
4. Có nhiều tài khoản ChatGPT dùng Codex: `doi-ca cai` → mỗi dự án một tài khoản; tối trước khi ngủ `doi-ca bat` để Claude thay ca khi Codex hết lượt.

Bộ cài tạo sẵn các file của Tổng quản (bàn duyệt, sổ quyết định, kho kiến thức, sơ đồ đội) từ thư mục `mau\` — **chỉ khi máy chưa có**, không ghi đè file của bạn. Quy tắc chung được thêm vào `~\.claude\CLAUDE.md` và `~\.codex\AGENTS.md` giữa hai dòng đánh dấu `wezterm-ai`; ghi chú riêng của bạn ngoài đoạn đó luôn được giữ.

## Sao lưu sau khi sửa cấu hình
```powershell
powershell -ExecutionPolicy Bypass -File E:\AI\wezterm-ai\cap-nhat.ps1
```
rồi quét khoá bí mật, commit, push.

## Lưu ý
- Không có API key / mật khẩu trong repo. Đừng thêm vào.
- Mặc định dự án ở `E:\AI`, script ở `E:\AI\Hion\cai-dat`. Máy khác ổ đĩa: `khoi-phuc.ps1 -AIRoot D:\AI` (ghi vào `~\.wez-ai.json`, không cần sửa code).
- Cài xong / lỗi lạ: chạy `E:\AI\Hion\cai-dat\kiem-tra.ps1` để xem thiếu gì.
- Mở lại bố cục dựng theo cột rồi theo hàng: kiểu chia lồng nhau phức tạp chỉ gần đúng.
- Cần WezTerm bản 20240203 trở lên, Node.js, glow (để hiện Markdown có màu).
