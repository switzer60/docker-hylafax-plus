# hylafax+ on Docker

A minimal (Alpine Linux), fully documented, reproducible container image for
[hylafax+](https://hylafax.sourceforge.io/), configured entirely through
`docker-compose` environment variables - no shell access or manual config
editing required for the common cases, with a documented escape hatch for
everything else.

```sh
git clone <this repo> && cd hylafax-plus-docker
cp .env.example .env
$EDITOR .env   # at minimum: HYLAFAX_ADMIN_PASSWORD, and either point
               # MODEM_1_IAX_SERVER at your Asterisk box, or switch
               # MODEM_1_TYPE to `serial` and attach real hardware
docker compose up -d
docker compose logs -f
```

Within a few seconds you'll have a running fax server: `faxq` (scheduler),
`hfaxd` (client-server protocol on port 4559), and one modem
(`faxgetty` + either a software `iaxmodem` or a real device) - all
supervised in a single container, all configured from the environment.

## Why this exists

- **Minimal**: Alpine base, installed entirely from pinned, checksummed
  `apk` packages - no compiler, no source tarball baked into the image. See
  [docs/BUILD.md](docs/BUILD.md) for why a distro package beats compiling
  hylafax+ from source here.
- **Full flexibility, exposed through compose**: every commonly-needed
  hylafax+ setting (dialing rules, per-modem identity, access control,
  IAX2/serial modem selection, ...) is a documented environment variable -
  see [docs/CONFIGURATION.md](docs/CONFIGURATION.md). Anything not covered
  by an env var is still reachable via a mounted override file - see
  ["Escape hatch"](docs/CONFIGURATION.md#escape-hatch-custom_config_dir).
- **No hardware required**: the default modem type is `iaxmodem`, a software
  modem that registers to an Asterisk/FreePBX server over IAX2/VoIP. Real
  USB/serial modems are also supported, side-by-side. See
  [docs/MODEMS.md](docs/MODEMS.md).
- **Reproducible, transparently**: every version pin, the exact
  `faxsetup(8C)` transcript used at build time, and the honest limits of
  what "reproducible" means here are documented in
  [docs/BUILD.md](docs/BUILD.md) - not just a Dockerfile you have to
  reverse-engineer.
- **CI'd**: a Jenkins pipeline (`ci/Jenkinsfile`) builds, smoke-tests
  (boots the image and exercises the real protocol), scans, generates an
  SBOM, and pushes to a container registry (a Forgejo instance, by
  default) on every push. Lives under `ci/`, separate from everything
  above - see ["For maintainers"](#for-maintainers-the-ci-pipeline) below;
  you don't need it to build or run the container yourself.

## Repository layout

| Path | What |
|---|---|
| `docker/Dockerfile` | The image build. |
| `docker/entrypoint.sh` | Process supervisor: renders config from env vars, starts `iaxmodem`/`faxgetty`/`faxq`/`hfaxd`, handles shutdown. |
| `docker/versions.env` | Single source of truth for all version pins. |
| `docker-compose.yml` | Reference compose file - every env var documented inline. |
| `.env.example` | Copy to `.env` and edit. |
| `config-overrides/` | Drop files here to override any generated config verbatim (see docs/CONFIGURATION.md). |
| `docs/` | Architecture, full config reference, modem setup, build/reproducibility notes - for anyone using the image. |
| `ci/` | Jenkinsfile + its setup checklist - for whoever maintains the build pipeline. See ["For maintainers"](#for-maintainers-the-ci-pipeline) below. |
| `tests/smoke-test.sh` | The real end-to-end test Jenkins (and you, locally) runs against a built image. |
| `scripts/check-versions.sh` | CI guard against version-pin drift. |

## Documentation index

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - process model, spool
  layout, why one container handles all modems.
- [docs/CONFIGURATION.md](docs/CONFIGURATION.md) - every environment
  variable, what it maps to, and the override escape hatch.
- [docs/MODEMS.md](docs/MODEMS.md) - iaxmodem/Asterisk setup, and real
  hardware passthrough.
- [docs/BUILD.md](docs/BUILD.md) - exact build steps, version pins, and
  what reproducibility does/doesn't guarantee here.
- [NOTICE.md](NOTICE.md) - third-party licenses (hylafax+, Alpine,
  iaxmodem).

## For maintainers: the CI pipeline

Everything above is what you need to build or run the container.
`ci/Jenkinsfile` and [ci/JENKINS.md](ci/JENKINS.md) are separate: they
document how *this repo's own* Jenkins/Forgejo pipeline is wired up (build
→ verify → smoke test → scan → SBOM → push), for whoever maintains that
pipeline - not required reading to use the image yourself.

## License

The Dockerfile, entrypoint, compose file, and Jenkins pipeline in this
repository are MIT-licensed - see [LICENSE](LICENSE). hylafax+ itself, and
the other software this image installs, retain their own licenses - see
[NOTICE.md](NOTICE.md).
