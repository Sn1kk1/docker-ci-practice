#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
expected="${1:-$(sed -nE 's/^const Version = "([^"]+)"$/\1/p' main.go)}"
docker run --rm --platform linux/amd64 --network practice5-nexus_default \
  -e "APT_KEY=$(cat nexus/syspulse.asc)" \
  -e "EXPECTED=$expected" ubuntu:22.04 bash -euc '
    printf "%s\n" "$APT_KEY" >/usr/share/keyrings/syspulse.asc
    printf "%s\n" "deb [signed-by=/usr/share/keyrings/syspulse.asc] http://nexus:8081/repository/syspulse/ stable main" >/etc/apt/sources.list
    rm -f /etc/apt/sources.list.d/*
    apt-get update
    apt-get install -y --no-install-recommends "syspulse=$EXPECTED"
    dpkg-query -W -f="\${Package} \${Version} \${Architecture}\n" syspulse
    test "$(syspulse --version)" = "syspulse $EXPECTED"
    syspulse --version
    syspulse
  '
