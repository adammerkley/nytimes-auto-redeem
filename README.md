# nytimes-auto-redeem (Scottsdale Public Library)

Automates redemption of the free New York Times pass that the Scottsdale Public
Library offers to cardholders. It runs a headful real Chrome browser with
anti-bot measures, logs in to the Scottsdale Public Library (Polaris) and to
NY Times automatically, and records each attempt with screenshots and history.

This is a fork of [rawhideron/nytimes-auto-redeem](https://github.com/rawhideron/nytimes-auto-redeem),
adapted for the Scottsdale Public Library and for running on Unraid. See
[NOTICE.md](NOTICE.md).

## Purpose

The goal is to redeem the time-limited library pass reliably without manual steps:

- Log in to the Scottsdale Public Library with your barcode or username and PIN.
- Log in to NY Times (email and password, with a Google SSO fallback).
- Open the library's NY Times link, which redirects to the NYT redeem page with
  the gift code in the URL.
- Detect common failure modes (bot detection, auth required, expired code).
- Click the Redeem button when available.
- Save cookies and log results to track success over time.

## How it works

- `redeem.js` is the main script. It uses `puppeteer-real-browser` with real
  Google Chrome (not bundled Chromium) running headful inside Xvfb to defeat NYT
  bot detection.
- Cookies and redemption history are stored under `cookies/` (mounted as a
  volume in Docker). The Chrome user-data-dir is also persisted there so the
  browser profile stays consistent across daily runs.
- The script does not go directly to `nytimes.com`. It follows the library's
  e-resources link, which sends the logged-in browser to NYT with the gift code
  in the URL, so the code is picked up automatically.
- A cron job inside the container runs the redemption daily at 6:05 AM in the
  container's time zone (`America/Phoenix` by default).
- The Docker image does not contain Chrome. `ensure-chrome.sh` installs Google
  Chrome from Google's repository when the container starts (usually under a
  minute, and it needs internet access), and again before each scheduled run if
  Chrome is missing.

## Functions and what they do

From `redeem.js`:

- `randomDelay(min, max)`: adds jittered pauses to appear more human.
- `humanMouseMove(page, ...)`: moves the mouse along a noisy curved path.
- `humanClick(page, el)`: scrolls into view, moves the mouse naturally, clicks.
- `humanType(el, text)`: types one character at a time with random delays, and
  can empty the field first so autofilled values are not doubled.
- `cleanStaleChromeFiles()`: removes stale Chrome port, log and lock files left
  by an earlier unclean shutdown.
- `loadHistory()`: reads `cookies/redemption-history.json` or initialises one.
- `saveHistory(history)`: persists history to disk.
- `logAttempt(success, status, codeUsed)`: records success or failure, detects
  code changes, and keeps only the last 30 attempts.
- `analyzePattern(history)`: prints a quick summary and warns on repeated failures.
- `loadCookies(page)`: loads cookies from `cookies/nytimes-cookies.json` into the
  browser session (decrypts when `COOKIE_ENCRYPTION_KEY` is set).
- `saveCookies(page)`: writes the current browser cookies to disk (encrypts when
  `COOKIE_ENCRYPTION_KEY` is set).
- `loginToLibrary(page, credentials)`: signs in to the Scottsdale Public Library
  Polaris portal.
- `loginToNyTimes(page)`: logs in to NY Times using email and password, and falls
  back to "Continue with Google" if that fails or the account is Google SSO only.
- `openNyTimesFromLibrary(page, browser)`: opens the library's NY Times link,
  handling the direct redirect first and a tile click as a fallback.
- `ensureGiftCodeFilled(page)`: fills the gift code if the page asks for it.
- `redeemSubscription()`: main flow. Launches the browser, logs in to the library
  and NYT, follows the library link, checks for failure states, clicks Redeem,
  and logs the result.
- `manualLogin()`: opens a visible Chrome with two tabs (library login and NYT
  login) so you can seed both sessions at once. Stopping it with SIGINT saves
  cookies from all relevant domains.
- `showHistory()`: prints a summary of past attempts.

## Settings

Copy `.env.example` to `.env` and fill it in. Values have no quotes.

