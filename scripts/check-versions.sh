#!/bin/sh
# Fails if docker-compose.yml / docker/Dockerfile default build args have
# drifted from docker/versions.env, the single source of truth. Run in CI
# (jenkins/Jenkinsfile "Verify" stage) and locally before committing a
# version bump.
set -eu
cd "$(dirname "$0")/.."

. docker/versions.env

status=0
check() {
    file="$1" pattern="$2" expected="$3"
    if ! grep -qF "${pattern}${expected}" "${file}"; then
        echo "MISMATCH: ${file} does not contain '${pattern}${expected}' (docker/versions.env says ${expected})" >&2
        status=1
    fi
}

check docker-compose.yml "ALPINE_VERSION:-" "${ALPINE_VERSION}"
check docker-compose.yml "ALPINE_DIGEST:-" "${ALPINE_DIGEST}"
check docker-compose.yml "HYLAFAX_PKG_VERSION:-" "${HYLAFAX_PKG_VERSION}"
check docker-compose.yml "IAXMODEM_PKG_VERSION:-" "${IAXMODEM_PKG_VERSION}"

check docker/Dockerfile "ARG ALPINE_VERSION=" "${ALPINE_VERSION}"
check docker/Dockerfile "ARG ALPINE_DIGEST=" "${ALPINE_DIGEST}"
check docker/Dockerfile "ARG HYLAFAX_PKG_VERSION=" "${HYLAFAX_PKG_VERSION}"
check docker/Dockerfile "ARG IAXMODEM_PKG_VERSION=" "${IAXMODEM_PKG_VERSION}"

check .env.example "ALPINE_VERSION=" "${ALPINE_VERSION}"
check .env.example "ALPINE_DIGEST=" "${ALPINE_DIGEST}"
check .env.example "HYLAFAX_PKG_VERSION=" "${HYLAFAX_PKG_VERSION}"
check .env.example "IAXMODEM_PKG_VERSION=" "${IAXMODEM_PKG_VERSION}"

if [ "${status}" -eq 0 ]; then
    echo "OK: version pins consistent across docker-compose.yml, docker/Dockerfile, .env.example"
fi
exit "${status}"
