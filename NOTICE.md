# Third-party notices

This repository's own content (Dockerfile, scripts, compose file,
Jenkinsfile, docs) is MIT-licensed - see [LICENSE](LICENSE). The resulting
container image installs the following third-party software, each under its
own license:

## hylafax+

Installed via Alpine's `hylafaxplus` package (`apk add hylafaxplus`), built
from the upstream [hylafax+ project](https://hylafax.sourceforge.io/)
source.

```
HylaFAX Facsimile Software
Copyright (c) 1990-1996 Sam Leffler
Copyright (c) 1991-1996 Silicon Graphics, Inc.
HylaFAX is a trademark of Silicon Graphics, Inc.

Permission to use, copy, modify, distribute, and sell this software and
its documentation for any purpose is hereby granted without fee, provided
that (i) the above copyright notices and this permission notice appear in
all copies of the software and related documentation, and (ii) the names of
Sam Leffler and Silicon Graphics may not be used in any advertising or
publicity relating to the software without the specific, prior written
permission of Sam Leffler and Silicon Graphics.

THE SOFTWARE IS PROVIDED "AS-IS" AND WITHOUT WARRANTY OF ANY KIND,
EXPRESS, IMPLIED OR OTHERWISE, INCLUDING WITHOUT LIMITATION, ANY
WARRANTY OF MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.

IN NO EVENT SHALL SAM LEFFLER OR SILICON GRAPHICS BE LIABLE FOR
ANY SPECIAL, INCIDENTAL, INDIRECT OR CONSEQUENTIAL DAMAGES OF ANY KIND,
OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
WHETHER OR NOT ADVISED OF THE POSSIBILITY OF DAMAGE, AND ON ANY THEORY OF
LIABILITY, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE
OF THIS SOFTWARE.
```

Full text: `COPYRIGHT` in the
[hylafax+ source distribution](https://sourceforge.net/projects/hylafax/),
or `apk info hylafaxplus` / the Alpine `aports` `APKBUILD` for this exact
package build.

## iaxmodem

Installed via Alpine's `iaxmodem` package. GPL-2.0-or-later. Project:
https://iaxmodem.sourceforge.net/.

## Alpine Linux

Base image and all other `apk` packages (`ghostscript`, `tiff`,
`tiff-tools`, `openssl`, `busybox`, ...) - each under its own upstream
license, tracked by Alpine's package metadata
(`apk info -a <package>`). Alpine Linux itself: MIT.

## Generating a full SBOM

For a complete, per-package license and version manifest of a specific
built image (not just the highlights above), see the `SBOM` stage in
`ci/Jenkinsfile`, or run locally:

```sh
syft hylafax-plus:local -o cyclonedx-json=sbom.json
```
