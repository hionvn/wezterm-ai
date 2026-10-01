# Quy tắc chung (áp dụng cho mọi dự án)

## Giao tiếp
- Luôn trả lời bằng tiếng Việt, ngắn gọn, dễ hiểu; giải thích thuật ngữ khi cần.
- Khi đưa lệnh cho người dùng tự chạy, ghi rõ chạy ở đâu và lệnh đó làm gì.
- Mọi chữ tiếng Anh hiển thị cho người dùng (câu hỏi, lựa chọn, thông báo, thuật ngữ, trích dẫn output) phải kèm chú thích tiếng Việt ngay bên cạnh, vd: "Allow (Cho phép)".
- Trình bày cho dễ nhìn trong terminal: dòng đầu là kết luận in đậm; dùng tiêu đề ##; đánh dấu ý quan trọng bằng **in đậm** + biểu tượng cố định: 📌 quan trọng, ⚠️ cảnh báo, ✅ đã xong, 👉 việc người dùng cần làm; lệnh để trong khối code. Chỉ làm nổi vài điểm thật sự quan trọng, không lạm dụng.

## Môi trường
- Windows 11, terminal là Windows Terminal + PowerShell 5.1 (không dùng cú pháp bash cho lệnh người dùng tự gõ).
- Thư mục dự án nằm trong E:\AI\<ten-du-an>, mỗi dự án có AGENTS.md riêng.
- Người dùng chạy song song 2 AI: Claude Code, Codex (GPT) — trên cùng thư mục dự án. (Đã bỏ Gemini CLI từ 02/10/2026, đừng đề xuất dùng lại.)
  Tránh sửa cùng một file mà AI khác có thể đang sửa; ghi thông tin cần chia sẻ vào AGENTS.md của dự án.

## An toàn
- Hỏi trước khi xoá file/thư mục, ghi đè dữ liệu, hoặc thay đổi cấu hình hệ thống.
- Không in hay ghi API key / mật khẩu ra màn hình hoặc vào file trong dự án.

## Kho kiến thức chung
- Tài liệu dùng chung giữa các dự án (ghi chú khóa học BTO, kế hoạch kinh doanh…) có mục lục ở `E:\AI\_Hub\kho-kien-thuc.md`.
  Khi việc đang làm cần kiến thức/kế hoạch chung, đọc mục lục đó rồi mở đúng file liên quan (không đọc hết).
- Tạo tài liệu mới cần chia sẻ giữa các dự án → thêm 1 dòng vào mục lục đó.

## Làm việc trong WezTerm (đội AI)
- Làm xong một tài liệu người dùng cần đọc hoặc duyệt (báo cáo, spec, kế hoạch, bài tập…) → bật nó lên màn hình: `node E:\AI\_Hub\cai-dat\mo-tai-lieu.js <đường dẫn file>`.
- Việc cần người dùng quyết → ghi thêm 1 dòng vào `E:\AI\_Hub\can-duyet.md` (mục "Đang chờ", ghi rõ [tên dự án]).
- Điều khiển ô khác: `E:\AI\_Hub\cai-dat\wez.ps1` (list · send · cho · read · nen = đẩy ô ra tab nền · chinh = kéo ô về · mo = bật tài liệu). Luôn `list` trước để chắc đúng ô.
  Giao việc cho ô khác: `send <id> "câu"` rồi `cho <id>` (đợi ô đó làm xong và in kết quả) thay vì `read` nhiều lần.
  Cần AI mới ở dự án khác: `giao <dự án> <claude|codex> "việc"` (mở tab nền, in PANEID); thêm `-Cho -Ra <file>` để đợi xong và lưu kết quả. Giao song song: gọi `giao` nhiều lần rồi `cho 12,13`. `send` từ chối khi ô đang bận / chờ duyệt — đợi, đừng thêm `-Ep` nếu chưa chắc.
- Khoá file (tránh 2 AI sửa chồng một file): Claude được tự khoá qua hooks. Codex trước khi sửa file thì chạy `node E:\AI\_Hub\cai-dat\khoa.js giu <file> --ai codex`; báo "đang bị giữ" thì không sửa, báo người dùng. Sửa xong: `khoa.js tha <file>`. Xem khoá: `khoa.js xem`.
