# syntax=docker/dockerfile:1
#
# hylafax+ on Alpine Linux, built entirely from pinned, checksummed distro
# packages - no source compilation. See docs/BUILD.md for the exact,
# reproducible steps this Dockerfile automates and why each pin exists.
#
# Build args let CI (or a local build) bump versions deliberately instead of
# silently drifting:
#   ALPINE_VERSION / ALPINE_DIGEST   base image, pinned by digest
#   HYLAFAX_PKG_VERSION              exact `apk` package version (fails loudly
#                                    if that exact version is no longer served)
ARG ALPINE_VERSION=3.24.2
ARG ALPINE_DIGEST=sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

FROM alpine:${ALPINE_VERSION}@${ALPINE_DIGEST}

ARG HYLAFAX_PKG_VERSION=7.0.11-r0
ARG IAXMODEM_PKG_VERSION=1.3.4-r1
# ALPINE_VERSION/ALPINE_DIGEST were only in scope for the FROM line above -
# re-declared (bare, no new default) to pull their existing values into this
# build stage so the LABELs below can actually reference them; without this
# they'd silently resolve to empty strings.
ARG ALPINE_VERSION
ARG ALPINE_DIGEST

# Standard OCI annotations, plus a project-specific set recording exactly
# which Alpine/hylafaxplus/iaxmodem build produced this image and where
# each package's own build recipe lives - see docs/BUILD.md for the same
# provenance chain in prose. image.version matches the composite tag this
# same build gets published under (docs/BUILD.md#tagging) - not just the
# hylafax+ version - so the label and the pullable tag never disagree.
LABEL org.opencontainers.image.title="hylafax+" \
      org.opencontainers.image.description="hylafax+ fax server on Alpine Linux, driven entirely by docker-compose environment variables" \
      org.opencontainers.image.source="https://github.com/switzer60/docker-hylafax-plus" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="alpine-${ALPINE_VERSION}_hylafaxplus-${HYLAFAX_PKG_VERSION}_iaxmodem-${IAXMODEM_PKG_VERSION}" \
      org.opencontainers.image.base.name="alpine:${ALPINE_VERSION}" \
      org.opencontainers.image.base.digest="${ALPINE_DIGEST}" \
      io.github.switzer60.docker-hylafax-plus.alpine-version="${ALPINE_VERSION}" \
      io.github.switzer60.docker-hylafax-plus.hylafaxplus-version="${HYLAFAX_PKG_VERSION}" \
      io.github.switzer60.docker-hylafax-plus.hylafaxplus-apk-source="https://gitlab.alpinelinux.org/alpine/aports/-/blob/v${ALPINE_VERSION}/community/hylafaxplus/APKBUILD" \
      io.github.switzer60.docker-hylafax-plus.iaxmodem-version="${IAXMODEM_PKG_VERSION}" \
      io.github.switzer60.docker-hylafax-plus.iaxmodem-apk-source="https://gitlab.alpinelinux.org/alpine/aports/-/blob/v${ALPINE_VERSION}/main/iaxmodem/APKBUILD"

# hylafaxplus     - the fax server itself (faxq, hfaxd, faxgetty, sendfax, ...)
# iaxmodem        - software modem over IAX2/VoIP; the default, hardware-free
#                    way to give the container a fax line (see docs/MODEMS.md)
# bash            - the entrypoint is bash, for `local -n` nameref support
# openssl         - generates hosts.hfaxd password hashes and the SSL Fax cert
# busybox-extras  - provides `nc`, used by the healthcheck
# tzdata          - so TZ= is honored for log timestamps
RUN apk add --no-cache \
        hylafaxplus=${HYLAFAX_PKG_VERSION} \
        iaxmodem=${IAXMODEM_PKG_VERSION} \
        bash \
        openssl \
        busybox-extras \
        tzdata \
        procps

# --- One-time, deterministic `faxsetup` run -------------------------------
# faxsetup(8C) is an interactive script, but every prompt in a fresh install
# either has a sane default (blank input accepts it) or is one of the two
# "do you want to do X now" prompts we explicitly decline, because the
# entrypoint does per-modem setup itself at container start instead (see
# render_modem_config in entrypoint.sh). faxsetup-answers.txt is the exact,
# literal transcript of accepted answers - see docs/BUILD.md for how it was
# derived and how to regenerate/verify it against a new hylafaxplus version.
COPY docker/faxsetup-answers.txt /tmp/faxsetup-answers.txt
RUN faxsetup < /tmp/faxsetup-answers.txt > /var/log/faxsetup.log 2>&1 \
    && rm -f /tmp/faxsetup-answers.txt \
    && tail -5 /var/log/faxsetup.log

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

VOLUME ["/var/spool/hylafaxplus"]

EXPOSE 4559/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
