#!/usr/bin/env bash
# backup-gamedata.sh — tạo bản backup hardlink cho dữ liệu game (không tốn thêm dung lượng).
#
# fc-online.sh dùng backup này để tự khôi phục khi cây data bị thiếu/hỏng:
#   gamedata_backup/image/<cây file game>
#
# CÁCH DÙNG (sau khi đã cài game xong):
#   bash backup-gamedata.sh
#
# LƯU Ý: hardlink cùng ổ đĩa → sửa file tại chỗ sẽ ảnh hưởng cả backup.
# Backup chỉ cứu được trường hợp mất file/ghi đè/xoá nhầm, không cứu hỏng nội dung.
set -u
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
PREFIX="${FCO_PREFIX:-$SCRIPT_DIR/prefix}"
GAME=""
for g in "drive_c/Garena/Games/32837" "drive_c/Garena/Game/32837"; do
  [ -d "$PREFIX/$g" ] && GAME="$PREFIX/$g" && break
done
BACKUP="$SCRIPT_DIR/gamedata_backup/image"

say() { echo "[$(date +%T)] $*"; }
die() {
  echo "[$(date +%T)] ✖ $*" >&2
  exit 1
}
[ -n "$GAME" ] || die "Không thấy game trong $PREFIX — cài FC Online bằng GPC trước."
[ -d "$GAME/mojitodata" ] || die "Không thấy $GAME/mojitodata — game chưa cài đủ."

if [ -d "$BACKUP" ] && [ -n "$(ls -A "$BACKUP" 2>/dev/null)" ]; then
  say "Backup đã tồn tại: $BACKUP"
  say "Không ghi đè. Muốn tạo lại: xoá thư mục đó rồi chạy lại."
  exit 0
fi

mkdir -p "$BACKUP"
say "Đang tạo hardlink backup (nhanh, không copy dữ liệu)..."
cp -al -- "$GAME/." "$BACKUP/" || die "cp -al thất bại (backup phải cùng ổ đĩa với game)."
n=$(find "$BACKUP/mojitodata/data" -name '*.big' 2>/dev/null | wc -l)
say "✔ Xong: $n file .big trong $BACKUP"
