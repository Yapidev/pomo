#!/usr/bin/env bash
#
# build-deb.sh — build .deb tanpa debhelper (hanya butuh dpkg-deb).
# Alternatif lengkap: dpkg-buildpackage -us -uc (memakai debian/rules).

set -euo pipefail

cd "$(dirname "$0")"

# Ambil versi dari POMO_VERSION di script pomo — satu sumber kebenaran,
# supaya label .deb tidak pernah tertinggal dari versi script.
version=$(sed -n 's/^readonly POMO_VERSION="\([^"]*\)"$/\1/p' pomo | head -n 1)
if [[ -z $version ]]; then
    echo "build-deb.sh: cannot parse POMO_VERSION from ./pomo" >&2
    exit 1
fi
deb_version="${version}-1"

arch="all"

stage="build/pomo"
out="build/pomo_${deb_version}_${arch}.deb"

rm -rf build
mkdir -p "$stage/DEBIAN" "$stage/usr/bin" "$stage/usr/share/doc/pomo"

# 1) Script utama ke /usr/bin/pomo
install -m 755 pomo "$stage/usr/bin/pomo"

# 2) Metadata paket: paragraf binary (Package:) dari debian/control,
#    plus Version: dari POMO_VERSION (paragraf binary di debian/control
#    sumber package memang tanpa Version)
{
    awk 'BEGIN { RS = "" } /^Package:/ { print }' debian/control
    printf 'Version: %s\n' "$deb_version"
} > "$stage/DEBIAN/control"

# 3) Dokumentasi standar
install -m 644 debian/copyright  "$stage/usr/share/doc/pomo/copyright"
install -m 644 debian/changelog  "$stage/usr/share/doc/pomo/changelog.Debian"
gzip -n -9 "$stage/usr/share/doc/pomo/changelog.Debian"
install -m 644 README.md "$stage/usr/share/doc/pomo/README.md"

# 4) Rakit paket
dpkg-deb --root-owner-group --build "$stage" "$out"

echo
echo "Built $out"
