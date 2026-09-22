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
   already solved the musl-specific rough edges (see the exact recipe below).
   Re-solving those ourselves would be strictly worse engineering for no
   benefit.
2. **Patch/CVE tracking.** An `apk` package gets picked up by every standard
   Alpine vulnerability scanner (Trivy, Grype, `apk audit`) by name and
   version. A locally-compiled binary is invisible to all of them.
3. **Auditability.** `apk info -L hylafaxplus` and the aports `APKBUILD` are
   a complete, public record of exactly what's in the package and how it was
   built. Nothing is hidden in a multi-hundred-line Dockerfile `RUN` block.

The tradeoff: we're one version behind whatever hylafax+'s own release page
shows (7.0.10 via the Alpine 3.22 package vs. 7.0.11 upstream as of this
writing). We accept that explicitly rather than silently.

## The upstream packaging recipe (APKBUILD), in full

This is the actual, complete build recipe Alpine's packager uses to produce
`hylafaxplus-7.0.10-r0.apk` - fetched from Alpine's `aports` source repo,
pinned to the `v3.22.0` tag (not `master`, which can show a newer recipe
than what `alpine:3.22` actually serves):

https://gitlab.alpinelinux.org/alpine/aports/-/blob/v3.22.0/community/hylafaxplus/APKBUILD

What it establishes:

- **Maintainer**: Francesco Colista (`fcolista@alpinelinux.org`), a named
  Alpine package maintainer - not an anonymous or third-party build.
- **Source**: `https://downloads.sourceforge.net/hylafax/hylafax-7.0.10.tar.gz`
  - the same official upstream tarball a from-source build would use -
  pinned by the `sha512sums` block below; `abuild` refuses to build if the
  downloaded tarball doesn't match.
- **5 patches** on top of stock upstream (each independently checksummed,
  diffs readable at the same gitlab path). Read in full, not just by name -
  what each one actually does:

  | Patch | What it does | Relevant to this image? |
  |---|---|---|
  | `common-functions-busybox-awk.patch` | In `util/common-functions.sh.in` (used by `bin/notify`/`bin/faxrcvd`, run on every completed job): replaces an `awk 'length>L{...}' \| sed` string-length pipeline with plain `${#VAR}`; and fixes a real bug where `p("files_"++nfiles, $4)` pre-increments `nfiles` *inside* a string-concatenation expression - evaluation order POSIX awk doesn't guarantee, and BusyBox awk (Alpine's default, not gawk) could misnumber multi-part received documents as a result. Fixed by splitting into `++nfiles; p("files_"nfiles, $4)`. | **Yes** - a correctness fix that runs on every job in this container. |
  | `no-locale.patch` | Drops a `CHARSET="$(locale -- charmap)"` fallback in `util/dictionary.sh.in` - Alpine/musl doesn't have working glibc-style locale introspection. | Makes charset handling deterministic (from the dictionary files, never from container locale env vars). |
  | `utf8-dictionary.patch` | Recodes the built-in notification-email dictionaries (`dict-de`, `dict-es`, `dict-it`, `dict-pl`, `dict-pt`, `dict-pt_BR`, ...) from legacy ISO-8859-1/2 to UTF-8. | Only if you use non-English fax notification emails. |
  | `dont-ship-xferfaxlog-file.patch` | Stops the package pre-seeding an empty `etc/xferfaxlog` at install time. | No - `xferfaxlog` is server-generated state; `faxq` creates it itself regardless. |
  | `config-files-default-extension.patch` | Installs `hosts.hfaxd`/`hfaxd.conf` as `hosts.hfaxd.default`/`hfaxd.conf.default`, not as live filenames, so a package upgrade never silently overwrites an admin's access-control file. | **Yes - this is why `entrypoint.sh` generates `etc/hosts.hfaxd` itself.** The package deliberately ships no live one; `apk info -L hylafaxplus` shows `usr/lib/hylafaxplus/hfaxd.conf.default`, never a live `hfaxd.conf`. |

  One more cross-check worth recording: the `-openrc` subpackage (not
  installed in this image - we supervise `faxq`/`hfaxd` directly in
  `entrypoint.sh` instead, see docs/ARCHITECTURE.md) invokes
  `hfaxd ... -d` and `faxq ... -D` in its `hylafaxplus.initd`/`.confd` -
  the exact same "don't detach" flags `entrypoint.sh` uses. Independent
  confirmation those are the package's own intended foreground flags, not
  a guess made for this image.
