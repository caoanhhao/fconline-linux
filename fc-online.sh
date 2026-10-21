#!/usr/bin/env bash
# fc-online.sh — FC Online (FIFA Online 4 VN, appId 32837) trên Linux/Wine — một lệnh.
#
# CÁCH DÙNG:
#   bash fc-online.sh
#   (tuỳ chọn) FCO_PREFIX=/đường/dẫn/prefix bash fc-online.sh
#
# LUỒNG CHẠY:
#   1. Mở launcher FC Online (fco-vn.exe) bằng Wine hệ thống trong prefix gốc.
#   2. Bạn đăng nhập (nếu cần) rồi bấm PLAY.
#   3. Launcher gọi mojitodata/fclauncher.exe kèm token tươi.
#      fclauncher (Themida) bị deadlock dưới Wine 11.20, nên script bắt đúng
#      cmdline của process đó, kill nó, rồi chạy lại y nguyên bằng Wine 10.
#   4. Game fczf.exe boot bằng Wine 10 + DXVK trong prefix phụ
#      prefix/compat-wine10 (ổ C:\Garena trỏ về prefix/drive_c/Garena).
#
# VÌ SAO KHÔNG CÒN STUB launch_fco.exe:
#   fco-vn đọc manifest và gọi thẳng fclauncher.exe, không đi qua launch_fco.exe.
#   launch_fco.exe chỉ dùng cho luồng GPC. Script giữ bản thật và tự dựng cây
#   symlink root -> mojitodata (phần prepareData của wrapper) để cây data lành.
#
# LỖI BIẾT TRƯỚC:
#   - "Hết phiên" / 30000532 = token cũ → bấm PLAY lại trong launcher.
#   - fco-vn cần WebView2 109 trong prefix gốc nếu phải đăng nhập lại
#     (xem NOTES-webview2-109.md).
#   - Nếu game báo "Could Not Get Primary Adapter Handle": thiếu DXVK trong
#     prefix/compat-wine10 — script tự copy từ Wine 10 (Proton 9 / GE-Proton10).
#
# LƯU Ý WINE 10:
#   Script kiểm tra "sức khoẻ" của Proton 9 trước khi dùng. Nếu thư mục
#   lib/wine/x86_64-windows đã bị trộn DLL Wine 11 (advapi32 forward sang
#   cryptbase nhưng thiếu cryptbase.dll), script tự chuyển sang GE-Proton10-34
#   (cũng là Wine 10) nếu có. Đừng copy DLL từ GE-Proton11 vào Proton 9.
set -u
say() { echo "[$(date +%T)] $*"; }
warn() { echo "[$(date +%T)] ⚠ $*" >&2; }
die() {
  echo "[$(date +%T)] ✖ $*" >&2
  exit 1
}
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"

# ---------- 1. Tìm prefix + game ----------
PREFIX=""
GAME=""
find_game_in() {
  local g
  for g in "drive_c/Garena/Games/32837" "drive_c/Garena/Game/32837"; do
    if [ -d "$1/$g" ]; then
      PREFIX="$1"
      GAME="$1/$g"
      return 0
    fi
  done
  return 1
}
[ -n "${FCO_PREFIX:-}" ] && find_game_in "$FCO_PREFIX"
[ -z "$GAME" ] && find_game_in "${FCO_PREFIX:-$(pwd -P)/prefix}"
[ -z "$GAME" ] && find_game_in "$SCRIPT_DIR/prefix"
if [ -z "$GAME" ]; then # tương thích prefix cũ kiểu Heroic/Steam
  shopt -s nullglob
  for c in "$HOME"/Games/Heroic/Prefixes/*/pfx/ "$HOME"/Games/Heroic/Prefixes/*/ \
    "$HOME"/Games/*/*/pfx/ "$HOME"/Games/*/*/ "$HOME"/Games/*/pfx/ "$HOME"/Games/*/; do
    find_game_in "${c%/}" && break
  done
  shopt -u nullglob
fi
[ -n "$GAME" ] || die "Không tìm thấy game. Cài lại: ./garena-setup.sh (prefix ở ./prefix), hoặc export FCO_PREFIX=... rồi chạy lại."
say "Prefix: $PREFIX"
say "Game:   $GAME"
LOG_DIR="$SCRIPT_DIR/log"
mkdir -p "$LOG_DIR" "$SCRIPT_DIR/data"
# Chỉ một instance: tránh 2 script cùng bắt/kill fclauncher khiến game biến mất.
exec 9>"$SCRIPT_DIR/data/launcher.lock"
if command -v flock >/dev/null 2>&1; then
  flock -n 9 || die "Đã có fc-online.sh khác đang chạy (cùng thư mục). Đóng cửa sổ đó rồi thử lại."
