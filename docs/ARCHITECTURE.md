# Architecture

## Process model

One container, four kinds of long-lived process, supervised directly by
`docker/entrypoint.sh` (PID 1 in the container - no s6/supervisord; see
["Why no init system"](#why-no-init-system) below):

```
entrypoint.sh (PID 1)
├─ syslogd                      (busybox, logs to stdout so `docker logs` sees it)
├─ faxq                         (one, always - the scheduler)
├─ hfaxd                        (one, if HFAXD_ENABLE=yes - client-server protocol, port 4559)
└─ per modem slot (MODEM_1.. MODEM_<MODEM_COUNT>):
   ├─ iaxmodem                  (only if MODEM_<N>_TYPE=iaxmodem; creates /dev/<device>)
   └─ faxgetty /dev/<device>    (always - watches the modem, answers calls, hands off to faxq)
```

`entrypoint.sh` traps `SIGTERM`/`SIGINT`, forwards to every tracked child,
and waits for clean exit - `docker compose stop` takes well under a second
in practice (see `tests/smoke-test.sh`, which asserts this). If *any*
supervised process dies unexpectedly, the entrypoint tears the rest down
and exits non-zero, so `restart: unless-stopped` recovers the whole
container rather than leaving it running with e.g. `faxq` dead and `hfaxd`
still accepting jobs it can never send.

### Why no init system

s6-overlay/supervisord/runit are the usual answer for "several processes in
one container." We didn't reach for one because the process set here is
small, fixed-shape (known at container start from `MODEM_COUNT`, not
dynamic), and the trap/wait/kill logic fits in the ~40 lines you can read in
`entrypoint.sh` - adding a supervisor framework would be a dependency and a
new failure mode in exchange for solving a problem bash's own job control
already solves at this scale. Revisit this if a future need (log rotation,
per-process restart-without-killing-the-container, etc.) outgrows plain
`wait -n`.

## Why one container, not one-modem-per-container

`faxq` is a single scheduler that expects to own the whole spool
(`/var/spool/hylafaxplus`) and coordinate every modem attached to it -
that's how hylafax+'s job-to-modem assignment, `ModemGroup`s, and
`xferfaxlog` are designed to work. Splitting modems across containers would
mean either sharing the spool volume across containers (unsupported by
hylafax+ - `faxq` is not written to be run twice against the same spool) or
running a separate scheduler per modem with no shared queue - defeating the
purpose of having more than one line. One container, N modems, is the
supported shape.

## Spool layout (`/var/spool/hylafaxplus`, one named volume)

| Path | Contents |
|---|---|
| `etc/config` | Scheduler-wide settings, regenerated every boot from `FAX_*` env vars. |
| `etc/config.<devid>` | Per-modem settings, regenerated every boot from `MODEM_<N>_*` env vars merged with a `config/<profile>` prototype. |
| `etc/hosts.hfaxd` | Client access control, regenerated every boot from `HYLAFAX_*` env vars. |
| `etc/ssl.pem` | Self-signed cert from the one-time build-time `faxsetup` run (SSL Fax) - mount your own over it if you use that feature. |
| `config/*` | ~90 read-only modem prototype files shipped by the `hylafaxplus` package (real hardware profiles + `iaxmodem`/`class1`/`class2`). |
| `docq/`, `sendq/`, `recvq/`, `doneq/`, `pollq/` | Job/document queues - the actual fax data. |
| `log/` | Per-session transcripts (`ServerTracing`/`SessionTracing` controlled). |
| `status/` | Live modem status files, read by `faxstat`. |

Everything here persists in the `hylafax_spool` named volume across
container recreation; only the `etc/*` files listed above are regenerated
(idempotently, from current env vars) on every start.

## Image layers

Single-stage build (see `docker/Dockerfile` and `docs/BUILD.md` for the
full reasoning): Alpine base (pinned by digest) → `apk add` the
`hylafaxplus`/`iaxmodem` packages and their runtime deps → one `RUN
faxsetup` at build time → copy in `entrypoint.sh`/`healthcheck.sh`. No
compiler, no source tarball, no multi-stage copy - there's nothing to
compile, since we install from a distro package (see `docs/BUILD.md#why-a-distro-package-instead-of-compiling-from-source`).
Final image is Alpine-small: `hylafaxplus` + `iaxmodem` + their shared-lib
dependencies (libtiff, ghostscript, openssl, ...), nothing else.

## Network

- **hfaxd** (TCP, `HFAXD_PORT`, default 4559): the hylafax+ client-server
  protocol (FTP-like; `sendfax`/`faxstat`/`faxalter` and any HylaFAX client
  library talk to this). Exposed via `ports:` in `docker-compose.yml`.
- **iaxmodem** (UDP, outbound only, to `MODEM_<N>_IAX_SERVER:MODEM_<N>_IAX_PORT`):
  IAX2 to your Asterisk/FreePBX server. The container never listens for
  this - it's an outbound client connection, so nothing needs publishing in
  `ports:` for it.
- **SNPP** (paging protocol) is supported by hfaxd (`-s port`) but off by
  default and not wired into the entrypoint - flag if you need it; it's a
  small addition to `MODEM_*`/`HFAXD_*` handling and `docker-compose.yml`.
