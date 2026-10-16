#!/usr/bin/env bash
#
# build-deb.sh — build .deb tanpa debhelper (hanya butuh dpkg-deb).
# Alternatif lengkap: dpkg-buildpackage -us -uc (memakai debian/rules).

set -euo pipefail

cd "$(dirname "$0")"

# Ambil versi dari baris pertama debian/changelog
version=$(sed -n 's/^pomo (\([^)]*\)).*/\1/p' debian/changelog | head -n 1)
if [[ -z $version ]]; then
    echo "build-deb.sh: cannot parse version from debian/changelog" >&2
    exit 1
fi

arch="all"

stage="build/pomo"
out="build/pomo_${version}_${arch}.deb"

rm -rf build
mkdir -p "$stage/DEBIAN" "$stage/usr/bin" "$stage/usr/share/doc/pomo"

# 1) Script utama ke /usr/bin/pomo
install -m 755 pomo "$stage/usr/bin/pomo"

# 2) Metadata paket: ambil paragraf binary (Package:) dari debian/control
awk 'BEGIN { RS = "" } /^Package:/ { print }' debian/control > "$stage/DEBIAN/control"

# 3) Dokumentasi standar
install -m 644 debian/copyright  "$stage/usr/share/doc/pomo/copyright"
install -m 644 debian/changelog  "$stage/usr/share/doc/pomo/changelog.Debian"
gzip -n -9 "$stage/usr/share/doc/pomo/changelog.Debian"
install -m 644 README.md "$stage/usr/share/doc/pomo/README.md"

# 4) Rakit paket
dpkg-deb --root-owner-group --build "$stage" "$out"

echo
echo "Built $out"
