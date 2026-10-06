# Hướng dẫn cho người mới — đội AI trong WezTerm

Bản này dành cho người **chưa từng dùng** bộ wezterm-ai. Đọc từ trên xuống, làm theo từng bước; khoảng 30 phút là chạy được đội đầu tiên.
Danh sách tính năng đầy đủ: [README.md](README.md).

---

## 1. Hiểu trong 1 phút

Bạn là **chủ**. Bạn không tự gõ từng việc cho từng AI — bạn nói với **một** AI, nó chia việc cho cả đội.

```
Bạn (chủ)
 └─ 👑 Tổng quản      — 1 ô Claude ở thư mục Hion. Bạn nói chuyện với nó.
     └─ 🧭 Manager     — mỗi dự án 1 ô Claude. Nhận việc từ Tổng quản, chia cho worker, gom kết quả.
         └─ Worker     — Engineer, Nội dung, Số liệu, Kiểm soát… Làm từng việc cụ thể.
```

- **Ô** = một khung trong cửa sổ WezTerm, mỗi ô chạy một AI.
- **Worker chạy ngầm 🌙** = worker **không có ô**, chạy trong nền. Màn hình gọn, máy không giật. Bạn chỉ thấy Tổng quản + các Manager.
- **Claude** (Claude Code) và **Codex** (của ChatGPT) là 2 loại AI. Claude giỏi viết tiếng Việt và điều phối; Codex giỏi code, số liệu, soát lỗi.

---

## 2. Cài đặt (làm 1 lần)

**Cần có:** Windows 10/11, tài khoản Claude (gói Pro/Max), tài khoản ChatGPT (để dùng Codex, không bắt buộc), ổ đĩa còn ~2 GB.

Mở **PowerShell** (bấm phím Windows, gõ `powershell`, Enter) rồi chạy lần lượt:

```powershell
winget install Git.Git GitHub.cli OpenJS.NodeJS.LTS wez.wezterm charmbracelet.glow
# đóng PowerShell, mở lại, rồi:
git clone https://github.com/hionvn/wezterm-ai E:\AI\wezterm-ai
cd E:\AI\wezterm-ai
powershell -ExecutionPolicy Bypass -File .\khoi-phuc.ps1 -CaiAI
```

- Máy không có ổ `E:` → thêm `-AIRoot D:\AI` vào cuối lệnh cuối.
- Bộ cài sao lưu mọi file cũ thành `*.bak-<giờ>` trước khi ghi đè — không mất gì.

**Đăng nhập AI** (trong PowerShell):
```powershell
claude        # làm theo hướng dẫn trên màn hình, xong gõ /exit
codex login   # nếu dùng Codex
```

**Kiểm tra:** `E:\AI\Hion\cai-dat\kiem-tra.ps1` — dòng nào ❌ thì làm theo gợi ý bên cạnh.

---

## 3. Ngày đầu tiên

