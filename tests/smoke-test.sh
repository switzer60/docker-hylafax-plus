#!/bin/bash
# End-to-end smoke test for a built hylafax-plus image: boots the container
# with a fake IAX2 server (no real Asterisk needed - iaxmodem's AT-command
# interface comes up regardless of whether registration succeeds), waits for
# Docker's own HEALTHCHECK to go healthy, then exercises the hfaxd protocol
# and faxstat. Exits non-zero on any failure. Used by ci/Jenkinsfile
# and safe to run locally: `IMAGE=hylafax-plus:local tests/smoke-test.sh`.
set -Eeuo pipefail

IMAGE="${IMAGE:-hylafax-plus:local}"
NAME="hf-smoke-$$"
PORT="${SMOKE_PORT:-14559}"

cleanup() {
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "== smoke test: booting ${IMAGE} =="
docker run -d --name "${NAME}" \
    -p "${PORT}:4559" \
    -e MODEM_COUNT=1 \
    -e MODEM_1_TYPE=iaxmodem \
    -e MODEM_1_DEVICE=ttyIAX0 \
    -e MODEM_1_IAX_SERVER=10.0.0.1 \
    -e MODEM_1_IAX_PEER_NAME=fax1 \
    -e MODEM_1_IAX_PEER_SECRET=smoketest \
    -e MODEM_1_FAX_NUMBER=+15555550100 \
    -e HYLAFAX_ADMIN_USER=admin \
    -e HYLAFAX_ADMIN_PASSWORD=smoke-test-password \
    "${IMAGE}" >/dev/null

echo "== waiting for Docker healthcheck =="
ok=0
for _ in $(seq 1 30); do
    status="$(docker inspect "${NAME}" --format '{{.State.Health.Status}}' 2>/dev/null || echo unknown)"
    if [[ "${status}" == "healthy" ]]; then
        ok=1
        break
    fi
    if [[ "${status}" == "unhealthy" ]]; then
        echo "FAIL: container became unhealthy" >&2
        docker logs "${NAME}" >&2
        exit 1
    fi
    sleep 1
done
[[ "${ok}" -eq 1 ]] || { echo "FAIL: never became healthy within 30s" >&2; docker logs "${NAME}" >&2; exit 1; }
echo "OK: healthy"

echo "== faxstat: modem must be idle =="
docker exec "${NAME}" faxstat -s | tee /dev/stderr | grep -q "Running and idle" \
    || { echo "FAIL: modem not idle per faxstat" >&2; exit 1; }
echo "OK: faxstat reports modem idle"

echo "== hfaxd protocol: anonymous login =="
resp="$(printf 'USER anonymous\r\nQUIT\r\n' | docker exec -i "${NAME}" nc -w 2 127.0.0.1 4559)"
echo "${resp}"
grep -q '220 .*ready' <<< "${resp}" || { echo "FAIL: no 220 greeting" >&2; exit 1; }
grep -q '230 User anonymous logged in' <<< "${resp}" || { echo "FAIL: anonymous login rejected" >&2; exit 1; }
echo "OK: hfaxd protocol responds"

echo "== hfaxd protocol: admin auth =="
resp="$(printf 'USER admin\r\nPASS smoke-test-password\r\nQUIT\r\n' | docker exec -i "${NAME}" nc -w 2 127.0.0.1 4559)"
echo "${resp}"
grep -q '230 User admin logged in' <<< "${resp}" || { echo "FAIL: admin auth rejected" >&2; exit 1; }
echo "OK: admin auth accepted"

echo "== graceful shutdown =="
start="$(date +%s)"
docker stop -t 10 "${NAME}" >/dev/null
elapsed=$(( $(date +%s) - start ))
[[ "${elapsed}" -lt 10 ]] || { echo "FAIL: shutdown took ${elapsed}s, expected a clean exit well under the 10s grace period" >&2; exit 1; }
echo "OK: shut down cleanly in ${elapsed}s"

echo "== all smoke tests passed =="