fi

# ---------- 2. Chọn Wine 10 (Proton 9 / GE-Proton10) cho game ----------
wine10_healthy() {
  local base="$1" dir="$1/files/lib/wine/x86_64-windows" t1 t2
  [ -d "$dir" ] || return 0
  # Proton 9 từng bị trộn DLL Wine 11: advapi32 forward SystemFunction036 sang
  # cryptbase nhưng runtime lại thiếu cryptbase.dll -> fclauncher abort.
  if grep -aq 'cryptbase.SystemFunction036' "$dir/advapi32.dll" 2>/dev/null &&
    [ ! -e "$dir/cryptbase.dll" ]; then
    return 1
  fi
  # Các builtin phải cùng một đợt build. Lệch > 7 ngày = đã bị trộn phiên bản.
  t1=$(stat -c %Y "$dir/ntdll.dll" 2>/dev/null) || return 0
  t2=$(stat -c %Y "$dir/advapi32.dll" 2>/dev/null) || return 0
  [ $((t1 > t2 ? t1 - t2 : t2 - t1)) -le 604800 ] || return 1
  return 0
}

find_wine10() {
  local base cand ver seen=""
  # Proton 9 sạch được ưu tiên; GE-Proton10 là phương án dự phòng khi Proton 9
  # đã bị trộn DLL (máy này) nhưng vẫn là Wine 10 nên qua được Themida.
  for base in "${FCO_PROTON9:-}" \
    "$HOME/.local/share/Steam/steamapps/common/Proton 9.0" \
    "$HOME/.steam/steam/steamapps/common/Proton 9.0" \
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/Proton 9.0" \
    "$HOME/.steam/steam/compatibilitytools.d/GE-Proton10-34" \
    "$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton10-34" \
    "$HOME"/.steam/steam/compatibilitytools.d/GE-Proton10-* \
    "$HOME"/.local/share/Steam/compatibilitytools.d/GE-Proton10-* \
    "$HOME"/.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d/GE-Proton10-* \
    "$HOME/.local/share/Steam/steamapps/common/Proton - Experimental"; do
    [ -n "$base" ] || continue
    [ -d "$base/files" ] || continue
    base="$(readlink -f "$base")"
    # .steam/steam thường là symlink của .local/share/Steam — chỉ thử một lần.
    case " $seen " in *" $base "*) continue ;; esac
    seen="$seen $base"
    # Themida của fclauncher chỉ qua được Wine 10, nên kiểm tra version thật.
    for cand in "$base/files/bin/wine64" "$base/files/bin/wine"; do
      [ -x "$cand" ] || continue
      ver=$("$cand" --version 2>/dev/null)
      case "$ver" in
      wine-10.*) ;;
      *) continue ;;
      esac
      if ! wine10_healthy "$base"; then
        warn "Bỏ qua $base: DLL builtin bị trộn/hỏng."
        break
      fi
      printf '%s\n' "$cand"
      return 0
    done
  done
  return 1
}
if [ -n "${FCO_WINE10:-}" ]; then
  WINE10="$FCO_WINE10"
else
  WINE10="$(find_wine10)" || WINE10=""
fi
[ -n "$WINE10" ] && [ -x "$WINE10" ] || die "Không tìm thấy Wine 10 sạch (Proton 9 / GE-Proton10). Cài Proton 9 trong Steam, cài GE-Proton10-34, hoặc đặt FCO_WINE10=/đường/dẫn/wine64."
PROTON_FILES="$(cd "$(dirname "$WINE10")/.." && pwd -P)"
DXVK_SRC="${FCO_DXVK_SRC:-$PROTON_FILES/lib/wine/dxvk/x86_64-windows}"
say "Wine 10: $WINE10"

command -v wine >/dev/null || die "Cần wine hệ thống trong PATH để mở launcher UI."
WINEUI="$(command -v wine)"

# ---------- 3. Prefix phụ cho Wine 10 + DXVK ----------
COMPAT="${FCO_COMPAT_PREFIX:-$PREFIX/compat-wine10}"
DEFAULT_PFX="$PROTON_FILES/share/default_pfx"