- `NYTIMES_EMAIL`: NY Times account email for automated login.
- `NYTIMES_PASSWORD`: NY Times account password. If the account uses Google SSO
  only, the script falls back to clicking "Continue with Google" using the
  existing Chrome session.
- `LIBRARY_CARD_NUMBER`: exactly what you type in the "Barcode or Username" box.
- `LIBRARY_PIN`: library PIN or password.
- `NYTIMES_GIFT_CODE`: optional fallback gift code. Normally read from the library
  redirect, so leave it unset.

Optional overrides:

- `LIBRARY_LOGIN_URL`: defaults to
  `https://scottsdale.polarislibrary.com/polaris/logon.aspx`.
- `LIBRARY_LINK_URL`: defaults to
  `https://scottsdale.polarislibrary.com/polaris/Search/misc/esources.aspx?Target=1557`.
- `TZ`: container time zone, `America/Phoenix` by default. It decides what 6:05 AM means.
- `CHROME_EXECUTABLE_PATH`: path to a Chrome binary (set automatically in the
  Docker image to `/usr/bin/google-chrome-stable`).
- `USER_DATA_DIR`: path to the Chrome user data directory (defaults to
  `cookies/chrome-profile`).

The `.env` file must stay out of version control. It is listed in `.gitignore`.

### `COOKIE_ENCRYPTION_KEY`

Optional secret used to encrypt `cookies/nytimes-cookies.json` at rest with
AES-256-GCM. Generate a key with:

```
openssl rand -base64 32
```

Add it to `.env` and restart the container. The next cookie save rewrites the
file encrypted. The history log and the Chrome profile are not encrypted.

## Diagram (success and failure paths)

```
                 +-----------------------+
                 | cron / manual run     |
                 +-----------+-----------+
                             |
                             v
                   +-----------------+
                   | redeem.js start |
                   +--------+--------+
                            |
                            v
            +------------------------------+
            | load cookies                 |
            | library login (Polaris)      |
            | NYT login (email/pw or SSO)  |
            | open library NY Times link   |
            +--------------+---------------+
                            |
                 +----------+----------+
                 | page checks         |
                 | (bot/auth/expired)  |
                 +----+----+----+------+
                      |    |    |
     bot detected ----+    |    +---- code invalid/expired
     -> screenshot         |         -> screenshot + log FAIL
     + log FAIL            |
                           |
    auth required --------+
    -> re-login + retry
    (or log FAIL if no creds)
                           |
                           v
               +------------------------+
               | find & click Redeem    |
               +-----------+------------+
                           |
               +-----------+------------+
               | result checks          |
               +-----+---------+--------+
                     |         |
        success -----+         +---- login wall / blocked / expired
        -> save cookies              -> re-auth + retry or log FAIL
        -> log SUCCESS
```

## First-time setup (seed the Chrome profile)

Seeding gives the browser a believable history before the first automated run.
The script also logs in with your saved credentials on every run, so this mainly
helps with NYT's bot detection. Repeat it if NYT starts blocking logins.

### Option A: Linux desktop (X11 forwarding)

Run `--manual-login` once. It opens Chrome with two tabs:

```
# Allow Docker to use your host display
xhost +local:docker

docker run --rm \
  -e DISPLAY=:1 \
  -e XAUTHORITY=/tmp/.Xauthority \
  -e TZ=America/Phoenix \
  --env-file .env \
  --user "$(id -u):$(id -g)" \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v "$XAUTHORITY:/tmp/.Xauthority:ro" \
  -v "$(pwd)/cookies:/app/cookies" \
  nytimes-redeem node redeem.js --manual-login
```

- **Tab 1:** log in to the Scottsdale Public Library, then open the library's NY
  Times link and confirm it reaches the redeem page. Do not click Redeem.
- **Tab 2:** log in to your NYT account.

When both are done, press **Ctrl+C** in the terminal to save cookies and exit.

### Option B: headless server (Unraid, NAS, VPS)

There is no desktop to forward, so use the seed image, which adds a virtual
screen and a browser-based remote desktop (noVNC). Full steps are in
[docs/UNRAID.md](docs/UNRAID.md). In short:

