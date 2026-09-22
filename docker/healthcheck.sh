#!/bin/bash
# Docker HEALTHCHECK: faxq must be running, and hfaxd (if enabled) must
# accept a protocol connection. Modem-level health (iaxmodem/faxgetty) is
# checked per configured slot but does not fail the container on its own,
# since a modem flapping (e.g. IAX2 server briefly unreachable) shouldn't
# cause Docker to kill the whole stack - `faxstat` surfaces that instead.
set -u

fail() { echo "unhealthy: $*" >&2; exit 1; }

pgrep -f '/usr/sbin/faxq' > /dev/null || fail "faxq is not running"

if [[ "${HFAXD_ENABLE:-yes}" == "yes" ]]; then
    pgrep -f '/usr/sbin/hfaxd' > /dev/null || fail "hfaxd is not running"
    printf 'QUIT\r\n' | nc -w 2 127.0.0.1 "${HFAXD_PORT:-4559}" > /dev/null \
        || fail "hfaxd is not accepting connections on port ${HFAXD_PORT:-4559}"
fi

count="${MODEM_COUNT:-1}"
for n in $(seq 1 "${count}"); do
    devvar="MODEM_${n}_DEVICE"
    devid="${!devvar:-}"
    [[ -n "${devid}" ]] || continue
    pgrep -f "faxgetty.*${devid}" > /dev/null \
        || echo "warning: faxgetty for modem ${n} (${devid}) is not running" >&2
done

echo "ok"
exit 0
