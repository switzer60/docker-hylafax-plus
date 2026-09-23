# Build: exact steps and reproducibility

This document is the complete, honest account of how the image is built and
what "reproducible" does and doesn't mean here. If you rebuild this image
from scratch in five years, this is what should let you get (functionally)
the same thing back.

## Why a distro package instead of compiling from source

hylafax+ is not in Alpine's default (`main`) repo, but it **is** in
`community` as of Alpine 3.21 (`hylafaxplus-7.0.9-r2`), 3.22
(`hylafaxplus-7.0.10-r0`), and 3.24 (`hylafaxplus-7.0.11-r0`, what this
image pins), maintained upstream by the Alpine packagers, built against
musl, with security updates tracked through Alpine's normal advisory
process.

We use that package instead of compiling hylafax+ from its SourceForge
tarball for three reasons:

1. **Correctness.** hylafax+'s `configure`/build system is a hand-rolled,
   pre-autoconf shell script from the mid-1990s. The Alpine packagers have
   already solved the musl-specific rough edges (see the exact recipe below).
   Re-solving those ourselves would be strictly worse engineering for no
   benefit.
2. **Patch/CVE tracking.** An `apk` package gets picked up by every standard
   Alpine vulnerability scanner (Trivy, Grype, `apk audit`) by name and
   version. A locally-compiled binary is invisible to all of them.
3. **Auditability.** `apk info -L hylafaxplus` and the aports `APKBUILD` are
   a complete, public record of exactly what's in the package and how it was
   built. Nothing is hidden in a multi-hundred-line Dockerfile `RUN` block.

The tradeoff: we're always however many releases behind whatever Alpine's
packagers have gotten to - currently none; 7.0.11-r0 (the Alpine 3.24
package) matches hylafax+'s own latest release as of this writing. That
won't always be true, and we accept it explicitly rather than silently
when it isn't.

## The upstream packaging recipe

We don't compile hylafax+ ourselves - Alpine's own packager already did,
and solved the musl-specific rough edges in the process. Rather than
duplicating that work here (a copy that would just go stale), the recipe
itself is the reference:

https://gitlab.alpinelinux.org/alpine/aports/-/blob/v3.24.2/community/hylafaxplus/APKBUILD

Pinned to the `v3.24.2` tag, not `master`, so it always matches what
`alpine:3.24.2` actually installs. Maintained by Francesco Colista
(`fcolista@alpinelinux.org`) - our thanks to him and Alpine's packaging
community for doing and maintaining this work; this image is considerably
simpler and more trustworthy for it existing.

The one thing worth calling out explicitly, because it explains a design
choice in our own code rather than theirs: that recipe's
`config-files-default-extension.patch` installs `hosts.hfaxd` as
`hosts.hfaxd.default`, not as a live file - which is why
`docker/entrypoint.sh` has to generate `etc/hosts.hfaxd` itself from
`HYLAFAX_*` env vars on every boot, rather than expecting the package to
have shipped a usable one.

## What's pinned, and where

Single source of truth: [`docker/versions.env`](../docker/versions.env).
`docker-compose.yml`, `docker/Dockerfile`, and `.env.example` each carry the
same values as their own defaults (so `docker build` with no other files,
or `docker compose up` with no `.env`, still produce a pinned build).
[`scripts/check-versions.sh`](../scripts/check-versions.sh) fails CI if
these drift apart - see the "Verify version pins are consistent" step in
[`.github/workflows/build.yml`](../.github/workflows/build.yml).

| Pin | Value | What it guarantees |
|---|---|---|
| `ALPINE_VERSION` + `ALPINE_DIGEST` | `3.24.2` / `sha256:294b683c...` | The base image is referenced **by digest**, not just tag. `alpine:3.24.2` can be repointed by Docker Hub; the digest cannot. |
| `HYLAFAX_PKG_VERSION` | `7.0.11-r0` | `apk add hylafaxplus=7.0.11-r0` - fails loudly (not silently upgrades) if that exact build is unavailable. |
| `IAXMODEM_PKG_VERSION` | `1.3.4-r1` | Same guarantee for the iaxmodem package. |