```
docker build -f Dockerfile.seed -t nytimes-redeem-seed .
docker run -it --rm --shm-size=1g --name nyt-seed \
  --env-file .env -e TZ=America/Phoenix -p 6080:6080 \
  -v "$(pwd)/cookies:/app/cookies" nytimes-redeem-seed
```

Open `http://<host>:6080/vnc.html`, do both logins, then save from a second
terminal with `docker kill --signal=INT nyt-seed`. Do not press Ctrl+C in the run
terminal, because that also shuts down the virtual screen before cookies are written.

## Run with Docker

You can build the image yourself (below) or use the prebuilt one. GitHub builds
and publishes it to `ghcr.io/adammerkley/nytimes-auto-redeem:latest` on every
push to `main` (see `.github/workflows/docker-publish.yml`). To use it, skip the
build step and put that image name at the end of the `docker run` command in place
of `nytimes-redeem`.

```
# Build the image
docker build -t nytimes-redeem .

# Start the container (runs cron at 6:05 AM Phoenix time daily)
docker run -d \
  --name nytimes-redeem \
  --restart unless-stopped \
  --shm-size=1g \
  -e TZ=America/Phoenix \
  --env-file .env \
  -v "$(pwd)/cookies:/app/cookies" \
  nytimes-redeem

# Watch cron logs
docker logs -f nytimes-redeem

# Run a manual test (mirrors exactly what cron does)
docker exec nytimes-redeem bash -c \
  '. /app/.env-cron && xvfb-run -a --server-args="-screen 0 1440x900x24" node /app/redeem.js'

# Show redemption history
docker exec nytimes-redeem bash -c \
  '. /app/.env-cron && node /app/redeem.js --history'

# Stop / restart
docker stop nytimes-redeem
docker restart nytimes-redeem

# Update .env credentials and restart
docker restart nytimes-redeem
```

> **Note:** `docker-compose` v1 (the system package on some distros) has a known
> incompatibility with newer Docker daemons. Use the `docker` commands above directly.

## Unraid

An Unraid template is in [unraid/my-nytimes-redeem.xml](unraid/my-nytimes-redeem.xml).
The full guide, including the seed procedure, operation, and troubleshooting, is
[docs/UNRAID.md](docs/UNRAID.md). The template pulls the prebuilt image, so the
Docker tab can show "update ready" after each push to `main`.

## Run locally (optional)

```
npm install
NYTIMES_EMAIL=... NYTIMES_PASSWORD=... \
LIBRARY_CARD_NUMBER=... LIBRARY_PIN=... \
node redeem.js
```

## Files at a glance

- `redeem.js`: main automation script and all helper functions.
- `Dockerfile`: Node 24-slim + Xvfb + cron. Real Google Chrome is installed from Google's repository when the container starts (`ensure-chrome.sh`).
- `ensure-chrome.sh`: installs Google Chrome when it is missing (container start and before each run).
- `.github/workflows/`: `ci.yml` checks the script syntax, `docker-publish.yml` publishes the image to ghcr.io.
- `NOTICE.md`: credit to the upstream project and a list of changes.
- `Dockerfile.seed`, `seed-entrypoint.sh`: seed image with a virtual desktop and noVNC.
- `docker-compose.yml`: reference compose config (use the `docker` CLI directly if compose v1 is broken).
- `crontab`: daily schedule, fires `redeem.js` at 06:05 container time via `xvfb-run`.
- `update-code.sh`: helper to update `NYTIMES_GIFT_CODE` in `.env`.
- `.env.example`: template for the settings file.
- `unraid/`: Unraid Docker template.
- `docs/UNRAID.md`: Unraid guide.
- `cookies/`: persisted cookies, Chrome profile, logs, and screenshots (gitignored).

## Security notes

- `.env` holds your library PIN and NYT password in plain text. Keep it out of
  version control and set its permissions to `600`.
- Chrome may save your logins in the profile under `cookies/chrome-profile`.
  Treat the whole `cookies/` folder as private.
- Chrome runs with `--no-sandbox` as root inside the container, because that is
  the usual Docker setup. The container is not privileged and mounts only `cookies/`.
- The script is built to look like a normal visitor to NYT's bot detection. Check
  that automated access is acceptable under NYT's and the library's terms for your use.
