#!/usr/bin/env bash
set -euo pipefail
: "${NEXUS_HOST:?Set NEXUS_HOST to the base URL}"
: "${NEXUS_USER:?Set NEXUS_USER}"
: "${NEXUS_PASSWORD:?Set NEXUS_PASSWORD}"
package="${1:?Pass the path to the Debian package}"
status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  --max-time 60 --user "$NEXUS_USER:$NEXUS_PASSWORD" \
  --form "apt.asset=@$package" "${NEXUS_HOST%/}/service/rest/v1/components?repository=syspulse")"
case "$status" in
  200|201|204) printf 'Nexus accepted %s (HTTP %s)\n' "${package##*/}" "$status" ;;
  *) printf 'Nexus upload failed (HTTP %s)\n' "$status" >&2; exit 1 ;;
esac
curl -fsS --retry 8 --retry-all-errors --retry-delay 2 --max-time 15 \
  "${NEXUS_HOST%/}/repository/syspulse/dists/stable/InRelease" -o /dev/null
