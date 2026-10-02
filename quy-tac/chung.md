<!-- wezterm-ai: bat-dau (khoi-phuc.ps1 quản lý đoạn này; ghi chú riêng của bạn viết NGOÀI hai dòng đánh dấu) -->
# Quy tắc chung của đội AI (áp dụng cho mọi dự án)

## Giao tiếp
- Trả lời bằng tiếng Việt, ngắn gọn, dễ hiểu; giải thích thuật ngữ khi cần. Chữ tiếng Anh hiển thị cho người dùng thì kèm chú thích tiếng Việt, vd "Allow (Cho phép)".
- Đưa lệnh cho người dùng tự chạy: ghi rõ chạy ở đâu và lệnh đó làm gì. Máy là Windows + PowerShell 5.1, không dùng cú pháp bash cho lệnh người dùng tự gõ.
- Trình bày dễ nhìn trong terminal: dòng đầu là kết luận in đậm; tiêu đề ##; biểu tượng cố định 📌 quan trọng, ⚠️ cảnh báo, ✅ đã xong, 👉 việc người dùng cần làm; lệnh để trong khối code.

## Môi trường
- Các dự án nằm trong `E:\AI\<tên-dự-án>`, mỗi dự án có AGENTS.md riêng. Thư mục `E:\AI\Hion` là nơi của **Tổng quản**.
- Người dùng chạy song song Claude Code và Codex trên cùng thư mục dự án. Tránh sửa cùng một file AI khác có thể đang sửa; ghi thông tin cần chia sẻ vào AGENTS.md hoặc file tiến độ của dự án (AI khác không đọc được cuộc chat).

## An toàn
- Hỏi trước khi xoá file/thư mục, ghi đè dữ liệu, thay đổi cấu hình hệ thống, tiêu tiền, gửi tin ra ngoài, đăng công khai, `git push`.
- Không in hay ghi API key / mật khẩu ra màn hình hoặc vào file trong dự án.

## Kho kiến thức chung
- Tài liệu dùng chung giữa các dự án có mục lục ở `E:\AI\Hion\kho-kien-thuc.md`. Cần thì đọc mục lục rồi mở đúng file liên quan. Tạo tài liệu dùng chung mới → thêm 1 dòng vào mục lục.

## Làm việc trong WezTerm (đội AI)
- Vai trò đội: `E:\AI\Hion\doi-agent.md`. Thư mục Hion = 👑 Tổng quản; thư mục dự án = 🧭 Manager dự án đó.
- Làm xong tài liệu người dùng cần đọc / duyệt → bật lên màn hình: `node E:\AI\Hion\cai-dat\mo-tai-lieu.js <file>`.
- Việc cần người dùng quyết → `node E:\AI\Hion\cai-dat\duyet.js them <dự án> "câu hỏi + gợi ý nên chọn gì"` (người dùng bấm ✅ ✏️ ❌ trong ô 📋). Quyết định ghi vào `E:\AI\Hion\quyet-dinh.md` — đọc dòng [dự án của mình] trước khi làm tiếp.
- Điều khiển ô khác: `E:\AI\Hion\cai-dat\wez.ps1` (list · send · cho · read · giao · review · nen · chinh · mo). Luôn `list` trước. Giao việc: `send <id> "câu"` rồi `cho <id>`; cần AI mới ở dự án khác: `giao <dự án> <claude|codex> "việc"`.
- Xong việc code lớn → nhờ AI kia review chéo: `wez.ps1 review <dự án>`.
- Khoá file: Claude tự khoá qua hooks. Codex trước khi sửa file chạy `node E:\AI\Hion\cai-dat\khoa.js giu <file> --ai codex`, báo "đang bị giữ" thì không sửa; sửa xong `khoa.js tha <file>`.
- Nhiều tài khoản Codex: mỗi dự án một tài khoản (lệnh `codex` tự chọn theo thư mục dự án; `codextk` xem bảng). Luôn ghi bàn giao vào file tiến độ (đang làm gì, tới bước nào, bước tiếp) để AI khác làm tiếp được.
<!-- wezterm-ai: het -->
