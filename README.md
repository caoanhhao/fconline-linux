# FC Online trên Linux — bộ cài đặt & hướng dẫn

Bộ file này giúp cài và chơi **FC Online (FIFA Online 4 VN, appId 32837)** trên Linux bằng Wine,
theo đúng luồng đã kiểm chứng:

```text
bash fc-online.sh  →  launcher FC Online  →  bấm PLAY  →  vào game
```

Đã test thành công trên Hyprland (Wayland), Wine hệ thống 11.20 + **Proton 9.0 hoặc GE-Proton10-34**
(đều là Wine 10) + DXVK, màn hình 2560×1080. Các DE/WM khác (GNOME, KDE, X11) cũng dùng được
miễn có `DISPLAY`/XWayland.

Script tự kiểm tra "sức khoẻ" của runtime Wine 10: nếu Proton 9.0 đã bị trộn DLL của bản khác
(ví dụ DLL Wine 11), script bỏ qua và chuyển sang GE-Proton10-34 nếu có.

---

## 1. Bộ file có gì?

| File / thư mục | Vai trò |
|---|---|
| `fc-online.sh` | **Script chính** — mở launcher, bắt `fclauncher`, chuyển sang Wine 10, chờ game |
| `garena-setup.sh` | Tạo prefix + cài Garena PC (GPC) + DXVK cho GPC |
| `setup-webview2.sh` | Cài WebView2 FIXED **109.0.1518.78** (bắt buộc cho màn hình đăng nhập) |
| `run.sh` | Mở Garena PC để đăng nhập / cài / cập nhật game |
| `backup-gamedata.sh` | Tạo backup hardlink dữ liệu game (tuỳ chọn, nên làm) |
| `check-deps.sh` | Kiểm tra Wine, Proton 9.0/GE-Proton10, DXVK, prefix, dung lượng, file cài |
| `dl/Garena-v2.0.exe` | Bộ cài Garena PC (~70 MB) |
| `dl/MicrosoftEdgeWebview_X64_109.0.1518.78.exe` | Bộ cài WebView2 109 (~135 MB) |
| `NOTES-webview2-109.md` | Ghi chú kỹ thuật về WebView2 |
| `TONG-HOP.md` | Tài liệu kỹ thuật đầy đủ (vì sao dùng 2 bản Wine, các lỗi đã gặp) |
| `prefix/` | *Sẽ được tạo* — ổ C: của Wine, chứa Garena + game |
| `dl/`, `data/`, `log/`, `gamedata_backup/` | File tải về, tham số/log, backup |

> Game ~28 GB không kèm trong bộ file. Bạn cài qua Garena PC (mục 4.5) hoặc chép prefix từ máy cũ
> (mục 7).

---

## 2. Yêu cầu

| Thành phần | Yêu cầu |
|---|---|
| CPU/OS | Linux x86_64, kernel hiện đại |
| GPU | Driver Vulkan hoạt động (Mesa/AMD, NVIDIA proprietary…) |
| Dung lượng | **≥ 45 GB** trống (game ~28 GB + prefix + tải về) |
| Wine hệ thống | **11.x** (đã test 11.20) — dùng cho launcher Electron `fco-vn.exe` |
| Proton 9.0 **hoặc** GE-Proton10 | Bắt buộc một trong hai — cung cấp Wine **10.0** cho `fclauncher.exe`/`fczf.exe`. Script tự bỏ qua runtime bị trộn DLL |
| Tài khoản | Tài khoản Garena có quyền chơi FC Online VN |
| Mạng | Tải Garena/game/WebView2 (nếu chưa có sẵn file) |

### Cài gói hệ thống

**Arch / Manjaro / CachyOS:**

```bash
sudo pacman -S --needed wine winetricks curl tar cabextract vulkan-icd-loader
```

**Ubuntu / Debian:** gói `wine` mặc định thường là bản cũ (9/10) — **không đủ** cho launcher.
Cài Wine 11 từ WineHQ (stable/staging), sau đó:

