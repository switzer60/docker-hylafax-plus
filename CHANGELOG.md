# Changelog

All notable changes to this repository (not to hylafax+ itself - see
https://hylafax.sourceforge.io/ for that) are documented here.

Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Initial hylafax+ Alpine Docker image: `docker/Dockerfile`,
  `docker/entrypoint.sh`, `docker/healthcheck.sh`.
- `docker-compose.yml` reference deployment, fully environment-variable
  driven (identity/dialing, hfaxd, access control, up to N modems via
  `MODEM_<N>_*`, escape-hatch config overrides).
- `iaxmodem` (software modem over IAX2/VoIP) as the default modem type, with
  serial/USB hardware passthrough supported side-by-side.
- `.github/workflows/build.yml`: build, version-pin verification, smoke
  test, vulnerability scan (Trivy), SBOM generation, push to
  `ghcr.io/switzer60/docker-hylafax-plus` - multi-arch, `linux/amd64` +
  `linux/arm64` (arm64 via QEMU emulation), published as a single manifest
  list.
- Documentation: `docs/ARCHITECTURE.md`, `docs/CONFIGURATION.md`,
  `docs/MODEMS.md`, `docs/BUILD.md`, `NOTICE.md`.
- `tests/smoke-test.sh`, `scripts/check-versions.sh`.
- `docker-compose.yml` defaults to pulling the published image - no local
  build needed; `docker-compose.override.yml` (auto-merged when present)
  adds the local `build:` block back for development.
- First-boot admin password: if `HYLAFAX_ADMIN_PASSWORD` is unset, one is
  generated, printed once to the container logs, and persisted so restarts
  don't rotate or lock you out of it. Covered by a dedicated smoke-test
  scenario (boot, scrape password from logs, restart, confirm it still
  authenticates).
- `MODEM_COUNT` defaults to `0` - `faxq`/`hfaxd` start with no modem
  configured, so a bare `docker compose up -d` with no `.env` works.
- OCI labels record the exact Alpine/hylafaxplus/iaxmodem versions baked
  into a given image, plus a direct link to each package's own APKBUILD,
  so `docker inspect` alone (no repo checkout needed) answers "what's
  actually inside this image" - see docs/BUILD.md.

### Pinned
- Alpine `3.22` (by digest).
- `hylafaxplus` `7.0.10-r0`.
- `iaxmodem` `1.3.4-r0`.
