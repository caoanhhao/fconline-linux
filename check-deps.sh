#!/usr/bin/env bash
# check-deps.sh — kiểm tra nhanh máy đã đủ điều kiện chạy FC Online chưa.
#   bash check-deps.sh
set -u
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
PREFIX="${FCO_PREFIX:-$SCRIPT_DIR/prefix}"
ok=0
bad=0
warn=0

say_ok() { printf '  ✔ %s\n' "$*"; ok=$((ok + 1)); }
say_bad() { printf '  ✖ %s\n' "$*"; bad=$((bad + 1)); }
say_warn() { printf '  ⚠ %s\n' "$*"; warn=$((warn + 1)); }

echo "== Kiểm tra môi trường =="

if command -v wine >/dev/null 2>&1; then
  v=$(wine --version 2>/dev/null | sed 's/^wine-//')
  major=${v%%.*}
  if [ "${major:-0}" -ge 11 ] 2>/dev/null; then
    say_ok "Wine hệ thống: $v (dùng cho launcher UI)"
  else
    say_warn "Wine hệ thống: $v — cần 11.x cho launcher Electron (đã test 11.20)"
  fi
else
  say_bad "Thiếu wine trong PATH"
fi

wine10_healthy() {
  local base="$1" dir="$1/files/lib/wine/x86_64-windows" t1 t2
  [ -d "$dir" ] || return 0
  if grep -aq 'cryptbase.SystemFunction036' "$dir/advapi32.dll" 2>/dev/null &&
    [ ! -e "$dir/cryptbase.dll" ]; then
    return 1
  fi
  t1=$(stat -c %Y "$dir/ntdll.dll" 2>/dev/null) || return 0
  t2=$(stat -c %Y "$dir/advapi32.dll" 2>/dev/null) || return 0
  [ $((t1 > t2 ? t1 - t2 : t2 - t1)) -le 604800 ] || return 1
  return 0
}

WINE10=""
WINE10_VERSION=""
SEEN=""
for p in "${FCO_WINE10:-}" \
  "$HOME/.local/share/Steam/steamapps/common/Proton 9.0/files/bin/wine64" \
  "$HOME/.steam/steam/steamapps/common/Proton 9.0/files/bin/wine64" \
  "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/Proton 9.0/files/bin/wine64" \
  "$HOME/.steam/steam/compatibilitytools.d/GE-Proton10-34/files/bin/wine64" \
  "$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton10-34/files/bin/wine64" \
  "$HOME"/.steam/steam/compatibilitytools.d/GE-Proton10-*/files/bin/wine64 \
  "$HOME"/.local/share/Steam/compatibilitytools.d/GE-Proton10-*/files/bin/wine64 \
  "$HOME"/.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d/GE-Proton10-*/files/bin/wine64; do
  [ -n "$p" ] && [ -x "$p" ] || continue
  v=$("$p" --version 2>/dev/null)
  case "$v" in
  wine-10.*) ;;
  *)
    say_warn "Bỏ qua $p: $v (cần wine-10.*)"
    continue
    ;;
  esac
  base=$(cd "$(dirname "$p")/../.." && pwd -P)
  case " $SEEN " in *" $base "*) continue ;; esac
  SEEN="$SEEN $base"
  if ! wine10_healthy "$base"; then
    say_warn "Bỏ qua $base: DLL builtin bị trộn/hỏng"
    continue
  fi
  WINE10="$p"
  WINE10_VERSION="$v"
  break
done

if [ -n "$WINE10" ]; then
  PF="$(cd "$(dirname "$WINE10")/.." && pwd -P)"
  say_ok "Wine 10: $WINE10_VERSION — $WINE10"
  [ -d "$PF/lib/wine/dxvk/x86_64-windows" ] && say_ok "DXVK 64-bit" || say_warn "Không thấy DXVK 64-bit trong $PF"
  [ -d "$PF/lib/wine/dxvk/i386-windows" ] && say_ok "DXVK 32-bit" || say_warn "Không thấy DXVK 32-bit (wbemprox/anti-cheat có thể lỗi dxgi)"
  [ -d "$PF/share/default_pfx" ] && say_ok "default_pfx (tạo prefix Wine 10)" || say_bad "Thiếu $PF/share/default_pfx"
else
  say_bad "Không thấy runtime Wine 10 sạch — cài Proton 9.0 hoặc GE-Proton10-34, hoặc đặt FCO_WINE10"
fi

for c in curl tar bash; do
  command -v "$c" >/dev/null 2>&1 && say_ok "Có $c" || say_bad "Thiếu $c"
done
command -v winetricks >/dev/null 2>&1 && say_ok "Có winetricks (tuỳ chọn, cài DXVK cho GPC)" || say_warn "Không có winetricks (garena-setup.sh vẫn tự tải DXVK)"
command -v flock >/dev/null 2>&1 && say_ok "Có flock (chống chạy trùng fc-online.sh)" || say_warn "Không có flock — vẫn chạy được nhưng dễ mở trùng script"

if [ -f "$SCRIPT_DIR/dl/Garena-v2.0.exe" ]; then
  say_ok "Có sẵn bộ cài Garena trong dl/"
else
  say_warn "Không có dl/Garena-v2.0.exe — garena-setup.sh sẽ tự tải"
fi
if [ -f "$SCRIPT_DIR/dl/MicrosoftEdgeWebview_X64_109.0.1518.78.exe" ]; then
  say_ok "Có sẵn WebView2 109 trong dl/"
else
  say_warn "Không có WebView2 109 trong dl/ — cần cho màn hình đăng nhập"
fi

free_gb=$(df -Pk "$SCRIPT_DIR" | awk 'NR==2 {printf "%d", $4/1024/1024}')
if [ "${free_gb:-0}" -ge 45 ]; then
  say_ok "Dung lượng trống: ${free_gb} GB"
else
  say_warn "Dung lượng trống: ${free_gb} GB — nên có ≥ 45 GB (game ~28 GB + prefix)"
fi

if [ -d "$PREFIX/drive_c/windows" ]; then
  say_ok "Prefix đã tạo: $PREFIX"
else
  say_warn "Chưa có prefix — chạy: bash garena-setup.sh"
fi

COMPAT="${FCO_COMPAT_PREFIX:-$PREFIX/compat-wine10}"
if [ -d "$COMPAT/drive_c/windows" ]; then
  n=$(find "$COMPAT/drive_c/windows" -xtype l 2>/dev/null | wc -l)
  if [ "$n" -eq 0 ]; then
    say_ok "Prefix game symlink lành: $COMPAT"
  else
    say_warn "Prefix game có $n symlink hỏng — chạy fc-online.sh để sửa (hoặc xoá $COMPAT để tạo lại)"
  fi
fi

echo
echo "Kết quả: $ok OK, $warn cảnh báo, $bad lỗi."
[ "$bad" -eq 0 ] || exit 1
