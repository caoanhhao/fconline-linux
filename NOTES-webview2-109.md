# WebView2 109 — chạy được FC Online SDK webview trên Wine 11.20 (2026-10-21)

## Trạng thái phát hiện
1. **Runtime Evergreen mới (155.0.4283.62) CHẾT dưới Wine** — msedge.dll 155
   `IMMEDIATE_CRASH` (int3/ud2) tại RVA 0x3870C7E, gần chuỗi
   `Failed to get activation factory for IPlatformDiagnosticsAndUsageDataSettingsStatics`
   (`base/win/edge_osconsent.cc`) + `Microsoft.EmbeddedBrowser.WebView.OOM.ProcessOOM.CommitUsagePct`.
   Wine chưa hỗ trợ các phần WinRT này; patch string/jmp chỉ kéo dài vài giây, không cứu được.
2. **Fix đúng chuẩn cộng đồng (cmo-on-linux / Fusion-360-on-Linux): dùng WebView2
   FIXED runtime 109.0.1518.78** (bản cuối chạy Win7 — bớt WinRT/telemetry).

## Đã cài trong thư mục này
- `dl/MSWebView2InstallerX64_109.exe` — bootstrapper 109 (github aedancullen archive).
- `dl/MicrosoftEdgeWebview_X64_109.0.1518.78.exe` — payload standalone (chạy được standalone;
  bootstrapper ban đầu báo "already has a more recent version" khi pv=155 vẫn còn).
- **Cài đặt theo trình tự đã chạy:**
  1) xoá `prefix/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application/155.0.4283.62`
     + `ProgramData/Microsoft/EdgeUpdate` + key registry
     `HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}`
  2) chạy payload: `wine dl/MicrosoftEdgeWebview_X64_109.0.1518.78.exe --msedgewebview --verbose-logging --do-not-launch-msedge --system-level`
  3) registry bất động hiện tại: `pv = 109.0.1518.78` (Clients GUID trên).
- `HKCU\Software\Wine\AppDefaults\msedgewebview2.exe` → `Version=win7` (bắt buộc theo recipe).
- `HKCU\Environment` → `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--no-sandbox --disable-gpu`
  (fallback; các spawn của fc-watch.sh tự set thêm env riêng).
- `fc-watch.sh` đã được gắn env `WEBVIEW2_BROWSER_EXECUTABLE_FOLDER` + args cho TẤT CẢ
  các spawn (GPC, fco-vn, fclauncher).
- `data/mswview2_109.exe` + `data/mswrap.c` — wrapper "msedgewebview2.exe" (chỉ thêm
  `--remote-debugging-port=9222` cho browser-process, children pass-through; version 109.0.1518.78).
  HIỆN KHÔNG cài (đổi name real↔main để SDK thấy exe thật). LƯU Ý: loader/SDK **cắt**
  `--remote-debugging-port` khỏi `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS`; chỉ wrapper
  đưa được port vào, NHƯNG browser có port + SDK host thì tree chết nhanh — đang
  để nguyên (không cần CDP khi flow chuẩn hoạt động).

## Kết quả test (05:30-05:50, 21/10/2026)
- Click "Login with Garena" trong fco-vn → SDK `Login()` (sdk_tap.log) → **SDK spawn
  webview2 109 THÀNH CÔNG, chuỗi process sống: browser + gpu + network + storage +
  renderer + audio, sống suốt phiên** (05:56→05:00, không crash, 0 dump crashpad mới).
- **Cửa sổ login Garena (webview) RENDER ĐÚNG** — logo, textbox username/password,
  "Login Now", "Register A New Account" (sh_j1.png, sh_k2.png).
- GPC 2.0.3653: login bằng account + password (remember) hoạt động qua
  wkeyhelper `click:568:415|Garena` (LOGIN button client coords trong dialog 742x570
  @(909,234) — đã dùng screenshoots tự đo).
- Game Center: tile FC Online mở bình thường (page FCOVN Full Live 0914).
- **Nút "Chơi" trên tile đang hiện "MAINTENANCE"** — ĐÚNG server thật đang bảo trì
  (fanpage EA Sports FC Online VN công bố maintenance 21.10.2026 từ ~04:00). статус
  `queryAppBasicInfo` trả `status:2` = maintenance. KẾT LUẬN: máy/Wine KHÔNG lỗi —
  chờ server mở lại (~09:00-11:00 sáng 21/10?) bấm Chơi là enters game.

## Cơ chế "Maintenance" (đã tra code launcher)
- Launcher/GPC đọc `-v1/game/query_app_basic_info` qua gpipe `game.garena.com/api/`.
  Nếu không query được → "no cached app basic info; defaulting to Launched" (still play).
  Nếu có response → status server (2 = maintenance).
- Lưu ý IP whitelist của launcher: "The launcher is ip whitelisted, set app status
  from maintenance to launched" — chỉ để khi server hoạt động mà bị region block.

## Việc còn lại khi server mở lại
1. `./fc-watch.sh` (đã có sẵn) — chờ GPC mở + login (nhớ Remember Password đã lưu).
2. Bấm tile FC Online → "Chơi" → stub12 chụp token tươi in-job → fco-vn boot với
   token → SDK Login() (3007 hết) → webview chỉ khi cần → **fczf.exe xuất hiện**.
3. Kết quả kỳ vọng theo completion criteria của goal.
