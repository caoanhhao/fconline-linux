#!/usr/bin/env bash
# backup-gamedata.sh — backup HARDLINK dữ liệu game (mojitodata/), không tốn thêm dung lượng.
#
# Nguyên tắc:
#   - Garena/launcher làm hỏng file bằng cách XOÁ file. Hardlink giữ lại inode gốc → chỉ cần
#     link lại từ backup là có file lành, tức thì.
#   - Backup gắn với đúng buildId hiện tại (gamedata_backup/BUILD). Khác build → không dùng để
#     phục hồi (file bản cũ không chơi được), chỉ tạo lại.
#   - Chỉ backup khi dữ liệu game đang LÀNH: chạy pipe.exe verify của launcher trước.
#
# CÁCH DÙNG (đóng launcher/game trước):
#   bash backup-gamedata.sh            # tạo/làm mới backup cho build hiện tại (sau mỗi lần cập nhật)
#   bash backup-gamedata.sh --restore  # link lại file bị xoá/bị thay từ backup
#   bash backup-gamedata.sh --status   # build của game/backup + số file đang thiếu
#   FCO_SKIP_VERIFY=1 bash backup-gamedata.sh   # bỏ qua bước verify (không khuyến khích)
set -u
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
PREFIX="${FCO_PREFIX:-$SCRIPT_DIR/prefix}"
GAME=""
for g in "drive_c/Garena/Games/32837" "drive_c/Garena/Game/32837"; do
  [ -d "$PREFIX/$g" ] && GAME="$PREFIX/$g" && break
done
ROOT="$SCRIPT_DIR/gamedata_backup"
BACKUP="$ROOT/image"
STAMP="$ROOT/BUILD"
# thư mục/file runtime trong mojitodata — không phải file game, không backup
RUNTIME=(_cache instance0 instance1 screenshot customoptions.ini)

say() { echo "[$(date +%T)] $*"; }
die() {
  echo "[$(date +%T)] ✖ $*" >&2
  exit 1
}
[ -n "$GAME" ] || die "Không thấy game trong $PREFIX — cài FC Online bằng GPC trước."
DATA="$GAME/mojitodata"
[ -d "$DATA" ] || die "Không thấy $DATA — game chưa cài đủ."

# buildId + signature hiện tại, đọc từ game.json của launcher
BUILD=$(grep -o '"buildId": *[0-9]*' "$GAME/game.json" 2>/dev/null | grep -o '[0-9]*$')
SIGOBJ=$(grep -o '"signatureName": *"[^"]*"' "$GAME/game.json" 2>/dev/null | sed 's/.*: *"//; s/"$//')
SIG="${SIGOBJ##*/}"
CDN="https://fco-mojito.cdn.garenanow.com"
[ -n "$BUILD" ] && [ -n "$SIG" ] || die "Không đọc được buildId/signature từ $GAME/game.json."
bak_build() { sed -n 's/^buildId=//p' "$STAMP" 2>/dev/null; }

game_running() { pgrep -xi 'fco-vn\.exe|fclauncher\.exe|fczf\.exe|pipe\.exe' >/dev/null; }

# Liệt kê file bị lệch trong file wounds (.pww, định dạng wharf/protobuf của pipe.exe)
list_wounds() {
  python3 -I - "$1" <<'EOF'
import sys
b = open(sys.argv[1], 'rb').read()
def varint(b, i):
    r = s = 0
    while True:
        c = b[i]; i += 1; r |= (c & 0x7f) << s; s += 7
        if c < 0x80: return r, i
def fields(m):
    i = 0; out = []
    while i < len(m):
        k, i = varint(m, i); t = k & 7
        if t == 0: v, i = varint(m, i)
        elif t == 2: l, i = varint(m, i); v = m[i:i + l]; i += l
        elif t == 1: v = m[i:i + 8]; i += 8
        elif t == 5: v = m[i:i + 4]; i += 4
        else: raise SystemExit("bad wounds file")
        out.append((k >> 3, v))
    return out
i = 4; msgs = []
while i < len(b):
    l, i = varint(b, i); msgs.append(b[i:i + l]); i += l
cont = fields(msgs[1])
tbl = {0: [dict(fields(v)) for f, v in cont if f == 1], 3: None,
       2: [dict(fields(v)) for f, v in cont if f == 2],
       1: [dict(fields(v)) for f, v in cont if f == 3]}
tbl[3] = tbl[0]
seen = set()
for m in msgs[2:]:
    w = dict(fields(m)); e = tbl[w.get(4, 0)][w.get(1, 0)]
    p = e[1].decode(errors='replace')
    if p not in seen: seen.add(p); print(p)
EOF
}

# Chỉ dùng chữ ký đúng build: launcher xoá .sig sau khi cập nhật → tải lại từ CDN
fetch_sig() {
  local f="$ROOT/$SIG"
  if [ ! -s "$f" ]; then
    if [ -s "$DATA/$SIG" ]; then
      cp -- "$DATA/$SIG" "$f"
    else
      say "Tải signature build $BUILD: $CDN/$SIGOBJ"
      curl -sSfL --retry 3 -o "$f.part" "$CDN/$SIGOBJ" && mv -f "$f.part" "$f" ||
        die "Không tải được signature (mạng?)."
    fi
  fi
  find "$ROOT" -maxdepth 1 -name 'signature_*.mojito.sig' ! -name "$SIG" -delete
}

