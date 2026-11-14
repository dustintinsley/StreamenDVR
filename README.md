# StreamenDVR

A small, self-hosted DVR server for the [Streamen](https://github.com/dustintinsley/Streamen)
IPTV app. Streamen schedules a recording ("record this programme"); StreamenDVR
runs on an always-on machine (NAS, mini PC, Raspberry Pi, Mac) and records the
stream with ffmpeg to HLS on disk, even when every Apple device is asleep.
Finished and in-progress recordings play back in Streamen over short-lived signed
links.

- One ffmpeg process per recording, stream copy (no transcoding), HLS output.
- Automatic retries with `#EXT-X-DISCONTINUITY` when the source drops.
- Survives restarts: running recordings resume, missed ones are marked.
- Pairing with a 6-digit code, per-device bearer tokens (stored hashed).
- Bonjour discovery (`_streamen-dvr._tcp`), JSON HTTP API, no database.

> **Your responsibility:** only record content you are entitled to record and
> keep. StreamenDVR ships no channels or streams. It records what your Streamen
> app points it at, using your provider credentials, for your private use.

## Mac app (no Docker)

On a Mac you can run StreamenDVR as a menu-bar app instead of a container:

1. Download [StreamenDVR.dmg](https://streamen.app/download/StreamenDVR.dmg)
   (always the latest version; past versions are on the
   [releases page](https://github.com/dustintinsley/StreamenDVR/releases)),
   open it, and drag StreamenDVR into Applications. It's signed and notarized
   by Apple, so it opens without a Gatekeeper warning.
2. Open the app. A record icon appears in the menu bar. Click it to see the
   pairing code, recording status and paired devices.

ffmpeg is built in, so there's nothing else to install. The app registers itself to open at login (toggle it in the menu), keeps the
Mac from idle-sleeping while recordings are running or scheduled, and stops
ffmpeg cleanly when you quit. Data lives in
`~/Library/Application Support/StreamenDVR`, the log in
`~/Library/Logs/StreamenDVR/streamen-dvr.log`. The environment variables
from [Configuration](#configuration) still apply. A Mac whose lid is closed
(without an external display) still sleeps and misses recordings.

## Quick start (Docker)

The image is `streamen.app/streamen-dvr` (amd64 and arm64; `latest` or a
version such as `1.0.0`). Nothing to build.

### Linux / NAS (Docker Compose)

Save this as `docker-compose.yml`, set `TZ` to your time zone, then run
`docker compose up -d`:

```yaml
services:
  streamen-dvr:
    image: streamen.app/streamen-dvr:latest
    container_name: streamen-dvr
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./data:/data
    environment:
      TZ: "America/New_York"
```

Host networking lets Streamen find the server automatically (Bonjour). On a
NAS, paste the same compose file into Container Manager, Portainer or your
NAS's Docker app. The pairing code is in the log:
`docker logs streamen-dvr | grep "Pairing code"`.

To update: `docker compose pull && docker compose up -d`.

### Docker Desktop (macOS / Windows)

Docker Desktop's network can't carry Bonjour, so publish the port and add the
server in Streamen by address (`<computer-ip>:8090`):

```yaml
services:
  streamen-dvr:
    image: streamen.app/streamen-dvr:latest
    container_name: streamen-dvr
    restart: unless-stopped
    ports:
      - "8090:8090"
    volumes:
      - ./data:/data
    environment:
      BONJOUR: "0"
      TZ: "America/New_York"
```

### docker run

```bash
docker run -d --name streamen-dvr --restart unless-stopped \
  --network host -v "$PWD/data:/data" streamen.app/streamen-dvr:latest
docker exec streamen-dvr streamen-dvr pair
```

On Docker Desktop use `-p 8090:8090 -e BONJOUR=0` in place of `--network host`.

### Apple `container` (macOS on Apple silicon)

```bash
container system start
mkdir -p ~/StreamenDVR-data
container run -d --name streamen-dvr \
  -p 0.0.0.0:8090:8090 -v ~/StreamenDVR-data:/data \
  -e BONJOUR=0 streamen.app/streamen-dvr:latest
container exec streamen-dvr streamen-dvr pair
```

The container runs in a VM, so Bonjour doesn't reach your network: in Streamen use
**Settings → Recording Server → Enter Address Manually** with your Mac's IP and
port 8090.

The server runs as the unprivileged `streamen` user. The entrypoint hands `/data`
to that user when it can; shared host folders (Docker Desktop, Apple
`container`) refuse `chown`, in which case it runs as the folder's owner or, if
only root can write there, as root, and says so in the log.

### Build the image yourself

`docker-compose.yml` in this repo uses the published image; to build from a
checkout instead, replace its `image:` line with `build: .` and run
`docker compose up -d --build` (the first build takes a while: Swift, ~4 GB
RAM). With Apple `container`: `container build -t streamen-dvr:dev .`.

### Without Docker

Needs Swift 6 and ffmpeg (`brew install ffmpeg` / `apt install ffmpeg`):

```bash
swift run -c release streamen-dvr --data-dir ./data
```

On macOS this also advertises the server via Bonjour, so the iOS Simulator and
devices on your LAN discover it.

## Pairing

1. Start the server. It logs a code, and logs a new one every 10 minutes:
   `Pairing code: 123 456 (valid 10 min)`
2. Print the current code at any time:
   `docker exec streamen-dvr streamen-dvr pair` (or `streamen-dvr pair --data-dir ./data`).
   The Mac app shows it in its menu.
3. In Streamen, pick the discovered server (or enter `host:port`) and type the code.

A code stays valid for its whole 10-minute window, so several devices can pair
with it. After 5 wrong codes within a minute, pairing is locked for that
minute (`429`). Devices can be listed and unpaired from Streamen.

## Configuration

Every variable also has a CLI flag on `streamen-dvr serve` (e.g. `--port`,
`--data-dir`, `--max-concurrent`); a flag wins over its variable.

| Variable | Default | Meaning |
|----------|---------|---------|
| `PORT` | `8090` | HTTP port |
| `HOST` | `0.0.0.0` | Bind address |
| `DATA_DIR` | `/data` (Docker), `./data` otherwise | State, secrets and recordings |
| `MAX_CONCURRENT` | `4` | Recordings that may run at once (each holds one provider connection) |
| `MIN_FREE_GB` | `2` | Refuse/fail recordings below this much free disk |
| `SERVER_NAME` | hostname | Name shown in Streamen and in Bonjour |
| `PUBLIC_URL` | unset | Base URL for playback links when a request carries no `Host` header |
| `FFMPEG_PATH` | `ffmpeg` on `PATH` | ffmpeg executable |
| `LOG_LEVEL` | `info` | `trace`, `debug`, `info`, `notice`, `warning`, `error`, `critical` |
| `BONJOUR` | `1` | `0` disables Bonjour (NetService on macOS, avahi in Docker) |
| `SINGLE_FILE_RECORDINGS` | `0` | `1` merges each finished recording into one `recording.ts` (see below) |
| `TZ` | UTC | Container timezone (log timestamps only; the API is UTC) |

Data layout:

```
DATA_DIR/
├── server.json          server id + playback-signing secret (keep private)
├── recordings.json      recording records, including stream URLs (keep private)
├── devices.json         paired devices (SHA-256 token hashes only)
├── pairing-code.json    current pairing code (read by `streamen-dvr pair`)
└── recordings/<id>/     index.m3u8 + a<attempt>_<n>.ts segments
                         (finished, with SINGLE_FILE_RECORDINGS: index.m3u8 + recording.ts)
```

Files are written atomically and readable only by the server user (`0600`).

## Bonjour / discovery

The server advertises `_streamen-dvr._tcp` with TXT records `id=<server id>`,
`version=<version>`, `api=1`.

- **macOS (`swift run`)**: advertised with `NetService`.
- **Docker on Linux**: the entrypoint starts `avahi-daemon` inside the container.
  This only reaches your LAN with **`network_mode: host`**.
- **Bridge networking, Docker Desktop (macOS/Windows), or VLANs**: multicast
  doesn't leave the container. Set `BONJOUR=0` and enter `host:8090` in Streamen.
- **The host already runs avahi-daemon** (common on NAS systems): two mDNS
  responders on one host fight over the hostname. Set `BONJOUR=0` and put this
  file in the host's `/etc/avahi/services/streamen-dvr.service`, with the id from
  `docker exec streamen-dvr streamen-dvr server-id`:

  ```xml
  <?xml version="1.0" standalone='no'?>
  <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
  <service-group>
    <name replace-wildcards="yes">%h</name>
    <service>
      <type>_streamen-dvr._tcp</type>
      <port>8090</port>
      <txt-record>id=PASTE-SERVER-ID</txt-record>
      <txt-record>version=1.0.1</txt-record>
      <txt-record>api=1</txt-record>
    </service>
  </service-group>
  ```

## HTTP API (v1)

All JSON; dates are ISO-8601 UTC (fractional seconds optional on input).
Errors always look like `{"error":{"code":"snake_case","message":"…"}}`.
Swift clients should use `StreamenDVRKit` (in `Kit/`), which wraps all of this.

| Method & path | Auth | Purpose |
|---------------|------|---------|
| `GET /api/v1/info` | none | `ServerInfo {id, name, version, apiVersion}` |
| `POST /api/v1/pair` | none | `{code, deviceName}` → `{token, deviceID, server}`; `401 pairing_invalid`, `429 rate_limited` |
| `GET /api/v1/recordings` | bearer | All recordings, newest start first |
| `POST /api/v1/recordings` | bearer | Schedule/start one → `201`. Optional `Idempotency-Key` header: a repeat from the same device returns the original with `200` |
| `POST /api/v1/recordings/{id}/stop` | bearer | Scheduled → `cancelled`; recording → graceful stop → `completed` |
| `DELETE /api/v1/recordings/{id}` | bearer | Stop if needed, delete media and record → `204` |
| `POST /api/v1/recordings/{id}/playback` | bearer | `{url, expiresAt}`: signed HLS link valid 12 h (`409 not_playable` before the first segment) |
| `GET /api/v1/status` | bearer | Active/scheduled counts, disk space, `maxConcurrent` |
| `GET /api/v1/devices` | bearer | Paired devices |
| `DELETE /api/v1/devices/{id}` | bearer | Unpair (your own device too) → `204` |
| `GET /play/{id}/{expiry}/{sig}/{file}` | signature | `index.m3u8` / `*.ts`. Works while recording. `.ts` honours `Range` |

Create body: `{streamURL, title, channelName?, channelLogoURL?,
programmeDescription?, start, end, sourceRef?}`. Rules: http/https stream URL,
`end > start`, `end` in the future, at most 12 h. A `start` in the past starts
immediately. If that would exceed `MAX_CONCURRENT` you get `409
concurrency_limit`, and low disk gives `507 insufficient_storage`. A scheduled
recording that hits either limit at its start time becomes `failed` with that
`failureReason`.

`Recording.status` is `scheduled`, `recording`, `completed`, `failed` or
`cancelled`. Clients must tolerate unknown future values. The stream URL is
never returned by the API or written to the log.

Bearer auth: `Authorization: Bearer <token>`. Playback links carry their HMAC
in the **path** (`/play/<id>/<expiry>/<hmac>/index.m3u8`). That way the
playlist's relative segment URIs inherit the signature, and players need no
headers.

## Recording behaviour

- ffmpeg reads the source in real time (`-readrate 1`, with a 10 s initial
  burst where supported), so a "live" channel that is really a file is recorded
  at wall-clock pace rather than slurped.
- If ffmpeg exits before the end, the recorder retries with backoff from 2 s up
  to 30 s. Each attempt appends to the same playlist behind a discontinuity.
- At the end, or on stop, ffmpeg gets SIGINT (then SIGTERM/SIGKILL after 10 s).
  The playlist always ends with `#EXT-X-ENDLIST`.
- A recording that captured nothing becomes `failed` with
  `no_segments: <last ffmpeg lines>`, URLs redacted. If the source refuses to
  open five times in a row (each attempt dying within 2 s) before anything was
  captured, the recorder stops early with `source_unavailable: <last ffmpeg
  lines>`.
- On restart, running recordings resume as a new attempt. Ones that ended while
  the server was down become `completed` (if media exists) or `failed`.
  Scheduled ones whose window passed become `failed` (`missed`).
- With `SINGLE_FILE_RECORDINGS=1`, a recording still records (and plays live)
  as segments. When it finishes, the segments are concatenated into one
  `recording.ts` that any player opens directly, and `index.m3u8` is rewritten
  to address it with `#EXT-X-BYTERANGE`, so playback in Streamen is unchanged.
  The merge copies the recording once, so it needs the recording's size in
  free disk on top of `MIN_FREE_GB`. Without that space, or on any error, the
  recording keeps its segments. It only applies to recordings that finish
  while the setting is on.
- `docker stop` (SIGTERM) stops ffmpeg cleanly and keeps the rows `recording`,
  so they resume when the container is back.

## Development

```bash
swift build && swift test           # server (Swift Testing + HummingbirdTesting)
(cd Kit && swift test)              # client kit
(cd MacApp && swift build)          # macOS menu-bar app
MacApp/scripts/build-app.sh         # StreamenDVR.app + DMG in MacApp/dist/
```

`build-app.sh` bundles an LGPL ffmpeg built from the official source release
by `MacApp/scripts/build-ffmpeg.sh` (no external libraries, about 4 minutes on
first build, cached in `MacApp/.build/`). Set `FFMPEG_BINARY` to bundle another
static build. It signs ad-hoc by default. Set `SIGN_IDENTITY` (Developer ID)
and `NOTARY_PROFILE` for a build that opens on other Macs without a Gatekeeper
warning. The DMG layout comes from `MacApp/Resources/dmg-settings.py`
([dmgbuild](https://dmgbuild.readthedocs.io), installed into a venv on first
use).

### Signed Mac builds in CI

The `macOS app` job signs every push to `main` with a Developer ID
certificate. On a `v*` tag it also notarizes the app and attaches
`StreamenDVR-<version>.dmg` to the GitHub release. A release tag fails
without these repository secrets, and PRs build ad-hoc signed:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | `base64 -i cert.p12`: the "Developer ID Application" certificate *with* its private key, exported from Keychain Access |
| `MACOS_CERTIFICATE_PASSWORD` | the password set during that export |
| `NOTARY_KEY_P8_BASE64` | `base64 -i AuthKey_XXXX.p8`: an App Store Connect API key (Users and Access → Integrations, role Developer) |
| `NOTARY_KEY_ID` | that key's ID |
| `NOTARY_ISSUER_ID` | the issuer ID shown above the key list |

```bash
gh secret set MACOS_CERTIFICATE_P12_BASE64 < <(base64 -i cert.p12)
gh secret set MACOS_CERTIFICATE_PASSWORD
gh secret set NOTARY_KEY_P8_BASE64 < <(base64 -i AuthKey_XXXX.p8)
gh secret set NOTARY_KEY_ID
gh secret set NOTARY_ISSUER_ID
```

The real-ffmpeg integration test is skipped when ffmpeg isn't installed. See
`AGENTS.md` for architecture and invariants.

## License

AGPL-3.0. See [LICENSE](LICENSE).
