#!/bin/sh
# Build a stock-format AD5X update package that flashes the Kalico MCU
# firmware with FlashForge's own updater. See README.md.
#
#   AD5X_REFERENCE=<stock AD5X update .tgz or extracted dir> \
#   AD5X_FW_DIR=<dir with AD5X-mainboard.bin AD5X-eboard.hex AD5X-ifs.hex> \
#   ./build.sh
#
# AD5X_FW_DIR defaults to ../opencreator-fs/mcu-firmware/ad5x.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REF=${AD5X_REFERENCE:?set AD5X_REFERENCE to a stock AD5X update .tgz or extracted dir}
FW=${AD5X_FW_DIR:-$HERE/../opencreator-fs/mcu-firmware/ad5x}
WORK=$HERE/work
DIST=$HERE/dist

die() { echo "build.sh: $*" >&2; exit 1; }

for f in AD5X-mainboard.bin AD5X-eboard.hex AD5X-ifs.hex; do
    [ -f "$FW/$f" ] || die "missing $FW/$f"
done
[ ! -f "$FW/SHA256SUMS" ] || (cd "$FW" && sha256sum -c SHA256SUMS >/dev/null) \
    || die "firmware does not match $FW/SHA256SUMS"
FWVER=$(cat "$FW/VERSION" 2>/dev/null || echo unknown)

# FlashForge's names lie: their .tgz/.tar.xz are often plain tar, and the
# printer's busybox tar cannot decompress at all (verified: "tar -xvf" on a
# real gzip fails with "short read"). Extract by magic bytes; always pack
# plain tar.
extract() { # archive dir
    case "$(head -c 4 "$1" | od -A n -t x1 | tr -d ' ')" in
        fd377a58) xz -dc "$1" | tar -xf - -C "$2" ;;
        1f8b*) gzip -dc "$1" | tar -xf - -C "$2" ;;
        *) tar -xf "$1" -C "$2" ;;
    esac
}

rm -rf "$WORK"
mkdir -p "$WORK/ref" "$DIST"
if [ -d "$REF" ]; then
    cp -a "$REF/." "$WORK/ref/"
else
    [ -f "$REF" ] || die "no such reference: $REF"
    extract "$REF" "$WORK/ref"
fi
# the reference may unpack into a single top folder
[ -f "$WORK/ref/flashforge_init.sh" ] || {
    one=$(ls "$WORK/ref"); [ -f "$WORK/ref/$one/flashforge_init.sh" ] \
        && mv "$WORK/ref/$one/"* "$WORK/ref/" || die "flashforge_init.sh not in the reference"
}
grep -q '^MACHINE=AD5X' "$WORK/ref/flashforge_init.sh" || die "reference is not an AD5X package"
CTRL_TAR=$(ls "$WORK/ref"/control-*.tar.xz 2>/dev/null | head -n 1)
[ -n "$CTRL_TAR" ] || die "no control-*.tar.xz in the reference"
CTRL_VER=$(basename "$CTRL_TAR"); CTRL_VER=${CTRL_VER#control-}; CTRL_VER=${CTRL_VER%.tar.xz}

# Swap the Kalico images in under the vendor's filenames; run.sh and the
# flash tools stay exactly as FlashForge ships them.
mkdir -p "$WORK/control"
extract "$CTRL_TAR" "$WORK/control"
(cd "$WORK/control" && md5sum -c md5sum.list >/dev/null) || die "reference control part fails its own md5sum.list"
cp "$FW/AD5X-mainboard.bin" "$WORK/control/AD5X.bin"
cp "$FW/AD5X-eboard.hex"    "$WORK/control/ADM_App.hex"
cp "$FW/AD5X-ifs.hex"       "$WORK/control/ifs.hex"
rm -f "$WORK/control/ifs.bin"   # stock spare copy; run.sh flashes ifs.hex
touch "$WORK/control/Update" "$WORK/control/UpdateM"   # boot-time flash markers
# stock format: "hash  ./name" (md5sum on Windows marks binary with "*")
(cd "$WORK/control" && md5sum ./* 2>/dev/null | sed 's/ \*\.\//  .\//' \
    | grep -v 'md5sum\.list$' > md5sum.new && mv md5sum.new md5sum.list)

# Kalico-MCU-only package: the control part plus the updater's own pieces
mkdir -p "$WORK/pkg"
cp "$WORK/ref/flashforge_init.sh" "$WORK/pkg/"
for f in start.img end.img play; do
    [ ! -f "$WORK/ref/$f" ] || cp "$WORK/ref/$f" "$WORK/pkg/"
done
(cd "$WORK/control" && tar -cf "$WORK/pkg/control-$CTRL_VER.tar.xz" ./*)

NAME=AD5X-kalico-$FWVER-$(date +%Y%m%d)
tar -cf "$DIST/$NAME.tgz" -C "$WORK/pkg" .
(cd "$DIST" && sha256sum "$NAME.tgz" > "$NAME.tgz.sha256")
{
    echo "{"
    echo "  \"machine\": \"AD5X\","
    echo "  \"kalico_version\": \"$FWVER\","
    echo "  \"control_version\": \"$CTRL_VER\","
    echo "  \"firmware_sha256\": {"
    (cd "$FW" && sha256sum AD5X-mainboard.bin AD5X-eboard.hex AD5X-ifs.hex) |
        awk '{sub(/^\*/, "", $2); printf "    \"%s\": \"%s\",\n", $2, $1}' | sed '$ s/,$//'
    echo "  }"
    echo "}"
} > "$DIST/$NAME.tgz.manifest.json"

# Round trip: unpack what was built and recheck the control md5s
rm -rf "$WORK/verify"; mkdir -p "$WORK/verify/pkg" "$WORK/verify/control"
tar -xf "$DIST/$NAME.tgz" -C "$WORK/verify/pkg"
tar -xf "$WORK/verify/pkg/control-$CTRL_VER.tar.xz" -C "$WORK/verify/control"
(cd "$WORK/verify/control" && md5sum -c md5sum.list >/dev/null) || die "verify failed"
cmp -s "$WORK/verify/control/AD5X.bin" "$FW/AD5X-mainboard.bin" || die "verify failed: AD5X.bin"

echo "built $DIST/$NAME.tgz"
echo "put it in /usr/data on the printer and power-cycle twice:"
echo "  boot 1 installs the control part, boot 2 flashes and reboots"
