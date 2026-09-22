# hylafax+ on Docker

A minimal (Alpine Linux), fully documented, reproducible container image for
[hylafax+](https://hylafax.sourceforge.io/), configured entirely through
`docker-compose` environment variables - no shell access or manual config
editing required for the common cases, with a documented escape hatch for
everything else.

Pull and go - no build, no login, no required config:

```sh
curl -O https://raw.githubusercontent.com/switzer60/docker-hylafax-plus/main/docker-compose.yml
docker compose up -d
docker compose logs -f
```

That pulls the public image GitHub Actions builds and publishes on every
push (`ghcr.io/switzer60/docker-hylafax-plus`) - see
[.github/workflows/build.yml](.github/workflows/build.yml). Pulling from
somewhere else instead (e.g. an internal registry) is a matter of setting
`REGISTRY`/`IMAGE_NAMESPACE`/`IMAGE_NAME` in `.env` - see `.env.example`.

That gets you `faxq` (scheduler) and `hfaxd` (client-server protocol, port
4559) running with no modem configured yet, and an admin password generated
and printed once to the logs - copy it before you `logs -f` away from it,
or scroll back. `docker compose logs fax | grep -A2 'generated admin'`
finds it again later.

To actually send/receive faxes, add a modem:

```sh
git clone https://github.com/switzer60/docker-hylafax-plus && cd docker-hylafax-plus
cp .env.example .env
$EDITOR .env   # set MODEM_COUNT=1 and either point MODEM_1_IAX_SERVER at
               # your Asterisk box, or switch MODEM_1_TYPE to `serial` and
               # attach real hardware. Set HYLAFAX_ADMIN_PASSWORD here too
               # if you'd rather pick one than use the generated one.
docker compose up -d
```

`faxgetty` (+ either a software `iaxmodem` or a real device) then joins the
other two, all supervised in the same container, all configured from the
environment.

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
- **CI'd, publicly**: [.github/workflows/build.yml](.github/workflows/build.yml)
  builds, smoke-tests (boots the image and exercises the real protocol),
  scans, generates an SBOM, and publishes to `ghcr.io/switzer60/docker-hylafax-plus`
  on every push to `main` - anyone can read the run logs on the Actions tab.
  A separate internal pipeline (`ci/Jenkinsfile`) does the same for a
  private Forgejo mirror; see ["For maintainers"](#for-maintainers-the-ci-pipeline).
  Neither is required reading to build or run the container yourself.

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
| `.github/workflows/build.yml` | Public GitHub Actions pipeline: build → verify → smoke test → scan → SBOM → publish to `ghcr.io`. |
| `ci/` | Jenkinsfile + its setup checklist - the internal counterpart, for whoever maintains that private mirror. See ["For maintainers"](#for-maintainers-the-ci-pipeline) below. |
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
`.github/workflows/build.yml` is the public pipeline - it runs on GitHub's
own infrastructure with no extra setup, and its logs are visible to
anyone on the repo's Actions tab.

`ci/Jenkinsfile` and [ci/JENKINS.md](ci/JENKINS.md) are a separate,
internal pipeline: they document how *this project's own* Jenkins/Forgejo
mirror is wired up (build → verify → smoke test → scan → SBOM → push, same
shape as the public one), for whoever maintains that private pipeline -
not required reading to use the image yourself.

## License

The Dockerfile, entrypoint, compose file, and both CI pipelines in this
repository are MIT-licensed - see [LICENSE](LICENSE). hylafax+ itself, and
the other software this image installs, retain their own licenses - see
[NOTICE.md](NOTICE.md).
