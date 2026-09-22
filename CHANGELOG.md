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
- `ci/Jenkinsfile`: build, version-pin verification, smoke test, vulnerability
  scan (Trivy), SBOM generation (Syft), push to a Forgejo container
  registry.
- Documentation: `docs/ARCHITECTURE.md`, `docs/CONFIGURATION.md`,
  `docs/MODEMS.md`, `docs/BUILD.md`, `ci/JENKINS.md`, `NOTICE.md`.
- `tests/smoke-test.sh`, `scripts/check-versions.sh`.
- `docker-compose.yml` now defaults to pulling the image from the Forgejo
  registry rather than building locally; `docker-compose.override.yml`
  (auto-merged when present) adds the local `build:` block back for
  development.
- First-boot admin password: if `HYLAFAX_ADMIN_PASSWORD` is unset, one is
  generated, printed once to the container logs, and persisted so restarts
  don't rotate or lock you out of it. Covered by a dedicated smoke-test
  scenario (boot, scrape password from logs, restart, confirm it still
  authenticates).
- `MODEM_COUNT` now defaults to `0` - `faxq`/`hfaxd` start with no modem
  configured, so a bare `docker compose up -d` with no `.env` works.
- Public mirror at github.com/switzer60/docker-hylafax-plus, with its own
  `.github/workflows/build.yml` (build → verify → smoke test → scan →
  SBOM → push) publishing to `ghcr.io/switzer60/docker-hylafax-plus` on
  every push - the internal Jenkins/Forgejo pipeline is unchanged and now
  documented as the private counterpart. `docker-compose.yml`'s default
  registry flipped accordingly: GHCR (public) by default, Forgejo
  (internal) via `.env` override.
- Multi-arch publishing: `.github/workflows/build.yml` now builds, smoke
  tests, and pushes `linux/amd64` and `linux/arm64` separately (arm64
  under QEMU emulation), then merges them into proper multi-arch manifest
  lists with `docker buildx imagetools create` - no Dockerfile changes
  needed, since `hylafaxplus`/`iaxmodem` are published by Alpine for both
  architectures and the pinned base image digest was already multi-arch.
- OCI labels now record the exact Alpine/hylafaxplus/iaxmodem versions
  baked into a given image, plus a direct link to each package's own
  APKBUILD, so `docker inspect` alone (no repo checkout needed) answers
  "what's actually inside this image" - see docs/BUILD.md. Also fixed:
  `org.opencontainers.image.source` was still the placeholder
  `github.com/OWNER/hylafax-plus-docker`; now the real repo URL.

### Pinned
- Alpine `3.22` (by digest).
- `hylafaxplus` `7.0.10-r0`.
- `iaxmodem` `1.3.4-r0`.
