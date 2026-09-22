# Build: exact steps and reproducibility

This document is the complete, honest account of how the image is built and
what "reproducible" does and doesn't mean here. If you rebuild this image
from scratch in five years, this is what should let you get (functionally)
the same thing back.

## Why a distro package instead of compiling from source

hylafax+ is not in Alpine's default (`main`) repo, but it **is** in
`community` as of Alpine 3.21 (`hylafaxplus-7.0.9-r2`) and 3.22
(`hylafaxplus-7.0.10-r0`), maintained upstream by the Alpine packagers, built
against musl, with security updates tracked through Alpine's normal
advisory process.

We use that package instead of compiling hylafax+ from its SourceForge
tarball for three reasons:

1. **Correctness.** hylafax+'s `configure`/build system is a hand-rolled,
   pre-autoconf shell script from the mid-1990s. The Alpine packagers have
   already solved the musl-specific rough edges (see
   [`APKBUILD` upstream](https://gitlab.alpinelinux.org/alpine/aports/-/tree/master/community/hylafaxplus)
   if you want the diff). Re-solving those ourselves would be strictly worse
   engineering for no benefit.
2. **Patch/CVE tracking.** An `apk` package gets picked up by every standard
   Alpine vulnerability scanner (Trivy, Grype, `apk audit`) by name and
   version. A locally-compiled binary is invisible to all of them.
3. **Auditability.** `apk info -L hylafaxplus` and the aports `APKBUILD` are
   a complete, public record of exactly what's in the package and how it was
   built. Nothing is hidden in a multi-hundred-line Dockerfile `RUN` block.

The tradeoff: we're one version behind whatever hylafax+'s own release page
shows (7.0.10 via the Alpine 3.22 package vs. 7.0.11 upstream as of this
writing). We accept that explicitly rather than silently.

## What's pinned, and where

Single source of truth: [`docker/versions.env`](../docker/versions.env).
`docker-compose.yml`, `docker/Dockerfile`, and `.env.example` each carry the
same values as their own defaults (so `docker build` with no other files,
or `docker compose up` with no `.env`, still produce a pinned build).
[`scripts/check-versions.sh`](../scripts/check-versions.sh) fails CI if
these drift apart - see the "Verify" stage in `Jenkinsfile`.

| Pin | Value | What it guarantees |
|---|---|---|
| `ALPINE_VERSION` + `ALPINE_DIGEST` | `3.22` / `sha256:5291449c...` | The base image is referenced **by digest**, not just tag. `alpine:3.22` can be repointed by Docker Hub; the digest cannot. |
| `HYLAFAX_PKG_VERSION` | `7.0.10-r0` | `apk add hylafaxplus=7.0.10-r0` - fails loudly (not silently upgrades) if that exact build is unavailable. |
| `IAXMODEM_PKG_VERSION` | `1.3.4-r0` | Same guarantee for the iaxmodem package. |

### The honest limit of this reproducibility

Alpine does not keep an indefinite, queryable archive of every historical
package build the way Debian's snapshot.debian.org does. `v3.22/community`
keeps receiving updates until that branch's EOL; an exact `apk` version
string can in principle be garbage-collected from the mirrors after enough
time passes, at which point `apk add hylafaxplus=7.0.10-r0` fails outright
(loud failure, not silent drift - see the guarantee above) rather than
rebuilding.

The practical answer to "what's the reproducible artifact" is therefore:
**the image Jenkins pushes to the Forgejo registry, referenced by its
digest, is the actual durable, reproducible artifact.** The Dockerfile lets
you rebuild an equivalent image today or reason precisely about what
changed if a rebuild ever produces something different; it is not a promise
that the exact bytes are re-derivable forever. If you need that stronger
guarantee, mirror the `.apk` files themselves (e.g. into a Forgejo generic
package registry) - not currently done here, to keep the build simple; flag
it if you want it added.

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
docker run --rm -it alpine:3.22 sh -c '
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
6. Open a PR. Jenkins runs the same two commands (see `Jenkinsfile`) before
   anything is pushed.

## Building locally without Jenkins

```sh
git clone <this repo> && cd hylafax-plus-docker
cp .env.example .env        # edit HYLAFAX_ADMIN_PASSWORD at minimum
docker compose build
docker compose up -d
docker compose logs -f
```