- **The `configure` flags** (`build()`, below) are where `DIR_SPOOL=/var/spool/hylafaxplus`,
  `DIR_SBIN=/usr/sbin`, etc. actually get set - this is the authoritative
  source for the paths `docker/entrypoint.sh` and `docs/ARCHITECTURE.md`
  assume.
- **`# secfixes:`** records CVE-2020-15396/CVE-2020-15397 as already fixed
  in this lineage - the CVE-tracking benefit from point 2 above, in
  practice.

```sh
# Contributor: Francesco Colista <fcolista@alpinelinux.org>
# Maintainer: Francesco Colista <fcolista@alpinelinux.org>
pkgname=hylafaxplus
pkgver=7.0.10
pkgrel=0
pkgdesc="Making the Premier Open-Source Fax Management System Even Better"
url="https://hylafax.sourceforge.net/"
arch="all"
license="MIT"
# check/test not supported from upstream
options="!check"
depends="ghostscript bash tiff-tools findutils"
makedepends="zlib-dev tiff-dev gettext-dev openldap-dev lcms2-dev
	libffi-dev jbig2dec-dev sed readline-dev openssl-dev"
subpackages="$pkgname-dbg $pkgname-doc $pkgname-lang $pkgname-openrc"
source="https://downloads.sourceforge.net/hylafax/hylafax-$pkgver.tar.gz
	$pkgname.initd
	$pkgname.confd
	common-functions-busybox-awk.patch
	no-locale.patch
	utf8-dictionary.patch
	dont-ship-xferfaxlog-file.patch
	config-files-default-extension.patch
	"
builddir="$srcdir"/hylafax-$pkgver

# secfixes:
#   7.0.2-r2:
#     - CVE-2020-15396
#     - CVE-2020-15397

prepare() {
	default_prepare
	update_config_guess
}

build() {
	# the configure script does not handle ccache or distcc
	export CC=gcc
	export CXX=g++
	./configure \
		--nointeractive \
		--disable-pam \
		--with-DIR_BIN=/usr/bin \
		--with-DIR_SBIN=/usr/sbin \
		--with-DIR_LIB=/usr/lib \
		--with-DIR_LIBEXEC=/usr/sbin \
		--with-DIR_LIBDATA=/usr/lib/$pkgname \
		--with-DIR_LOCALE=/usr/share/locale/"$pkgname" \
		--with-DIR_LOCKS=/var/lock \
		--with-DIR_MAN=/usr/share/man \
		--with-DIR_SPOOL=/var/spool/"$pkgname" \
		--with-DIR_HTML=/usr/share/doc/"$pkgname"/html \
		--with-PATH_IMPRIP="" \
		--with-SYSVINIT=no \
		--with-REGEX=yes \
		--with-LIBTIFF="-ltiff -lz" \
		--with-LIBINTL="-lintl" \
		--with-DSO=auto \
		--with-PATH_EGETTY=/bin/false \
		--with-PATH_VGETTY=/bin/false \
		--with-SYSUID=root \
		--with-SYSGID=root

	# parallel build breaks libfaxutil dso building
	make -j1
}

package() {
	# this makefile has issues installing, it doesn't use the standard
	#   install - but the following seems to work
	mkdir -p "$pkgdir"/usr/bin "$pkgdir"/usr/sbin
	mkdir -p "$pkgdir"/usr/lib/$pkgname "$pkgdir"/usr/share/man
	mkdir -p "$pkgdir"/usr/share/locale/$pkgname
	touch "$pkgdir"/usr/lib/$pkgname/pagesizes
	chown uucp:uucp "$pkgdir"/usr/lib/$pkgname
	chmod 0600 "$pkgdir"/usr/lib/$pkgname

	make \
		BIN="$pkgdir/usr/bin" \
		SBIN="$pkgdir/usr/sbin" \
		LIBDIR="$pkgdir/usr/lib" \
		LIB="$pkgdir/usr/lib" \
		LIBEXEC="$pkgdir/usr/sbin" \
		LIBDATA="$pkgdir/usr/lib/$pkgname" \
		MAN="$pkgdir/usr/share/man" \
		LOCALEDIR="$pkgdir/usr/share/locale/$pkgname" \
		SPOOL="$pkgdir/var/spool/$pkgname" \
		HTMLDIR="$pkgdir/usr/share/doc/$pkgname/html" \
	install

	install -m644 -D "$builddir/COPYRIGHT" \
		"$pkgdir"/usr/share/licenses/$pkgname/COPYRIGHT
	install -m644 -D "$builddir/README" \
		"$pkgdir"/usr/share/doc/$pkgname/README

	install -D -m755 "$srcdir"/$pkgname.initd \
		"$pkgdir"/etc/init.d/$pkgname
	install -D -m644 "$srcdir"/$pkgname.confd \
		"$pkgdir"/etc/conf.d/$pkgname
}

sha512sums="
e87758307ab870b6d2d3a517b3e1448375edb0c4725df96b827fcd12c8323059134bf328196f1155781b5f1021700ae916f32c6343543cb1378dd6eaa965900b  hylafax-7.0.10.tar.gz
ae9de1dbf53ef64acd8b03515c5cd840c12596921edb8c45a333eb7a69e911ec3a449a9f0201c5c73d54d9f01c4696f1accacf1e83137737341a5913f0725b16  hylafaxplus.initd
a2117eddc8f0ff70a23a90f2001dcb88c5bddee46ffa021d6d1701cc5cfc3bcb0362ead2b1b1ce2b288992728053c5947466d08916649f45e7dfb1876576e50f  hylafaxplus.confd
41ae2055a7781d83fc275aafe18ced0fe75ba79d3ad7d5096eabaeae3a514b564723185dd33820268577174f6c53bfcfddb30922ba50754b15c5c3b0abbec837  common-functions-busybox-awk.patch
4a1243daff9904e6395c3e28aa4a78a74de99f5aa9dbf5055a3781acfcd9b1b3db42b1569409b27e3ef9b0e55272dc99122436a79a08c9a1c140c2547c5a2c15  no-locale.patch
f5f1e33897a91b8297311c033d50e7ea2f9088568264a5b9224285066a504da8cc4296f973dd0a70e09abca538cef26964c6181f4f67f76400783d0697f05e61  utf8-dictionary.patch
56a747d0592a4f7caa90b4bbf2f7f01a8000e80bea0f33a4d15af87315789cc3ca0b6031312db6d7a93ac4f4d16abe540331ef841c4911b291f0af30e41c8e8f  dont-ship-xferfaxlog-file.patch
49bd5e1f590c59de1a96cafa96f3ce5ba0afbacbf08f026682f5be56e4405f95a06df6acef5429a158652b967a446c7c976274729342608527ccbc035979f0b1  config-files-default-extension.patch
"
```

### Chain of trust from this recipe to the running container

1. Alpine's build infra (`abuild`) compiles the tarball above, applies the
   5 patches, and produces `hylafaxplus-7.0.10-r0.apk`.
2. That `.apk` is signed and published to
   `https://dl-cdn.alpinelinux.org/alpine/v3.22/community/x86_64/hylafaxplus-7.0.10-r0.apk`.
3. `docker/Dockerfile` runs `apk add hylafaxplus=7.0.10-r0` against the
   `alpine:3.22` base image, whose `/etc/apk/repositories` points at that
   same CDN and whose `/etc/apk/keys/` holds Alpine's signing keys - `apk`
   verifies the signature before installing anything.
4. `docs/BUILD.md`'s pin (`HYLAFAX_PKG_VERSION=7.0.10-r0` in
   `docker/versions.env`) makes step 3 fail loudly, not silently upgrade,
   if that exact build is ever superseded on the mirror.

No third-party or unofficial repository is added anywhere in this chain.

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
