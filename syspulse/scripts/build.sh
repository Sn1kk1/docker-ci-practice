#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
tar -cf - main.go go.mod | docker run --rm -i golang:1.24-bookworm bash -euc '
  cd "$(mktemp -d)"
  tar -xf -
  GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -buildvcs=false -o syspulse .
  cat syspulse
' >dist/syspulse
chmod 755 dist/syspulse
file dist/syspulse
