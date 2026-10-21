#!/usr/bin/env bash
# setup-webview2.sh — cài WebView2 FIXED runtime 109.0.1518.78 vào prefix.
#
# Vì sao cần: launcher fco-vn.exe (Electron) và màn hình đăng nhập Garena dùng WebView2.
# Bản Evergreen mới (155.x) crash dưới Wine; bản FIXED 109 (bản cuối hỗ trợ Win7) chạy được.
# Xem chi tiết: NOTES-webview2-109.md
#
# CÁCH DÙNG:
#   bash setup-webview2.sh
#   FCO_PREFIX=/đường/dẫn/prefix bash setup-webview2.sh
#
# File cài đặt có sẵn trong dl/:
#   dl/MicrosoftEdgeWebview_X64.exe
set -u
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
PREFIX="${FCO_PREFIX:-$SCRIPT_DIR/prefix}"
DISPLAY="${FCO_DISPLAY:-${DISPLAY:-:1}}"
WINE="${FCO_WINE_UI:-wine}"
PAYLOAD="${WEBVIEW2_PAYLOAD:-$SCRIPT_DIR/dl/MicrosoftEdgeWebview_X64.exe}"

say() { echo "[$(date +%T)] $*"; }
die() {
  echo "[$(date +%T)] ✖ $*" >&2
  exit 1
}

[ -d "$PREFIX/drive_c/windows" ] || die "Prefix chưa có: $PREFIX — chạy: bash garena-setup.sh"
[ -f "$PAYLOAD" ] || die "Không thấy file cài WebView2: $PAYLOAD. Tải từ https://developer.microsoft.com/en-us/microsoft-edge/webview2/#download-section rồi đặt vào dl/MicrosoftEdgeWebview_X64.exe."
command -v "$WINE" >/dev/null 2>&1 || die "Không thấy wine trong PATH."

WINENV=(env WINEPREFIX="$PREFIX" WINEDEBUG=-all DISPLAY="$DISPLAY")
APPDIR="$PREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application"
GUID='{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'

say "Prefix: $PREFIX"
say "Gỡ WebView2 Evergreen mới (nếu có) để tránh xung đột..."
rm -rf "$APPDIR"/155.* 2>/dev/null || true
rm -rf "$PREFIX/drive_c/ProgramData/Microsoft/EdgeUpdate" 2>/dev/null || true
"${WINENV[@]}" "$WINE" reg delete "HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\EdgeUpdate\\Clients\\$GUID" /f >/dev/null 2>&1 || true

say "Cài WebView2 FIXED 109.0.1518.78 (có thể mất 1–3 phút)..."
"${WINENV[@]}" "$WINE" "$PAYLOAD" --msedgewebview --verbose-logging \
  --do-not-launch-msedge --system-level >>"$SCRIPT_DIR/log/webview2.log" 2>&1 &
pid=$!
for _ in $(seq 1 180); do
  compgen -G "$APPDIR/109.*" >/dev/null && break
  kill -0 "$pid" 2>/dev/null || break
  sleep 1
done

if ! compgen -G "$APPDIR/109.*" >/dev/null; then
  wait "$pid" 2>/dev/null || true
fi
compgen -G "$APPDIR/109.*" >/dev/null || die "Cài thất bại — xem $SCRIPT_DIR/log/webview2.log. Có thể chạy tay:
  WINEPREFIX=$PREFIX $WINE \"$PAYLOAD\" --msedgewebview --verbose-logging --do-not-launch-msedge --system-level"

say "Đặt cấu hình tương thích Win7 cho msedgewebview2.exe..."
"${WINENV[@]}" "$WINE" reg add "HKCU\\Software\\Wine\\AppDefaults\\msedgewebview2.exe" \
  /v Version /d win7 /f >/dev/null 2>&1 || true

say "Đặt WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS (fallback)..."
"${WINENV[@]}" "$WINE" reg add "HKCU\\Environment" \
  /v WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS /d "--no-sandbox --disable-gpu" /f >/dev/null 2>&1 || true

ver=$(basename "$(compgen -G "$APPDIR/109.*" | head -1)")
say "✔ WebView2 đã cài: $ver"
say "Tiếp theo: bash run.sh (đăng nhập Garena, cài FC Online), rồi bash fc-online.sh"