ensure_compat() {
  local runtime_id marker
  runtime_id="$(readlink -f "$DEFAULT_PFX")"
  marker="$COMPAT/.fco-runtime"
  case "$COMPAT" in
  "" | "/" | "$PREFIX" | "$PREFIX/") die "Đường dẫn prefix phụ không hợp lệ: $COMPAT" ;;
  esac
  # Prefix được tạo bởi runtime khác (Proton 9 hỏng -> GE-Proton10): tạo lại.
  if [ -f "$COMPAT/system.reg" ] && [ "$(cat "$marker" 2>/dev/null)" != "$runtime_id" ]; then
    say "Prefix Wine 10 dùng runtime khác — tạo lại $COMPAT..."
    rm -rf -- "$COMPAT" || die "Không xoá được $COMPAT."
  fi
  if [ ! -f "$COMPAT/system.reg" ]; then
    [ -d "$DEFAULT_PFX" ] || die "Không thấy $DEFAULT_PFX để tạo prefix Wine 10."
    say "Tạo prefix Wine 10: $COMPAT (copy default_pfx, tránh hộp thoại Wine Mono)..."
    mkdir -p "$COMPAT"
    cp -a "$DEFAULT_PFX/." "$COMPAT/" || die "copy default_pfx thất bại."
    # Mọi symlink trong default_pfx là đường dẫn tương đối; đổi sang tuyệt đối,
    # kể cả drivers/ và các thư mục con (chỉ sửa system32 thì driver không load).
    local l rel src
    while IFS= read -r -d '' l; do
      rel="${l#"$COMPAT"/}"
      src="$DEFAULT_PFX/$rel"
      if [ -L "$src" ] && [ -e "$src" ]; then
        ln -sfn "$(readlink -f "$src")" "$l"
      elif [ -f "$src" ] && [ ! -e "$l" ]; then
        ln -sfn "$src" "$l"
      fi
    done < <(find "$COMPAT/drive_c/windows" -type l -print0 2>/dev/null)
    mkdir -p "$COMPAT/dosdevices"
    ln -sfn ../drive_c "$COMPAT/dosdevices/c:"
    ln -sfn / "$COMPAT/dosdevices/z:"
    printf '%s\n' "$runtime_id" >"$marker"
  fi

  mkdir -p "$COMPAT/drive_c"
  if [ "$(readlink -f "$COMPAT/drive_c/Garena" 2>/dev/null)" != "$(readlink -f "$PREFIX/drive_c/Garena")" ]; then
    ln -sfn "$PREFIX/drive_c/Garena" "$COMPAT/drive_c/Garena"
  fi

  # Prefix copy từ máy khác: sửa MỌI symlink hỏng (tương đối lẫn tuyệt đối),
  # gồm cả system32/drivers/*.sys mà bản cũ bỏ sót.
  local l rel src appdata realapp
  while IFS= read -r -d '' l; do
    [ -e "$l" ] && continue
    rel="${l#"$COMPAT"/}"
    src="$DEFAULT_PFX/$rel"
    if [ -L "$src" ] && [ -e "$src" ]; then
      ln -sfn "$(readlink -f "$src")" "$l"
    elif [ -f "$src" ]; then
      ln -sfn "$src" "$l"
    fi
  done < <(find "$COMPAT/drive_c/windows" -type l -print0 2>/dev/null)
  appdata="$COMPAT/drive_c/users/steamuser/AppData"
  if [ -L "$appdata" ] && [ ! -e "$appdata" ]; then
    realapp=$(find "$PREFIX/drive_c/users" -mindepth 2 -maxdepth 2 -type d -name AppData 2>/dev/null | head -1)
    [ -n "$realapp" ] && ln -sfn "$realapp" "$appdata"
  fi

  # DXVK 64-bit + 32-bit (wbemprox/anti-cheat 32-bit vẫn cần dxgi).
  if [ -d "$DXVK_SRC" ]; then
    local arch dll srcdir dstdir
    for arch in x86_64 i386; do
      if [ "$arch" = x86_64 ]; then
        srcdir="$DXVK_SRC"
        dstdir=system32
      else
        srcdir="$(dirname "$DXVK_SRC")/i386-windows"
        dstdir=syswow64
      fi
      [ -d "$srcdir" ] || continue
      for dll in d3d10core d3d11 d3d8 d3d9 dxgi; do
        src="$srcdir/$dll.dll"
        dst="$COMPAT/drive_c/windows/$dstdir/$dll.dll"
        [ -f "$src" ] || continue
        if ! cmp -s "$src" "$dst" 2>/dev/null; then
          cp -f --remove-destination "$src" "$dst"
        fi
      done
    done
  else
    warn "Không thấy DXVK ở $DXVK_SRC — game có thể báo 'Could Not Get Primary Adapter Handle'."
  fi
  # libvkd3d 64-bit + 32-bit.
  local arch f srcdir dstdir
  for arch in x86_64 i386; do
    if [ "$arch" = x86_64 ]; then
      srcdir="$PROTON_FILES/lib/wine/x86_64-windows"
      dstdir=system32
    else
      srcdir="$PROTON_FILES/lib/wine/i386-windows"
      dstdir=syswow64
    fi
    [ -d "$srcdir" ] || continue
    for f in libvkd3d-1.dll libvkd3d-shader-1.dll; do
      src="$srcdir/$f"
      dst="$COMPAT/drive_c/windows/$dstdir/$f"
      if [ -f "$src" ]; then
        if ! cmp -s "$src" "$dst" 2>/dev/null; then
          cp -f --remove-destination "$src" "$dst"
        fi
      fi
    done
  done
}

