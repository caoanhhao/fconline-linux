#!/usr/bin/env bash
# garena-setup.sh — Cài Garena PC (GPC) vào prefix Wine, đặt CÙNG THƯ MỤC với script,
# để chơi FC Online trên Linux. Tất cả dữ liệu thực sinh trong thư mục của script:
#
#   {thư mục script}/
#     garena-setup.sh, fc-online.sh   ← 2 script
#     prefix/                         ← WINEPREFIX mặc định (tự tạo)
#     dl/                             ← bộ cài GPC tải về + DXVK
#     log/                            ← nhật ký
#     data/                           ← args/log phụ (fc-online.sh tạo)
#     gamedata_backup/ (tuỳ chọn)     ← backup hardlink dữ liệu game
#
# CÁCH DÙNG:
#   ./garena-setup.sh                       # prefix = <thư mục script>/prefix
#   FCO_PREFIX=/đường/khác ./garena-setup.sh
#
# Tự xử lý: nếu tải GPC lỗi → hỏi nhập URL khác HOẶC đường dẫn file tải sẵn.
set -u
say() { echo "[$(date +%T)] $*"; }
die() {
  echo "[$(date +%T)] ✖ $*" >&2
  exit 1
}
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"

PREFIX="${FCO_PREFIX:-$SCRIPT_DIR/prefix}"
DISPLAY="${FCO_DISPLAY:-${DISPLAY:-:1}}"
DL_DIR="$SCRIPT_DIR/dl"
LOG_DIR="$SCRIPT_DIR/log"
LOG="$LOG_DIR/garena-setup.log"
URL="https://cdn.gxx.garenanow.com/gxx/pc/installer/Garena-v2.0.exe"
SETUP="$DL_DIR/Garena-v2.0.exe"
GPC_EXE1="$PREFIX/drive_c/Program Files (x86)/Garena/Garena/Garena.exe"
GPC_EXE2="$PREFIX/drive_c/Garena/GPC/Garena.exe"
mkdir -p "$PREFIX" "$DL_DIR" "$LOG_DIR"

command -v wine >/dev/null || die "Cần wine trong PATH (wine-11.x đã test)."
ts() { echo "[$(date +%F\ %T)] $*" >>"$LOG"; }

valid_pe() {
  local f="$1"
  [ -s "$f" ] && [ "$(stat -c%s "$f" 2>/dev/null)" -gt 1000000 ] && [ "$(head -c2 "$f" 2>/dev/null)" = "MZ" ]
}

# --- nhập tay URL hoặc file (khi tải tự động thất bại) ---
manual_get() {
  [ -t 0 ] || {
    echo "Tải thủ công từ https://www.garena.vn/gpc rồi đặt file vào:" >&2
    echo "  $SETUP (hoặc: FCO và chạy lại)" >&2
    return 1
  }
  local src
  while :; do
    read -r -p "⚠ Không tải được GPC tự động. Dán URL khác HOẶC đường dẫn file Garena-v2.0.exe (Enter = thoát): " src || return 1
    [ -z "${src// /}" ] && return 1
    case "$src" in
    http* | ftp*)
      say "Đang tải từ $src ..."
      curl -L --retry 1 --max-time 1800 -o "${SETUP}.dl" -- "$src" && mv -f "${SETUP}.dl" "$SETUP" || {
        say "tải lỗi — dán lại."
        continue
      }
      ;;
    *)
      [ -f "$src" ] || {
        say "file không tồn tại: $src — thử lại."
        continue
      }
      cp -f -- "$src" "$SETUP"
      ;;
    esac
    valid_pe "$SETUP" && return 0
    say "File không hợp lệ (cần PE exe > 1MB) — thử lại."
  done
}

# ---------- 1. Prefix ----------
if [ -f "$GPC_EXE1" ] || [ -f "$GPC_EXE2" ]; then
  say "GPC đã cài sẵn trong prefix — bỏ qua bước cài."
