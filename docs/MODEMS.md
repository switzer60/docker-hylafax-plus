# Modems: iaxmodem (default) vs. real hardware

The container never talks to a phone line directly. It talks to one of two
things, selected per-modem via `MODEM_<N>_TYPE`:

- **`iaxmodem`** (default): a software modem (the `iaxmodem` package,
  using the spandsp soft-DSP fax stack) that registers as an IAX2 peer to an
  Asterisk/FreePBX server and presents a normal-looking Hayes/Class 1 AT
  command interface locally. No hardware, works identically on a laptop or
  a cloud VPS. This is what `docker-compose.yml` is set up for out of the
  box.
- **`serial`**: a real USB/serial fax modem, passed through from the Docker
  host via compose's `devices:`.

Both can be mixed in the same container (different `MODEM_<N>_TYPE` per
slot).

## iaxmodem: pointing at Asterisk

You need an Asterisk (or FreePBX) server reachable from the container over
UDP, with an IAX2 peer defined for the fax modem. Minimal `iax.conf` peer
(classic `chan_iax2`):

```ini
[fax1]
type=friend
host=dynamic
secret=change-me
context=fax-inbound
disallow=all
allow=alaw
qualify=yes
```

And a dialplan context that sends inbound calls to that peer, and lets it
dial out:

```ini
[fax-inbound]
exten => _X.,1,Dial(IAX2/fax1,60)
 same => n,Hangup()

; if this peer should be reachable by extension number too:
[from-fax1]
include => fax-inbound
```

Then in `.env` (or `docker-compose.yml` directly):

```env
MODEM_1_TYPE=iaxmodem
MODEM_1_DEVICE=ttyIAX0
MODEM_1_IAX_SERVER=asterisk.internal.example.com
MODEM_1_IAX_PEER_NAME=fax1
MODEM_1_IAX_PEER_SECRET=change-me
MODEM_1_FAX_NUMBER=+19195551212
```

`docker compose up -d` and watch `docker compose logs -f`:

```
starting iaxmodem for ttyIAX0 -> IAX2 server asterisk.internal.example.com:4569 as peer 'fax1'
FaxGetty[..]: OPEN /dev/ttyIAX0  HylaFAX (tm) Version 7.0.10
FaxGetty[..]: MODEM WWW.SOFT-SWITCH.ORG spandsp/...
```

`faxstat -s` inside the container (or `docker compose exec fax faxstat -s`)
should show `Running and idle`. If it instead shows the modem stuck in a
setup/wedged state, the IAX2 registration is failing - check
`MODEM_1_IAX_SERVER`/`_PEER_NAME`/`_PEER_SECRET` against Asterisk's own
`iax2 show peers` / `core set verbose 5` output; iaxmodem's local AT
interface (and the container's healthcheck) comes up successfully even
before registration succeeds, since these are independent as far as
iaxmodem is concerned.

No firewall change is needed on the container side beyond outbound UDP -
iaxmodem initiates the connection to `MODEM_<N>_IAX_SERVER`. Nothing needs
to be exposed in `ports:` for this to work.

## Real hardware (`serial`)

1. Plug the modem in, find its **stable** path:
   ```sh
   ls -l /dev/serial/by-id/
   ```
   Always use this path, never a bare `/dev/ttyUSBx` - USB enumeration
   order is not guaranteed across host reboots.
2. In `docker-compose.yml`, uncomment the `devices:` block and point it at
   that path, mapped to whatever container-side name you choose:
   ```yaml
   devices:
     - "/dev/serial/by-id/usb-USRobotics_USR5637-if00-port0:/dev/ttyUSB0"
   ```
3. Set the matching env vars:
   ```env
   MODEM_COUNT=1
   MODEM_1_TYPE=serial
   MODEM_1_DEVICE=ttyUSB0
   MODEM_1_PROFILE=usr-2.0
   MODEM_1_FAX_NUMBER=+19195551212
   ```
4. `MODEM_<N>_PROFILE` must match one of the ~90 prototype files shipped in
   the image:
   ```sh
   docker run --rm hylafax-plus:local ls /var/spool/hylafaxplus/config
   ```
   If your exact modem isn't listed, `class1` or `class2` (generic,
   standards-based profiles) are safe starting points - see
   `faxaddmodem(8C)`'s "PROTOTYPE CONFIGURATION FILES" section for how
   hylafax+ itself would normally auto-detect this from `ATI0`/`ATI3`; this
   container does the profile selection explicitly via
   `MODEM_<N>_PROFILE` instead (see docs/BUILD.md for why we don't drive
   live AT-probing during setup).

Only one container can hold a given passed-through device at a time - don't
map the same host device into two compose stacks.

## Adding more than two modems

`docker-compose.yml` ships a `MODEM_1_*` block plus a commented `MODEM_2_*`
block as a template (`MODEM_COUNT` itself defaults to `0` - see
docs/CONFIGURATION.md). To go further: copy the `MODEM_2_*` block,
increment the number, add a matching `devices:` entry if it's `serial`, and
set `MODEM_COUNT` to match. There's no hard limit in the entrypoint;
practical limits are IAX2 channel/CPU capacity (iaxmodem) or physical ports
(serial).
