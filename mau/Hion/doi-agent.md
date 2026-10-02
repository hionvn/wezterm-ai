# Đội agent — ai làm gì

Mô hình (theo buổi 8 khóa Build to Own): **người điều hành → Tổng quản → Manager từng dự án → agent chuyên môn / Worker**.

```
Bạn (người điều hành) ── giao việc bằng chữ hoặc giọng nói
   └─ 👑 Tổng quản = Claude ở {{AIROOT}}\Hion
        ├─ 🧭 Manager dự án A = Claude ở {{AIROOT}}\<A>
        ├─ 🧭 Manager dự án B = Claude ở {{AIROOT}}\<B>
        └─ … mỗi Manager gọi Worker / agent chuyên môn khi cần
```

| Agent chuyên môn | Làm gì | AI mặc định | Cách gọi |
|---|---|---|---|
| ⚙️ Engineer | Code, nối API/MCP, sửa lỗi, tự động hoá | Codex | `wez.ps1 giao <dự án> codex "…"` |
| ✏️ Design | Giao diện, sơ đồ, trang, slide | Claude | `wez.ps1 giao <dự án> claude "…"` |
| 🔒 Security | Soát khoá bí mật, quyền, dữ liệu khách trước khi push / ra mắt | AI còn lại, chỉ đọc | `wez.ps1 review <dự án>` |
| 📣 Marketing | Nội dung bán hàng, nghiên cứu thị trường | Claude | `wez.ps1 giao <dự án> claude "…"` |

Chỉ dùng vai nào dự án thật sự cần, không bắt buộc đủ 4.

## Luật chạy
1. Người điều hành chỉ cần nói với **Tổng quản**. Tổng quản hiểu ý → chia cho đúng Manager → báo lại.
2. **Manager** giữ `tien-do-<dự án>.md`, chia việc nhỏ, gom kết quả, commit trong thư mục dự án.
3. Việc chạm tiền, dữ liệu khách, đẩy code, ra mắt → qua **Security** (review chéo) trước.
4. Cần người điều hành quyết → bàn duyệt (`duyet.js them`), không tự làm.
5. Ghi mọi thứ cần chia sẻ vào file (AGENTS.md, tiến độ): AI khác không đọc được cuộc chat.
6. Nhiều tài khoản Codex: mỗi dự án một tài khoản (bảng `~\.codex-tai-khoan.json`; lệnh `codex` tự chọn theo dự án, `codextk` xem bảng).

## Đội của bạn
| Dự án | Manager | Worker / chuyên môn hay dùng | Tài khoản Codex |
|---|---|---|---|
| *(Tổng quản điền khi "khởi động đội")* | | | |