verify_game() {
  [ "${FCO_SKIP_VERIFY:-0}" = 1 ] && {
    say "Bỏ qua verify (FCO_SKIP_VERIFY=1)."
    return 0
  }
  mkdir -p "$ROOT"
  fetch_sig
  local wounds="$ROOT/verify.pww" rc bad
  rm -f "$wounds"
  say "Kiểm tra dữ liệu game bằng pipe.exe verify (build $BUILD, ~1 phút)..."
  (cd "$GAME" && WINEPREFIX="$PREFIX" WINEDEBUG=-all wine \
    'C:\Garena\Games\32837\launcher\pipe.exe' verify \
    "Z:$(tr / '\\' <<<"$ROOT/$SIG")" 'C:\Garena\Games\32837\mojitodata' \
    --wounds_path="Z:$(tr / '\\' <<<"$wounds")" 2>&1) | tr '\r' '\n' |
    grep -E 'wound|corrupted|check finish' | sed 's/^/    /'
  rc=${PIPESTATUS[0]}
  if [ "$rc" -ne 0 ]; then
    [ -s "$wounds" ] || die "pipe.exe verify lỗi (code $rc), không có file wounds — không backup."
    # Xigncode (anti-cheat) tự ghi lại file .xem của nó mỗi lần chạy game → không tính là hỏng
    bad=$(list_wounds "$wounds" | grep -v '^Xigncode/') || true
    list_wounds "$wounds" | grep '^Xigncode/' | sed 's/^/    bỏ qua (anti-cheat tự ghi): /'
    if [ -n "$bad" ]; then
      sed 's/^/    HỎNG: /' <<<"$bad"
      die "Dữ liệu game KHÔNG lành — không backup. Sửa game trước (--restore nếu backup cùng build, hoặc repair trong launcher)."
    fi
  fi
  rm -f "$wounds"
  say "✔ Dữ liệu game lành (build $BUILD)."
}

# Duyệt file trong backup: in ra "missing <rel>" (game mất file) hoặc "replaced <rel>"
# (game có file nhưng không còn là inode của backup — đã bị xoá rồi tạo lại).
scan() {
  local src rel dst
  while IFS= read -r -d '' src; do
    rel="${src#"$BACKUP"/}"
    dst="$DATA/$rel"
    if [ ! -e "$dst" ]; then
      echo "missing $rel"
    elif [ ! "$dst" -ef "$src" ]; then
      echo "replaced $rel"
    fi
  done < <(find "$BACKUP" -type f -print0)
}

need_same_build() {
  [ -f "$STAMP" ] && [ -d "$BACKUP" ] || die "Chưa có backup."
  [ "$(bak_build)" = "$BUILD" ] ||
    die "Backup là build $(bak_build), game là build $BUILD — không phục hồi được (dùng repair trong launcher)."
}

case "${1:-}" in
--status)
  echo "Game:   build $BUILD ($SIG)"
  if [ -f "$STAMP" ]; then
    echo "Backup: build $(bak_build) — tạo lúc $(sed -n 's/^date=//p' "$STAMP")"
    if [ "$(bak_build)" = "$BUILD" ]; then
      r=$(scan)
      echo "→ cùng build. Thiếu: $(grep -c '^missing' <<<"$r"), bị thay: $(grep -c '^replaced' <<<"$r")"
    else
      echo "→ KHÁC build, không dùng được. Chạy: bash backup-gamedata.sh"
    fi
  else
    echo "Backup: chưa có."
  fi
  ;;

--restore)
  # --replaced: link lại cả file bị thay (mặc định chỉ file bị xoá — file bị thay có thể là
  # do launcher repair hợp lệ, hoặc cấu hình người dùng)
  game_running && die "Launcher/game đang chạy — đóng hết rồi chạy lại."
  need_same_build
  n=0
  while read -r kind rel; do
    if [ "$kind" = missing ] || [ "${2:-}" = --replaced ]; then
      mkdir -p "$(dirname "$DATA/$rel")"
      ln -f -- "$BACKUP/$rel" "$DATA/$rel" && n=$((n + 1)) && echo "    $kind → link lại: $rel"
    else
      echo "    bỏ qua (bị thay, dùng --restore --replaced để link lại): $rel"
    fi
  done < <(scan)
  say "✔ Phục hồi xong: $n file."
  ;;

"" | --force)
  game_running && die "Launcher/game đang chạy — đóng hết rồi chạy lại."
  if [ "${1:-}" != --force ] && [ "$(bak_build)" = "$BUILD" ] && [ -d "$BACKUP" ]; then
    say "Backup đã là build $BUILD — không cần làm lại. (Ép tạo lại: --force)"
    exit 0
  fi
  [ -f "$STAMP" ] && say "Backup cũ: build $(bak_build) → thay bằng build $BUILD."
  verify_game
  rm -f "$STAMP" # chưa xong thì không được coi là backup hợp lệ
  rm -rf -- "$BACKUP"
  mkdir -p "$BACKUP"
  say "Đang tạo hardlink backup (nhanh, không copy dữ liệu)..."
  cp -al -- "$DATA/." "$BACKUP/" || die "cp -al thất bại (backup phải cùng ổ đĩa với game)."
  for d in "${RUNTIME[@]}"; do rm -rf -- "${BACKUP:?}/$d"; done
  find "$BACKUP" -maxdepth 1 -name 'Xigncode:*' -delete
  printf 'buildId=%s\nsignature=%s\ndate=%s\n' "$BUILD" "$SIG" "$(date '+%F %T')" >"$STAMP"
  n=$(find "$BACKUP/data" -name '*.big' 2>/dev/null | wc -l)
  say "✔ Xong: backup build $BUILD, $n file .big trong $BACKUP"
  ;;

*) die "Tham số không hợp lệ: $1 (dùng: --status | --restore [--replaced] | --force)" ;;
esac
