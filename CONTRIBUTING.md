# Contributing

## Local dev loop

```sh
docker build -f docker/Dockerfile -t hylafax-plus:local .
IMAGE=hylafax-plus:local ./tests/smoke-test.sh
```

The smoke test is the bar: it boots the image, waits for the real Docker
`HEALTHCHECK` to pass, and exercises the actual hfaxd protocol. If you
change `entrypoint.sh` or the Dockerfile, this must still pass.

## Changing a version pin

See [docs/BUILD.md#updating-the-pins](docs/BUILD.md#updating-the-pins) -
`docker/versions.env` is the single source of truth;
`scripts/check-versions.sh` enforces that `docker-compose.yml`,
`docker/Dockerfile`, and `.env.example` haven't drifted from it.

## Adding a new environment variable

1. Add the read/default in `docker/entrypoint.sh`.
2. Add the matching line (with the same default) in `docker-compose.yml`'s
   `environment:` block, and in `.env.example` if it's something most users
   will want to set.
3. Document it in the matching table in `docs/CONFIGURATION.md`.
4. If it's modem-related, also check whether `docs/MODEMS.md` needs an
   example update.

Env vars are the "convenient, common-case" layer over the full
`hylafax-config(5F)` surface - not every one of hylafax+'s ~150 config
parameters needs (or should get) its own variable. If what you need is
already reachable via `CUSTOM_CONFIG_DIR` (see docs/CONFIGURATION.md), that
may be enough on its own.

## Pull requests

GitHub Actions runs `scripts/check-versions.sh` and `tests/smoke-test.sh`
against every PR build (see `.github/workflows/build.yml`) - both must
pass before merge. There's no other formal process; open a PR against
`main`.