# ---------- 4. Cây data: root -> mojitodata ----------
prep_tree() {
  local d f b
  # thư mục dùng chung
  for d in data locales Xigncode; do
    if [ -d "$GAME/mojitodata/$d" ]; then
      [ -e "$GAME/$d" ] || ln -s "mojitodata/$d" "$GAME/$d"
    fi
  done
  # file dùng chung ở root (game/fczf đọc từ root)
  shopt -s nullglob
  for f in "$GAME"/mojitodata/*; do
    b="${f##*/}"
    [ -f "$f" ] || continue
    case "$b" in
    customoptions.ini | stub_out.txt | launch_capture.txt | 'Xigncode:'*) continue ;;
    esac
    [ -e "$GAME/$b" ] || ln -sfn "mojitodata/$b" "$GAME/$b"
  done
  shopt -u nullglob
  # thư mục runtime
  for d in _cache instance0 instance1 screenshot; do
    [ -d "$GAME/$d" ] || mkdir -p "$GAME/$d" 2>/dev/null || true
  done
  # rác mklink của Wine: "data?" thay vì "data"
  for d in data locales Xigncode; do
    if [ -d "$GAME/$d?" ] && [ ! -e "$GAME/$d" ]; then
      mv "$GAME/$d?" "$GAME/$d" && say "Sửa thư mục rác Wine: $d? → $d"
    fi
  done
}

# ---------- 5. Sức khoẻ dữ liệu (chỉ cảnh báo / khôi phục nếu có backup) ----------
health_check() {
  local nb backup="$SCRIPT_DIR/gamedata_backup/image"
  nb=$(find -L "$GAME/mojitodata/data" -name '*.big' 2>/dev/null | wc -l)
  if [ "$nb" -lt 100 ] && [ -d "$backup" ]; then
    say "Cây data thiếu ($nb .big) — khôi phục từ backup..."
    local n=0 src rel dst
    while IFS= read -r -d '' src; do
      rel="${src#"$backup"/}"
      dst="$GAME/$rel"
      if [ ! -f "$dst" ] || [ "$(stat -c%s "$dst" 2>/dev/null)" != "$(stat -c%s "$src")" ]; then
        mkdir -p "$(dirname "$dst")"
        cp -al -- "$src" "$dst" 2>/dev/null && n=$((n + 1))
      fi
    done < <(find "$backup" -type f -print0 2>/dev/null | sort -z -u)
    say "Khôi phục xong: $n file."
    nb=$(find -L "$GAME/mojitodata/data" -name '*.big' 2>/dev/null | wc -l)
  fi
  [ "$nb" -ge 100 ] && say "Cây data: $nb file .big — khoẻ." || warn "Cây data chỉ có $nb file .big — game có thể không vào được."
}

# ---------- 6. Tiến trình ----------
game_running() {
  local p s
  for p in $(pgrep -f -- '-garenaToken' 2>/dev/null); do
    s=$(ps -o stat= -p "$p" 2>/dev/null)
    case "$s" in Z* | "") ;; *) return 0 ;; esac
  done
  return 1
}
ui_running() {
  local p s
  for p in $(pgrep -f 'fco-vn\.exe' 2>/dev/null); do
    s=$(ps -o stat= -p "$p" 2>/dev/null)
    case "$s" in Z* | "") ;; *) return 0 ;; esac
  done
  return 1
}
find_fclauncher_pid() {
  local p cmd
  for p in /proc/[0-9]*; do
    [ -r "$p/cmdline" ] || continue
    cmd=$(tr '\0' '\n' <"$p/cmdline" 2>/dev/null) || continue
    case "$cmd" in
    *fclauncher.exe*/goptoken:* | *fclauncher.exe*/encryptedtoken:*)
      printf '%s\n' "${p#/proc/}"
      return 0
      ;;
    esac
  done
  return 1
}

focus_game() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  local pid
  pid=$(pgrep -f -- '-garenaToken' 2>/dev/null | head -1)
  [ -n "$pid" ] && hyprctl dispatch "hl.dsp.focus({ window = \"pid:$pid\" })" >/dev/null 2>&1 || true
}