else
  say "Khởi tạo prefix: $PREFIX"
  WINEPREFIX=$PREFIX wineboot --init >/dev/null 2>&1 || true
  i=0
  while [ ! -d "$PREFIX/drive_c/windows" ] && [ $i -lt 40 ]; do
    sleep 3
    i=$((i + 1))
  done
  [ -d "$PREFIX/drive_c/windows" ] || die "wineboot không tạo được prefix — chạy tay: WINEPREFIX=$PREFIX wineboot -i và xem lỗi."

  # ---------- 2. DXVK ----------
  say "Cài DXVK (d3d11/dxgi = native — cần cho game)..."
  if command -v winetricks >/dev/null; then
    env WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY" winetricks -q dxvk >>"$LOG" 2>&1 && say "DXVK cài qua winetricks." ||
      say "winetricks dxvk lỗi — dùng đường tay bên dưới."
  fi
  if ! (env WINEPREFIX="$PREFIX" wine reg query "HKCU\\Software\\Wine\\DllOverrides" 2>/dev/null | grep -q dxgi); then
    DXVKTAR=$(curl -s --max-time 20 https://api.github.com/repos/doitsujin/dxvk/releases/latest | grep -oE '"browser_download_url": *"[^"]*\.tar\.gz"' | head -1 | grep -oE 'https[^"]*')
    if [ -n "$DXVKTAR" ]; then
      say "Tải DXVK: ${DXVKTAR##*/}"
      curl -sL --max-time 300 -o "$DL_DIR/dxvk.tar.gz" "$DXVKTAR" || say "tải DXVK lỗi (không chặn): cài bằng winetricks dxvk sau."
      if [ -s "$DL_DIR/dxvk.tar.gz" ]; then
        mkdir -p "$DL_DIR/dxvk" && tar xzf "$DL_DIR/dxvk.tar.gz" -C "$DL_DIR/dxvk" &&
          d=$(find "$DL_DIR/dxvk" -maxdepth 1 -type d -name "dxvk-*" | head -1) && {
          cp -f "$d/x64/"*.dll "$PREFIX/drive_c/windows/system32/" 2>/dev/null
          cp -f "$d/x32/"*.dll "$PREFIX/drive_c/windows/syswow64/" 2>/dev/null
        }
      fi
    fi
  fi
  for dll in d3d9 d3d10 d3d10core d3d10_1 d3d11 dxgi; do
    env WINEPREFIX="$PREFIX" wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v "$dll" /d native /f >/dev/null 2>&1
  done
  say "DXVK/dll overrides xong."

  # ---------- 3. GPC installer: tải (tự xử lý lỗi) + chạy ----------
  if ! valid_pe "$SETUP"; then
    say "Tải GPC installer (~70MB) từ CDN chính thức..."
    curl -L --retry 2 -C - --max-time 1800 -o "${SETUP}.dl" "$URL" 2>>"$LOG" && mv -f "${SETUP}.dl" "$SETUP"
    valid_pe "$SETUP" || {
      rm -f "${SETUP}.dl"
      manual_get
    }
    valid_pe "$SETUP" || die "bỏ qua GPC — đặt file đúng tên rồi chạy lại script."
  fi
  say "Chạy installer (/S = silent NSIS; nếu đứng yên sẽ hiện GUI — bạn bấm Next)."
  env WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY" WINEDEBUG=-all wine "$SETUP" /S >>"$LOG" 2>&1 &
  IPPID=$!
  i=0
  while [ ! -f "$GPC_EXE1" ] && [ ! -f "$GPC_EXE2" ] && [ $i -lt 60 ]; do # ~5 phút
    sleep 5
    i=$((i + 1))
    if ! kill -0 "$IPPID" 2>/dev/null && ! pgrep -f "Garena-v[.]2[.]0" >/dev/null; then
      say "Silent không hiệu quả — mở GUI installer, VUI LÒNG BẤM Next/Install trên màn hình."
      env WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY" WINEDEBUG=-all wine "$SETUP" >>"$LOG" 2>&1 &
      IPPID=$!
    fi
  done
  [ -f "$GPC_EXE1" ] || [ -f "$GPC_EXE2" ] || die "Không thấy Garena.exe sau 5 phút — chạy tay: wine $SETUP (bấm Next), rồi chạy lại."
  say "GPC đã cài: $([ -f "$GPC_EXE1" ] && echo "$GPC_EXE1" || echo "$GPC_EXE2")"
fi

# ---------- 4. Hướng dẫn tiếp theo ----------
say "✔ Bước 1/2 xong — GPC sẵn sàng (runtime: $(wine --version 2>/dev/null))."
cat >&2 <<NEXT

BƯỚC TIẾP THEO:
  1. Cài WebView2 109:  bash setup-webview2.sh
  2. Mở GPC:            bash run.sh
     → đăng nhập Garena, cài FC ONLINE (~28GB), chờ verify xong.
  3. Chơi:              bash fc-online.sh
     → launcher mở, bấm PLAY là vào game.

Mọi dữ liệu (prefix, backup, log) nằm trong: $SCRIPT_DIR
NEXT