```bash
sudo apt install winetricks curl tar cabextract
```

**Fedora:**

```bash
sudo dnf install wine winetricks curl tar cabextract vulkan-loader
```

Kiểm tra:

```bash
wine --version     # phải là wine-11.x
```

> Nếu `wine --version` ra `wine-10.x`, launcher `fco-vn.exe` có thể crash ngay khi tạo cửa sổ.
> Nâng lên Wine 11 trước khi tiếp tục.

### Cài Proton 9.0 (hoặc GE-Proton10)

**Cách 1 — Proton 9.0 trong Steam (ưu tiên):**

1. Mở Steam → **Library** → ô tìm kiếm gõ `Proton 9.0`.
2. Chọn **Proton 9.0** → **Install** (hoặc mở `steam://install/2805730`).
3. Đường dẫn mặc định:

   ```text
   ~/.local/share/Steam/steamapps/common/Proton 9.0/
   ```

Script tự tìm đường dẫn này. Nếu Proton nằm ở thư viện Steam khác:

```bash
export FCO_WINE10="$HOME/path/Steam/steamapps/common/Proton 9.0/files/bin/wine64"
```

**Cách 2 — GE-Proton10-34 (khi Proton 9 hỏng hoặc Steam không cài được):**

GE-Proton10-34 cũng là **Wine 10.0** nên qua được Themida của `fclauncher.exe`. Cài bằng
**ProtonUp-Qt**, hoặc tải tarball từ GitHub `GloriousEggroll/proton-ge-custom` rồi giải nén vào:

```text
~/.steam/steam/compatibilitytools.d/GE-Proton10-34/
```

Kiểm tra version thật:

```bash
~/.steam/steam/compatibilitytools.d/GE-Proton10-34/files/bin/wine64 --version
# → wine-10.0 (Staging)
```

Script tự dò mọi `GE-Proton10-*` (ưu tiên `-34`) trong
`~/.steam/steam/compatibilitytools.d/` và `~/.local/share/Steam/compatibilitytools.d/`.
Có thể chỉ định thủ công:

```bash
export FCO_WINE10="$HOME/.steam/steam/compatibilitytools.d/GE-Proton10-34/files/bin/wine64"
```

> **Quan trọng:** không trộn DLL giữa các bản Proton — đặc biệt **không copy DLL Wine 11 vào
> Proton 9**. Script kiểm tra `advapi32.dll` có forward sang `cryptbase` nhưng thiếu `cryptbase.dll`,
> và so mtime `ntdll.dll`/`advapi32.dll`; runtime bị trộn sẽ bị bỏ qua kèm cảnh báo.
> Proton 9 bị hỏng có thể khôi phục bằng Steam → Library → Proton 9.0 → Properties →
> Installed Files → **Verify integrity of tool files**.

> Không cần bật Steam khi chơi; chỉ cần thư mục runtime tồn tại trên đĩa.

---

## 3. Cài đặt nhanh (tóm tắt)

```bash
cd ~/fconline
bash check-deps.sh        # kiểm tra môi trường
bash garena-setup.sh      # tạo prefix + cài Garena PC
bash setup-webview2.sh    # cài WebView2 109
bash run.sh               # đăng nhập Garena, cài FC Online (~28 GB)
bash backup-gamedata.sh   # tuỳ chọn: backup hardlink
bash fc-online.sh         # chơi
```

Chi tiết từng bước ở mục 4.

---

## 4. Cài đặt chi tiết

### 4.1. Đặt bộ file

Chép cả thư mục `fconline` sang máy mới, ví dụ:

```bash
# từ máy cũ (nếu có) hoặc giải nén file zip
rsync -av ~/projects/fconline/ maymoi:~/projects/fconline/
```

Mọi thứ được tính tương đối theo thư mục này. Có thể đổi tên/đổi vị trí tuỳ ý
(không dùng đường dẫn tuyệt đối trong script).

### 4.2. Kiểm tra phụ thuộc

