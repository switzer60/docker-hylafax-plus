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

### Pinned
- Alpine `3.22` (by digest).
- `hylafaxplus` `7.0.10-r0`.
- `iaxmodem` `1.3.4-r0`.
