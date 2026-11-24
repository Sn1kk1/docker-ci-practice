#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(sed -nE 's/^const Version = "([0-9]+\.[0-9]+\.[0-9]+)"$/\1/p' main.go)"
: "${version:?Version missing from main.go}"
package="syspulse_${version}_amd64.deb"
tar -cf - debian/control.in dist/syspulse |
  docker run --rm -i -e "VERSION=$version" -e "PACKAGE=$package" golang:1.24-bookworm bash -euc '
    cd "$(mktemp -d)"
    tar -xf -
    install -d -m 755 stage/DEBIAN
    sed "s/@VERSION@/$VERSION/" debian/control.in >stage/DEBIAN/control
    install -D -m 755 dist/syspulse stage/usr/bin/syspulse
    dpkg-deb --build --root-owner-group stage "$PACKAGE" >&2
    dpkg-deb -I "$PACKAGE" >&2
    dpkg-deb -c "$PACKAGE" >&2
    cat "$PACKAGE"
  ' >"dist/$package"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'version=%s\npath=%s\n' "$version" "syspulse/dist/$package" >>"$GITHUB_OUTPUT"
fi