```bash
cd ~/projects/fconline
bash check-deps.sh
```

Kết quả mong đợi: `0 lỗi`. Cảnh báo về `winetricks` hoặc dung lượng có thể bỏ qua
nếu bạn đã có đủ.

### 4.3. Tạo prefix + cài Garena PC

```bash
bash garena-setup.sh
```

Script sẽ:

- tạo `prefix/` (Wine prefix, mặc định dùng Wine hệ thống 11.x);
- cài DXVK cho GPC (qua `winetricks` hoặc tải trực tiếp từ GitHub);
- chạy bộ cài Garena (`dl/Garena-v2.0.exe`).

Nếu bộ cài im lặng không chạy, cửa sổ GUI sẽ hiện ra — bấm **Next/Install**.
Thời gian: 2–5 phút.

Kết thúc bạn sẽ thấy:

```text
✔ Bước 1/2 xong — GPC sẵn sàng
```

### 4.4. Cài WebView2 109

```bash
bash setup-webview2.sh
```

Vì sao cần bản 109: WebView2 Evergreen mới (155.x) **crash dưới Wine** do thiếu WinRT;
bản FIXED 109.0.1518.78 (bản cuối hỗ trợ Win7) chạy ổn. Script sẽ:

- xoá WebView2 155 nếu có;
- cài payload 109 từ `dl/`;
- đặt `Version=win7` cho `msedgewebview2.exe`;
- đặt `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--no-sandbox --disable-gpu`.

Kiểm tra:

```bash
ls "prefix/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application"
# → 109.0.1518.78
```

> Nếu chưa cài bước này, GPC/launcher có thể mở nhưng màn hình đăng nhập trắng hoặc crash.

### 4.5. Đăng nhập Garena và cài FC Online

```bash
bash run.sh
```

1. Đăng nhập tài khoản Garena (tick **Remember Password** nếu muốn lần sau tự đăng nhập).
2. Tìm **FC Online** → **Install/Cài đặt**.
3. Chờ tải + verify (~28 GB). **Không đóng GPC** trong lúc cài.
4. Tải game xong, đóng GPC.

Game được cài vào:

```text
prefix/drive_c/Garena/Games/32837/
```

Nếu GPC báo **MAINTENANCE**: đó là trạng thái server, không phải lỗi Wine. Vẫn có thể cài game;

### 4.6. Backup dữ liệu (khuyến nghị)

```bash
bash backup-gamedata.sh
```

Tạo `gamedata_backup/image/` bằng **hardlink** — gần như không tốn thêm dung lượng, cùng ổ đĩa.
`fc-online.sh` dùng backup này để tự khôi phục nếu cây `data` bị thiếu file `.big`.

### 4.7. Chơi

```bash
bash fc-online.sh
```

Luồng sẽ diễn ra:

1. Launcher FC Online mở bằng **Wine 11** (đăng nhập nếu cần).
2. Bạn bấm **PLAY**.
3. Launcher gọi `fclauncher.exe` kèm token tươi.
4. Script phát hiện process này, lưu tham số, kill nó.
5. Script chạy lại **đúng tham số** bằng **Wine 10 + DXVK** trong `prefix/compat-wine10`.
6. `fczf.exe` khởi động fullscreen → vào game.

Trước đó script tự kiểm tra:

- **Runtime Wine 10:** nếu Proton 9.0 bị trộn DLL, script in `⚠ Bỏ qua ...: DLL builtin bị trộn/hỏng`
  và dùng GE-Proton10-34 (nếu có). Đây là hành vi đúng, không phải lỗi.
- **Prefix phụ:** nếu `compat-wine10` được tạo bởi runtime khác, script tạo lại prefix
  (cấu hình đồ hoạ lưu trong prefix game có thể trở về mặc định).
- **Chống chạy trùng:** chỉ một `fc-online.sh` được chạy tại một thời điểm. Nếu có cửa sổ khác
  đang chờ PLAY, script mới sẽ báo `Đã có fc-online.sh khác đang chạy` và thoát.