1. Mở **WezTerm**. Hiện menu `ai` → chọn **Hion** → Enter (Claude). Đây là ô **Tổng quản**.
2. Đặt thư mục dự án của bạn vào `E:\AI\` (vd `E:\AI\ShopCuaToi`). Dự án mới tinh: gõ `newproj ShopCuaToi` trong PowerShell.
3. Nói với Tổng quản: **"khởi động đội"**. Nó hỏi từng dự án làm gì rồi tự tạo vai cho cả đội.
4. Tạo đội cho dự án: chép `E:\AI\wezterm-ai\mau\doi\VD.json` thành `E:\AI\Hion\doi\ShopCuaToi.json`, đổi `"du_an"` thành `ShopCuaToi`, sửa vai cho hợp (hoặc nhờ Tổng quản: *"tạo đội cho ShopCuaToi theo mẫu VD.json"*).
5. Mở đội: nói với Tổng quản *"mở đội ShopCuaToi"* — hoặc tự gõ `E:\AI\Hion\cai-dat\wez.ps1 doi ShopCuaToi`. Manager mở ở cửa sổ riêng, tự đọc dự án rồi bắt đầu giao việc cho worker.

---

## 4. Dùng hằng ngày

**Bạn chỉ cần làm 3 việc:**

| Việc | Làm thế nào |
|---|---|
| Ra lệnh | Gõ vào ô Tổng quản bằng lời thường: *"Shop: viết 5 bài đăng tuần này"*, *"tình hình hôm nay?"* |
| Duyệt việc quan trọng | Ô 📋 (`Ctrl+Shift+J`): mỗi việc có nút ✅ Duyệt · ✏️ Trả lời · ❌ Bỏ |
| Xem ai đang làm gì | Bảng 📊 (`Ctrl+Shift+U`) |

**AI tự làm, không hỏi bạn:** đọc/viết/sửa file trong dự án, chạy thử, commit trên máy, giao việc trong đội.
**AI luôn phải hỏi bạn (qua ô 📋):** tiêu tiền, gửi tin/đăng bài ra ngoài, xoá dữ liệu, đẩy code lên mạng (push/deploy), đổi giá.
Ngoài luật chữ còn có **hàng rào thật**: lệnh nguy hiểm (xoá cả ổ, push ép, xoá repo…) bị chặn cứng dù AI có lỡ chạy.

**Phím tắt hay dùng**

| Phím | Làm gì |
|---|---|
| `Ctrl+Shift+H` | Về tab Tổng quản |
| `Ctrl+Shift+U` | Bật/tắt bảng 📊 tổng quan đội |
| `Ctrl+Shift+J` | Bật/tắt ô 📋 việc chờ duyệt |
| `Ctrl+Shift+Space` | Nhảy tới ô theo tên (gõ để lọc) |
| `Ctrl+Shift+P` | Menu 10 việc hay dùng |
| `Ctrl+Shift+A` | Mở thêm AI ở dự án bất kỳ |
| `Ctrl+Shift+S` / `Ctrl+Shift+O` | Lưu / mở lại bố cục |

---

## 5. Worker chạy ngầm 🌙

Từ 06/10/2026 worker mặc định **chạy ngầm**: không mở ô, mỗi việc chạy một lần trong nền rồi tắt, nhưng **nhớ việc cũ** (tiếp đúng phiên). Lợi ích: 30 ô AI cùng vẽ chữ từng làm WezTerm giật; chạy ngầm thì WezTerm nhẹ hẳn.

**Bảng 📊** — worker ngầm có 🌙 trước tên:
`⏳ làm` đang chạy · `⌛ chờ` xếp hàng · `🟢 rảnh` xong, chờ việc · `⌛ hạn` quá giờ bị dừng · `⛔ lỗi`.

**Lệnh xem** (gõ trong PowerShell):
```powershell
node E:\AI\Hion\cai-dat\ngam.js ds                     # danh sách mọi worker ngầm + trạng thái
E:\AI\Hion\cai-dat\wez.ps1 read ShopCuaToi.Engineer     # 40 dòng nhật ký cuối của worker
E:\AI\Hion\cai-dat\wez.ps1 read ShopCuaToi.Engineer 100 -f   # xem trực tiếp, Ctrl+C để thoát
node E:\AI\Hion\cai-dat\ngam.js dung ShopCuaToi.Engineer     # dừng việc đang chạy
```
Nhật ký đọc được bằng mắt: 💬 AI nói gì · 🔧 lệnh đã chạy · ⛔ chỗ bị chặn/lỗi. Kết quả mỗi việc là 1 file trong `%LOCALAPPDATA%\wez-ai\ngam\ket-qua\`.

**Luật tự động:**
- Vai đang làm thì **không nhận việc mới** — báo "đang bận".
- Toàn máy chạy tối đa **N việc cùng lúc** (mặc định 4), dư thì xếp hàng.
- Mỗi việc tối đa **30 phút**; quá giờ thì dừng, file kết quả ghi rõ ⌛ QUÁ HẠN.
- Phiên quá dài (> 120.000 token) → tự tóm tắt rồi mở phiên mới, đỡ tốn hạn mức.
- Claude gần hết hạn mức (5 giờ ≥ 85% hoặc tuần ≥ 95%) → việc Claude mới tự xếp hàng tới khi hồi; việc Codex vẫn chạy.
- Worker xong → tự gõ 1 dòng 🌙 vào ô Manager để Manager giao việc kế ngay.

**Bật / tắt** — trong `E:\AI\Hion\doi\<dự án>.json`:
- `"ngam": true` ở đầu file → cả đội chạy ngầm.
- `"ngam": false` trong một vai → vai đó quay lại ô (rồi chạy `wez.ps1 doi <dự án>`).
- Vai luôn ở trong ô: vai dùng Grok, vai có `"rc": true` (điều khiển từ app Claude điện thoại), vai có `"giuO": "lý do"` (vd sửa hệ thống thật bằng Chrome — cần người xem).

**Chỉnh con số** — trong `C:\Users\<bạn>\.wez-ai.json`:
```json
"ngam": { "toiDa": 4, "phut": 30, "token": 120000, "claudeDung": 85, "claudeDungTuan": 95 }
```
`toiDa` càng cao càng nhanh nhưng càng tốn hạn mức. Gói Claude Max + 2 tài khoản ChatGPT Plus: 4–8 là vừa.

---

## 6. Hạn mức — điều người mới hay vấp

- Mỗi gói AI có **hạn mức 5 giờ** và **hạn mức tuần**. Hết thì AI dừng tới giờ hồi.
- Xem nhanh: dòng đầu bảng 📊 (⛽ Claude 5h …%) hoặc thanh trạng thái dưới mỗi ô Claude.
- Đội chạy hết công suất có thể ăn ~1% hạn mức 5 giờ mỗi phút. Muốn bền: để việc soát/số liệu/code cho Codex (`"ai": "codex"`), viết nội dung cho Claude.

---

## 7. Gặp sự cố

| Hiện tượng | Làm gì |
|---|---|
| WezTerm giật, gõ chậm | Đếm ô AI đang mở — bật chạy ngầm cho worker. Xem `%LOCALAPPDATA%\wez-ai\cham.log` |
| Cả máy chậm | `(Get-Process).Count` và `Get-Process chrome` — AI hay bỏ quên Chrome chạy ẩn |
| Bảng 📊 không có 🌙 | Bảng mở trước khi cập nhật → `Ctrl+Shift+U` hai lần |
| Worker ngầm báo ⛔ lỗi | `wez.ps1 read <Dự án>.<Vai>` xem dòng ⛔ cuối; thường do hết hạn mức hoặc chưa đăng nhập |
| Lỗi cài đặt lạ | `E:\AI\Hion\cai-dat\kiem-tra.ps1` |
| Muốn bỏ chế độ ngầm | Xoá `"ngam": true` trong file đội rồi `wez.ps1 doi <dự án>` |

**Cập nhật bản mới:** `Ctrl+Shift+P` → **⬆ Cập nhật đội AI**.

---

## 8. Ba lời khuyên

1. **Nói mục tiêu, đừng nói từng bước.** *"Tuần này cần 20 đơn từ khách cũ"* tốt hơn *"viết tin nhắn A rồi gửi B"*.
2. **Mỗi sáng xem ô 📋.** Đội chỉ kẹt khi chờ bạn duyệt.
3. **Tối gõ "tổng kết".** Tổng quản ghi nhật ký, lưu và đẩy code mọi dự án lên GitHub.
