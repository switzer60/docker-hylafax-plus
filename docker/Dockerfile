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
ARG ALPINE_VERSION=3.22
ARG ALPINE_DIGEST=sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8

FROM alpine:${ALPINE_VERSION}@${ALPINE_DIGEST}

ARG HYLAFAX_PKG_VERSION=7.0.10-r0
ARG IAXMODEM_PKG_VERSION=1.3.4-r0

LABEL org.opencontainers.image.title="hylafax+" \
      org.opencontainers.image.description="hylafax+ fax server on Alpine Linux, driven entirely by docker-compose environment variables" \
      org.opencontainers.image.source="https://github.com/OWNER/hylafax-plus-docker" \
      org.opencontainers.image.licenses="MIT"

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