Lần đầu có thể mất 10–30 giây. Các lần sau nhanh hơn.

---

## 5. Chơi hằng ngày

```bash
cd ~/projects/fconline
bash fc-online.sh
```

- Nếu launcher còn phiên đăng nhập: bấm **PLAY** luôn.
- Nếu báo **hết phiên** / mã `30000532`: đóng launcher, chạy lại script, đăng nhập lại rồi bấm PLAY.
- Nếu game đang chạy sẵn: script chỉ focus cửa sổ, không mở thêm.
- **Chỉ chạy một `fc-online.sh`.** Đừng mở nhiều terminal rồi chạy song song — hai script sẽ
  giành nhau bắt/kill `fclauncher`, làm game biến mất ngay sau khi bấm PLAY. Script đã có
  `flock` chặn việc này; nếu thấy thông báo `Đã có fc-online.sh khác đang chạy`, hãy dùng
  cửa sổ cũ thay vì mở thêm.

Có thể tạo alias:

```bash
echo "alias fco='bash $HOME/projects/fconline/fc-online.sh'" >> ~/.bashrc
# sau đó: fco
```

---

## 6. Cách hoạt động (ngắn gọn)

```text
fco-vn.exe (Electron, Wine 11)
   │  đọc game.json, gọi kèm token
   ▼
fclauncher.exe (Themida)  ──►  deadlock trên Wine 11
   │  script bắt /proc/<pid>/cmdline
   ▼
fclauncher.exe chạy lại bằng Wine 10 + DXVK
   ▼
fczf.exe  →  game
```

- `prefix/` — prefix chính, chứa Garena + game, do Wine 11 quản lý.
- `prefix/compat-wine10/` — prefix phụ cho Wine 10; `C:\Garena` là symlink tuyệt đối
  trỏ về `prefix/drive_c/Garena`, nên không nhân đôi 28 GB.
- **Chọn runtime:** Proton 9.0 sạch được ưu tiên; nếu bị trộn DLL, script dùng
  `GE-Proton10-*` (ưu tiên `-34`). Mọi ứng viên phải báo `wine-10.*`.
- **Kiểm tra sức khoẻ:** bỏ qua runtime nếu `advapi32.dll` forward `SystemFunction036` sang
  `cryptbase` nhưng thiếu `cryptbase.dll`, hoặc mtime `ntdll.dll`/`advapi32.dll` lệch > 7 ngày.
- **Prefix phụ:** file `.fco-runtime` ghi runtime đã tạo prefix; nếu runtime đổi, prefix được
  tạo lại từ `default_pfx`. **Mọi** symlink trong `drive_c/windows` (kể cả `system32/drivers/`)
  được đổi sang đường dẫn tuyệt đối — chỉ sửa `system32`/`syswow64` cấp 1 sẽ làm driver không load.
- DXVK và `libvkd3d` được copy cho **cả 64-bit (`system32`) và 32-bit (`syswow64`)** —
  `wbemprox`/anti-cheat 32-bit cũng cần `dxgi`. Sau đó override bằng
  `WINEDLLOVERRIDES="d3d10core,d3d11,d3d8,d3d9,dxgi=n"`.
- **Một instance:** `flock` trên `data/launcher.lock` ngăn hai script cùng bắt/kill `fclauncher`.

Chi tiết đầy đủ (vì sao không dùng `wineboot`, các lỗi đã gặp, token…) xem `TONG-HOP.md`.

---

## 7. Chuyển prefix từ máy cũ

Nếu đã có `prefix/` chứa Garena + game từ máy khác:

1. Copy `prefix/` sang cùng vị trí trong thư mục bộ file (hoặc chỉ `prefix/drive_c/Garena`
   nếu muốn cài Garena lại bằng `garena-setup.sh`).
2. Chạy `bash check-deps.sh` — cảnh báo symlink hỏng là bình thường.
3. Chạy `bash fc-online.sh` một lần: script tạo lại `prefix/compat-wine10`, sửa **mọi** symlink
   và copy DXVK 64-bit + 32-bit trước khi mở launcher.
