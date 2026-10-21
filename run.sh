#!/usr/bin/env bash
# run.sh — mở Garena PC (GPC) trong prefix của thư mục này.
# Dùng để đăng nhập và cài/cập nhật FC Online lần đầu.
set -u
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
PREFIX="${FCO_PREFIX:-$SCRIPT_DIR/prefix}"
DISPLAY="${FCO_DISPLAY:-${DISPLAY:-:1}}"

GPC="$PREFIX/drive_c/Garena/GPC/Garena.exe"
ALT="$PREFIX/drive_c/Program Files (x86)/Garena/Garena/Garena.exe"
if [ ! -f "$GPC" ] && [ ! -f "$ALT" ]; then
  echo "✖ Chưa thấy Garena PC trong $PREFIX"
  echo "  Chạy trước: bash garena-setup.sh"
  exit 1
fi
[ -f "$GPC" ] || GPC="$ALT"

echo "Mở Garena PC: $GPC"
echo "Đăng nhập → cài/cập nhật FC Online → đóng GPC rồi chạy: bash fc-online.sh"
cd "$PREFIX/drive_c" || exit 1
exec env WINEPREFIX="$PREFIX" WINEDEBUG=-all DISPLAY="$DISPLAY" wine "$GPC"
