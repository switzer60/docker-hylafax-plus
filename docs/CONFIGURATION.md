# Configuration reference

Every variable here is read by [`docker/entrypoint.sh`](../docker/entrypoint.sh)
on every container start (not just the first) and used to (re)generate the
hylafax+ config files under `/var/spool/hylafaxplus/etc/`. Change a value,
`docker compose up -d` (or `restart`), and the new config takes effect on
next boot - nothing needs to be re-baked into the image.

Anything not listed here is still reachable: see
["Escape hatch: CUSTOM_CONFIG_DIR"](#escape-hatch-custom_config_dir) below.

## Global

| Variable | Default | Meaning |
|---|---|---|
| `TZ` | `UTC` | Container timezone (log timestamps). |
| `FAX_COUNTRY_CODE` | `1` | `CountryCode` - see `hylafax-config(5F)`. |
| `FAX_AREA_CODE` | `000` | `AreaCode`. |
| `FAX_LONG_DISTANCE_PREFIX` | `1` | `LongDistancePrefix`. |
| `FAX_INTERNATIONAL_PREFIX` | `011` | `InternationalPrefix`. |
| `FAX_DIAL_RULES` | `dialrules` | Which `var/spool/hylafaxplus/etc/dialrules*` file to use (`dialrules`, `dialrules.europe`, `dialrules.uk`, `dialrules.world`, `dialrules.sf-ba`, `dialrules-pabx.be`, `dialrules.ext`). |
| `FAX_TIMEOFDAY` | `Any` | `TimeOfDay` - outbound call window, e.g. `Wk1705-0855,Wk2305-0855`. |
| `FAX_MAX_DIALS` | `12` | `MaxDials` per job. |
| `FAX_MAX_TRIES` | `3` | `MaxTries` per job. |
| `FAX_MAX_CONCURRENT_CALLS` | `1` | `MaxConcurrentCalls` to the same destination. |
| `FAX_POSTSCRIPT_TIMEOUT` | `180` | `PostScriptTimeout` (secs) for RIP'ing submitted documents. |
| `FAX_SERVER_TRACING` | `1` | `ServerTracing` bitmask. |
| `FAX_SESSION_TRACING` | `0xFFF` | `SessionTracing` bitmask (send/recv sessions). |
| `FAX_LOG_FACILITY` | `daemon` | syslog facility for server tracing. |

## hfaxd (client-server protocol)

| Variable | Default | Meaning |
|---|---|---|
| `HFAXD_ENABLE` | `yes` | Set `no` to run outbound-only, no client protocol server at all. |
| `HFAXD_PORT` | `4559` | TCP port (`hfaxd -i`). |
| `HFAXD_BIND_ADDRESS` | `0.0.0.0` | Bind address (`hfaxd -l`). |

## Access control

| Variable | Default | Meaning |
|---|---|---|
| `HYLAFAX_ADMIN_USER` | `admin` | Username provisioned into `etc/hosts.hfaxd` with administrative rights. |
| `HYLAFAX_ADMIN_PASSWORD` | *(generated)* | If unset, a random password is generated on first boot, printed once to `docker compose logs`, and persisted (in the `hylafax_spool` volume) so later restarts keep the same one instead of rotating it. Set this to pin a password explicitly - explicit always wins and re-applies on every boot, so it's also how you rotate one. Stored only as a salted SHA-512 crypt hash (`openssl passwd -6`) in `etc/hosts.hfaxd`, mode `0600`, owned by `uucp`; the plaintext is never written anywhere except that one log line. |
| `HYLAFAX_ADMIN_ADMINWORD` | *(same as password)* | Separate password required for `ADMIN` (privileged) commands, if you want it distinct from login. |
| `HYLAFAX_ALLOW_HOSTS` | *(empty)* | Comma-separated extra `hosts.hfaxd` entries (regexes or CIDRs), appended after the admin entry. `127.0.0.1` and `::1` are always trusted. See `hosts.hfaxd(5F)` for the pattern syntax. |

## Modems

`MODEM_COUNT` (default `0`) controls how many `MODEM_<N>_*` blocks
(N = 1..MODEM_COUNT) the entrypoint looks for. At `0`, `faxq`/`hfaxd` still
start with no modem at all - useful for a first look at a freshly pulled
image before wiring anything up. A slot with no `MODEM_<N>_DEVICE` set is
skipped with a logged warning, so you can leave higher-numbered blocks
defined but inactive.

| Variable | Default | Meaning |
|---|---|---|
| `MODEM_<N>_TYPE` | `iaxmodem` | `iaxmodem` (software modem over IAX2/VoIP, no hardware) or `serial` (a real device passed through via compose `devices:`). |
| `MODEM_<N>_DEVICE` | *(required)* | Device name **without** `/dev/`, e.g. `ttyIAX0` or `ttyUSB0`. For `serial`, must match the container-side target in your `devices:` mapping. |
| `MODEM_<N>_PROFILE` | `iaxmodem` (type=iaxmodem) or `class1` (type=serial) | Any filename under `var/spool/hylafaxplus/config/` in the image - run `docker run --rm hylafax-plus:local ls /var/spool/hylafaxplus/config` for the full list (~90 real-hardware prototypes: `usr-2.0`, `hayes`, `zyxel-2864`, `digi`, ...). |
| `MODEM_<N>_FAX_NUMBER` | *(empty)* | `FAXNumber` - this modem's phone number, e.g. `+19195551212`. |
| `MODEM_<N>_LOCAL_ID` | `HylaFAX` | `LocalIdentifier` (TSI string sent to the far end). |
| `MODEM_<N>_RINGS_BEFORE_ANSWER` | `1` | `RingsBeforeAnswer`. |
| `MODEM_<N>_TAGLINE` | *(unset = hylafax+ default)* | `TagLineFormat`. |
| `MODEM_<N>_COUNTRY_CODE`, `_AREA_CODE`, `_LONG_DISTANCE_PREFIX`, `_INTERNATIONAL_PREFIX` | falls back to the matching `FAX_*` global | Per-modem override, for a box with lines in different area codes. |

### `iaxmodem` type only

| Variable | Default | Meaning |
|---|---|---|
| `MODEM_<N>_IAX_SERVER` | *(required)* | Hostname/IP of your Asterisk/FreePBX IAX2 endpoint. |
| `MODEM_<N>_IAX_PORT` | `4569` | IAX2 UDP port. |
| `MODEM_<N>_IAX_PEER_NAME` | *(device name)* | IAX2 peer/username. |
| `MODEM_<N>_IAX_PEER_SECRET` | *(empty)* | IAX2 secret. |
| `MODEM_<N>_IAX_CIDNAME` | `HylaFAX` | Caller-ID name presented on outbound calls. |
| `MODEM_<N>_IAX_CIDNUMBER` | `0000000000` | Caller-ID number. |
| `MODEM_<N>_IAX_CODEC` | `alaw` | IAX2 codec (`alaw`/`ulaw` for fax - do not use a compressed codec). |
| `MODEM_<N>_IAX_REFRESH` | `900` | IAX2 registration refresh interval (secs). |

See [docs/MODEMS.md](MODEMS.md) for a worked Asterisk example and the
`serial` (real hardware) path.

## Escape hatch: `CUSTOM_CONFIG_DIR`

Mounted at `/config-overrides` (bind-mount `./config-overrides` by default in
`docker-compose.yml`). Any file dropped there is copied, verbatim, over the
matching generated file **after** every other step, on every boot:

| File in `config-overrides/` | Replaces |
|---|---|
| `config` | `etc/config` (scheduler-wide settings) |
| `hosts.hfaxd` | `etc/hosts.hfaxd` (access control) |
| `config.<devid>` | `etc/config.<devid>` (one specific modem, e.g. `config.ttyIAX0`) |

This covers the full `hylafax-config(5F)` parameter space (~150 tags) - the
env vars above are the common subset made convenient; this is the subset
made *complete*. A file here always wins over the generated version, so it's
also how you'd hand-tune a single modem beyond what `MODEM_<N>_*` exposes
without forking the entrypoint.