4. Nếu Proton/GE-Proton nằm ở đường dẫn khác, đặt `FCO_WINE10` trước khi chạy.

Không cần copy `prefix/compat-wine10` từ máy khác nếu runtime khác — script sẽ xoá và tạo lại.

---

## 8. Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `Không tìm thấy Wine 10 sạch` | Chưa cài Proton 9.0/GE-Proton10, hoặc mọi runtime đều hỏng | Cài Proton 9.0 hoặc GE-Proton10-34; đặt `FCO_WINE10`; chạy `bash check-deps.sh` |
| `⚠ Bỏ qua ...: DLL builtin bị trộn/hỏng` | Proton 9 bị ghi đè DLL của bản khác (Wine 11) | Bình thường nếu máy có GE-Proton10 — script tự dùng bản đó. Muốn sửa Proton 9: Steam → Verify integrity of tool files. **Không copy DLL giữa các bản Proton** |
| `fclauncher10.log` báo `unimplemented function advapi32.dll.SystemFunction036` / thiếu `cryptbase.dll` | Runtime Wine 10 không đồng bộ (DLL Wine 11 trộn với Wine 10) | Dùng GE-Proton10-34 hoặc Verify Proton 9.0; không chép DLL từ GE-Proton11 sang Proton 9 |
| Bấm PLAY xong launcher/game biến mất, có nhiều terminal đang chạy | Nhiều `fc-online.sh` chạy song song, giành bắt/kill `fclauncher` | Chỉ giữ **một** cửa sổ; kiểm tra `pgrep -af fc-online.sh`; script đã có `flock` chặn |
| `Đã có fc-online.sh khác đang chạy` | Instance khác đang giữ lock | Dùng cửa sổ cũ; đóng terminal cũ nếu treo. Không mở thêm instance |
| Launcher crash ngay khi mở | Wine hệ thống < 11 | Nâng Wine lên 11.x |
| `Could Not Get Primary Adapter Handle` | Thiếu DXVK (64-bit hoặc 32-bit) trong `compat-wine10` | Chạy lại `fc-online.sh`; kiểm tra `check-deps.sh`; cài driver Vulkan |
| Màn hình đăng nhập trắng / launcher treo | Thiếu/sai WebView2 | `bash setup-webview2.sh`, kiểm tra thư mục `109.0.1518.78` |
| Game lỗi driver/`.sys`, vào rồi thoát | Symlink hỏng trong `compat-wine10` (nhất là `system32/drivers/`) | Xoá `prefix/compat-wine10` rồi chạy lại — script tạo prefix mới và sửa **mọi** symlink |
| `게임파일 변조가 감지되었습니다` | Tham số/token dính `\r` hoặc token cũ | Chạy lại `fc-online.sh` để lấy token mới |
| `Hết phiên` / `30000532` | Token hết hạn | Đóng launcher, chạy lại, đăng nhập, bấm PLAY |
| `Bạn chỉ có thể chơi game trên 1 nền tảng` | Còn `fczf.exe`/`fclauncher.exe` cũ | `pkill -f fczf; pkill -f fclauncher` rồi bấm PLAY lại |
| Game đứng ở 99,7% CPU, không vào | `fclauncher` chạy bằng Wine 11 | Đảm bảo script chọn đúng Wine 10 — xem dòng `Wine 10:` khi chạy (Proton 9 hoặc GE-Proton10) |
| `wineboot` treo ở “Wine Mono Installer” | Tạo prefix bằng `wineboot` trên Proton | Không làm vậy; script copy `default_pfx` |
| Cây data thiếu `.big` | File bị xoá/hỏng | Chạy `backup-gamedata.sh` trước đó, rồi `fc-online.sh` tự khôi phục |
| Lỗi tải Garena | CDN đổi link | Tải tay từ <https://www.garena.vn/gpc>, đặt vào `dl/Garena-v2.0.exe` |
| Click PLAY không phản hồi | Launcher mất focus | Click vào cửa sổ launcher rồi bấm lại |