# ---------- 7. Chuẩn bị ----------
# launch_fco.exe: bỏ stub cũ (nếu có), giữ bản thật cho luồng GPC.
if [ -f "$GAME/launch_fco.exe.real" ]; then
  sz=$(stat -c%s "$GAME/launch_fco.exe" 2>/dev/null || echo 0)
  if [ ! -f "$GAME/launch_fco.exe" ] || [ "$sz" -lt 100000 ]; then
    cp -f "$GAME/launch_fco.exe.real" "$GAME/launch_fco.exe" && say "Khôi phục launch_fco.exe thật (bỏ stub cũ)."
  fi
fi

prep_tree
ensure_compat
health_check

if game_running; then
  say "FC Online đang chạy sẵn — mở cửa sổ FC ONLINE lên chơi thôi!"
  focus_game
  exit 0
fi

# Dọn fclauncher cũ còn treo (token cũ) để không bắt nhầm.
for p in $(find_fclauncher_pid); do
  kill -9 "$p" 2>/dev/null || true
done

# ---------- 8. Mở launcher UI (Wine hệ thống) ----------
WEBVIEW2_DIR=""
for d in "$PREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application/109."*; do
  [ -d "$d" ] && WEBVIEW2_DIR="$d" && break
done
WEBVIEW2_WIN=""
if [ -n "$WEBVIEW2_DIR" ]; then
  rel="${WEBVIEW2_DIR#"$PREFIX/drive_c/"}"
  WEBVIEW2_WIN="C:\\$(printf '%s' "$rel" | sed 's#/#\\#g')"
fi

start_ui() {
  local -a envs=(WINEPREFIX="$PREFIX" WINEDEBUG=-all DISPLAY="${DISPLAY:-:1}"
    WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--no-sandbox\ --disable-gpu)
  [ -n "$WEBVIEW2_WIN" ] && envs+=("WEBVIEW2_BROWSER_EXECUTABLE_FOLDER=$WEBVIEW2_WIN")
  (
    cd "$GAME" && nohup env "${envs[@]}" "$WINEUI" launcher/fco-vn.exe >>"$LOG_DIR/fco-vn.log" 2>&1 9>&- &
    disown
  ) 2>/dev/null
}

if ! ui_running; then
  say "Mở launcher FC Online (đăng nhập nếu cần, rồi bấm PLAY)..."
  start_ui
else
  say "Launcher FC Online đang mở — bấm PLAY trong cửa sổ đó."
fi

# ---------- 9. Bắt fclauncher của launcher, chạy lại bằng Wine 10 ----------
say "Chờ bạn bấm PLAY (tối đa 10 phút)..."
deadline=$((SECONDS + 600))
while [ "$SECONDS" -lt "$deadline" ]; do
  if game_running; then
    say "✔ FC ONLINE đã vào game — chúc chơi vui!"
    focus_game
    exit 0
  fi
  if pid=$(find_fclauncher_pid); then
    tr '\0' '\n' <"/proc/$pid/cmdline" >"$SCRIPT_DIR/data/fclauncher.args" 2>/dev/null || true
    say "Bắt được fclauncher (pid $pid) — chuyển sang Wine 10 + DXVK..."
    kill -9 "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
    # dọn các fclauncher còn lại của Wine 11 (nếu bấm PLAY nhiều lần)
    for p in $(find_fclauncher_pid); do kill -9 "$p" 2>/dev/null || true; done
    mapfile -t ARGS < <(tr -d '\r' <"$SCRIPT_DIR/data/fclauncher.args")
    [ "${#ARGS[@]}" -gt 0 ] || {
      warn "Không đọc được tham số fclauncher."
      continue
    }
    (
      cd "$GAME" && nohup env WINEPREFIX="$COMPAT" WINEDEBUG=-all DISPLAY="${DISPLAY:-:1}" \
        WINEDLLOVERRIDES="d3d10core,d3d11,d3d8,d3d9,dxgi=n" \
        "$WINE10" "${ARGS[@]}" >>"$LOG_DIR/fclauncher10.log" 2>&1 9>&- &
      disown
    ) 2>/dev/null
    break
  fi
  sleep 1
done

# ---------- 10. Chờ fczf ----------
for _ in $(seq 1 120); do
  if game_running; then
    say "✔ FC ONLINE đã vào game bằng Wine 10 — chúc chơi vui!"
    focus_game
    exit 0
  fi
  sleep 1
done
die "Không thấy fczf.exe khởi động. Xem: $LOG_DIR/fclauncher10.log và $LOG_DIR/fco-vn.log"