Every one of these pins is also baked into the image itself as an OCI
label - you don't need this repo checked out to find out what's inside a
given image, only the image:

```sh
docker inspect ghcr.io/switzer60/docker-hylafax-plus:latest \
    --format '{{json .Config.Labels}}' | python3 -m json.tool
```

`org.opencontainers.image.version` matches the composite tag this same
build is published under (see "Tagging" below) - the label and the
pullable tag always agree. `org.opencontainers.image.base.name`/`.base.digest`
are the Alpine base pin, standard OCI keys. The
`io.github.switzer60.docker-hylafax-plus.*` labels are this project's own
(no standard OCI key covers "which of two packages installed alongside
each other" - iaxmodem isn't "the" packaged software, hylafax+ is) and
include a direct link to each package's own APKBUILD, pinned to the
matching Alpine version tag, for `hylafaxplus` and `iaxmodem`
respectively - the same provenance links documented in prose above.

### The honest limit of this reproducibility

Alpine does not keep an indefinite, queryable archive of every historical
package build the way Debian's snapshot.debian.org does. `v3.24/community`
keeps receiving updates until that branch's EOL; an exact `apk` version
string can in principle be garbage-collected from the mirrors after enough
time passes, at which point `apk add hylafaxplus=7.0.11-r0` fails outright
(loud failure, not silent drift - see the guarantee above) rather than
rebuilding.

The practical answer to "what's the reproducible artifact" is therefore:
**the image published to `ghcr.io/switzer60/docker-hylafax-plus`,
referenced by its digest, is the actual durable, reproducible artifact.**
The Dockerfile lets you rebuild an equivalent image today or reason
precisely about what changed if a rebuild ever produces something
different; it is not a promise that the exact bytes are re-derivable
forever. If you need that stronger guarantee, mirror the `.apk` files
themselves - not currently done here, to keep the build simple; flag it
if you want it added.

## Tagging

Three tags get published, each answering a different question:

| Tag | Example | Answers |
|---|---|---|
| `latest` | `latest` | "give me whatever's current on `main`" - floating, moves on every push. |
| `sha-<short-sha>` | `sha-c9339754c201` | "give me exactly this commit" - immutable, the real reproducibility pin (see above). |
| `alpine-<ver>_hylafaxplus-<ver>_iaxmodem-<ver>` | `alpine-3.24.2_hylafaxplus-7.0.11-r0_iaxmodem-1.3.4-r1` | "what's actually inside, at a glance" - built directly from the three `docker/versions.env` pins, no separate release process to remember. |

The composite tag updates whenever any of the three `docker/versions.env`
pins change, and otherwise stays put. It's a label, not a strict content
pin - use `sha-<short-sha>` for an exact, immutable reference to a
specific build.

## Architectures

The public image (`ghcr.io/switzer60/docker-hylafax-plus`, published by
`.github/workflows/build.yml`) is multi-arch: `linux/amd64` and
`linux/arm64`, published as a single manifest list - `docker pull`/
`docker compose up` picks the right one automatically. This works because
nothing in the build compiles anything: `hylafaxplus` and `iaxmodem` are
both published by Alpine for `x86_64`, `aarch64`, `armv7`, and `armhf`
(checked directly against `v3.24/main` and `v3.24/community`'s
`APKINDEX`), and the pinned `ALPINE_DIGEST` above
is itself a multi-platform OCI image index, not a single-arch manifest -
`docker manifest inspect` on it shows `amd64`, `arm/v6`, and `arm64`
children. `docker/Dockerfile` needed zero changes for multi-arch; only the
CI pipeline did.

The GitHub Actions pipeline builds and smoke-tests each architecture
separately (`arm64` via QEMU emulation on the `amd64` runner -
`docker/setup-qemu-action`, since this image is apk-install-only with
nothing to compile, so emulation overhead is minor), pushes each as its
own `:sha-<sha>-<arch>` tag, then a final job merges them into the real
published tags with `docker buildx imagetools create` - a manifest-list
merge of already-pushed, already-tested images, not a rebuild.

A plain `docker build` locally remains single-arch, building for whatever
the Docker daemon's host platform is - that's expected; use
`docker-compose.override.yml` / `docker build` as usual for local
development, and let CI produce the multi-arch published image.

## The one-time `faxsetup` step, in full

`faxsetup(8C)` is an interactive script. Rather than reimplementing its
internal logic (which changes across hylafax+ versions and would silently
drift), the Dockerfile runs the **real, unmodified** `faxsetup` binary from
the package, feeding it a fixed, literal transcript of answers:
[`docker/faxsetup-answers.txt`](../docker/faxsetup-answers.txt).

Every answer in that file is either blank (accept the bracketed default) or
an explicit `no`, at exactly two points:

1. *"Should I restart the HylaFAX server processes?"* → **no**. The
   entrypoint starts `faxq`/`hfaxd` itself, supervised, at container start -
   not at build time.
2. *"Do you want to run faxaddmodem to configure a modem?"* → **no**. Modems
   are configured per-container-boot by `docker/entrypoint.sh`, from
   `MODEM_*` environment variables, not baked into the image. (`faxaddmodem`
   also identifies real hardware by sending it AT commands - meaningless at
   build time, when no modem exists yet.)

This step produces exactly three things that get baked into the image:
`/var/spool/hylafaxplus/etc/config` (with build-time-only defaults, fully
overwritten by the entrypoint from `FAX_*` env vars on every boot),
`/usr/lib/hylafaxplus/setup.cache` (paths/tool locations resolved once, at
build time, from the package layout - `faxq` and `hfaxd` refuse to start
without this file existing), and a self-signed `etc/ssl.pem` (SSL Fax;
replace it by mounting your own at the same path if you use that feature).

### How the answers file was derived (and how to re-derive it)

This is not guesswork - it was captured by actually running `faxsetup`
against the installed package and recording every prompt in order. To
verify against a new `HYLAFAX_PKG_VERSION`, or re-derive the answers file if
a new version changes the prompt sequence:

```sh
docker run --rm -it alpine:3.24.2 sh -c '
  apk add --no-cache hylafaxplus=<new-version> bash openssl
  faxsetup
'
```

Answer every prompt exactly as if accepting the default (press Enter),
**except** answer `no` at the two "restart"/"faxaddmodem" prompts described
above. Transcribe your answers, in order, one per line, into
`docker/faxsetup-answers.txt`. Then rebuild and run
[`tests/smoke-test.sh`](../tests/smoke-test.sh) - a mismatched answers file
either makes `faxsetup` hang (a prompt got an unexpected answer and is
re-asking) or fails obviously downstream (missing `etc/config`,
`faxq`/`hfaxd` refusing to start), never silently.

## Updating the pins

1. Edit `docker/versions.env`.
2. Copy the same values into `docker-compose.yml` (`build.args` defaults),
   `docker/Dockerfile` (`ARG ... =` defaults), and `.env.example`.
3. Run `./scripts/check-versions.sh` - it must print `OK`.
4. If `HYLAFAX_PKG_VERSION` changed: re-derive `docker/faxsetup-answers.txt`
   per the steps above.
5. `docker build -f docker/Dockerfile -t hylafax-plus:local .` then
   `IMAGE=hylafax-plus:local ./tests/smoke-test.sh`.
6. Open a PR. CI runs the same two commands (see
   `.github/workflows/build.yml`) before anything is published.

## Building locally without CI

`docker-compose.override.yml` is what makes this a local build instead of a
registry pull - `docker compose` merges it in automatically whenever it's
present next to `docker-compose.yml`, no flag needed:

```sh
git clone https://github.com/switzer60/docker-hylafax-plus && cd docker-hylafax-plus
cp .env.example .env        # optional - see .env.example; nothing here is required
docker compose build
docker compose up -d
docker compose logs -f
```