Xem log khi cần:

```bash
tail -f log/fco-vn.log          # launcher UI
tail -f log/fclauncher10.log    # fclauncher chạy bằng Wine 10
tail -f log/garena-setup.log    # quá trình cài GPC
```

Kiểm tra game đang chạy:

```bash
pgrep -af -- '-garenaToken'
tr '\0' '\n' </proc/$(pgrep -f -- '-garenaToken' | head -1)/environ | grep WINEPREFIX
# → .../prefix/compat-wine10
```

---

## 9. Biến môi trường

| Biến | Mặc định | Ý nghĩa |
|---|---|---|
| `FCO_PREFIX` | `./prefix` | Đổi vị trí prefix |
| `FCO_WINE10` | tự tìm Proton 9.0 sạch → `GE-Proton10-*` (ưu tiên 34) | Đường dẫn `wine64` bản Wine 10. **Đặt biến này sẽ bỏ qua bước kiểm tra sức khoẻ** |
| `FCO_PROTON9` | — | Thư mục Proton 9.0/GE-Proton10 khác (được thử đầu tiên và vẫn qua kiểm tra sức khoẻ) |
| `FCO_COMPAT_PREFIX` | `prefix/compat-wine10` | Prefix phụ cho game; đổi runtime sẽ khiến prefix được tạo lại |
| `FCO_DXVK_SRC` | runtime Wine 10 đã chọn: `lib/wine/dxvk/x86_64-windows` | Nguồn DXVK; script tự lấy bản `i386-windows` bên cạnh |
| `FCO_DISPLAY` | `$DISPLAY` hoặc `:1` | Display khi chạy Wine |
| `WEBVIEW2_PAYLOAD` | `dl/MicrosoftEdgeWebview_X64_109.0.1518.78.exe` | Bộ cài WebView2 khác |

Ví dụ đặt prefix ở ổ khác:

```bash
FCO_PREFIX=/mnt/games/fconline bash fc-online.sh
```

---

## 10. Gỡ cài đặt

```bash
cd ~/projects/fconline
# đóng game/launcher trước
WINEPREFIX="$PWD/prefix" wineserver -k 2>/dev/null || true
rm -rf prefix gamedata_backup data log
```

Giữ lại script + `dl/` nếu muốn cài lại. Không cần xoá gì trong `~/.local/share/Steam`.

---

## 11. Lưu ý

- Đây là công cụ cá nhân để chạy game trên Linux; việc dùng phụ thuộc điều khoản của Garena/EA.
- Không chia sẻ thư mục `prefix/` hoặc file chứa token: chúng gắn với tài khoản của bạn.
- Không dùng token cũ (`data/launch_capture.last.txt`, `token_fresh.txt`) — luôn để launcher cấp token mới.
- Game update: chỉ cần mở `run.sh` (GPC) để cập nhật, sau đó chạy `fc-online.sh`.
- **Không trộn DLL** giữa Proton 9.0, GE-Proton10 và Proton 11. Nếu Proton 9 đã bị trộn, đừng
  "sửa" bằng cách copy thêm DLL — script sẽ bỏ qua runtime đó và chuyển sang GE-Proton10.
- `prefix/compat-wine10` là prefix phụ, **có thể xoá và tạo lại** mà không mất dữ liệu game.
  Cấu hình đồ hoạ lưu trong prefix này sẽ về mặc định khi runtime đổi.
- Nếu copy prefix sang máy khác, luôn chạy qua `fc-online.sh` một lần để script sửa **mọi**
  symlink (kể cả `system32/drivers/`) trước khi vào game.

---

## 12. Tài liệu tham khảo trong bộ file

- `TONG-HOP.md` — nhật ký điều tra, kiến trúc, lỗi và cách khắc phục chi tiết.
- `NOTES-webview2-109.md` — vì sao phải dùng WebView2 109 và cách cài thủ công.
