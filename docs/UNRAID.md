# Running on Unraid

**Container name:** `nytimes-redeem`
**Suggested host folder:** `/mnt/user/appdata/nytimes-redeem`

## 1. What this does

Every day at 6:05 AM (container time zone, `America/Phoenix`) the container:

1. Opens a real, headful Google Chrome inside a virtual display (Xvfb).
2. Logs in to the Scottsdale Public Library (Polaris) with your barcode or username and PIN.
3. Logs in to the New York Times account with email and password.
4. Opens the library's e-resources link, which redirects to the NYT redeem page with the gift code in the URL.
5. Clicks **Redeem**, saves cookies, and records the attempt in a history file.

The library pass lasts about 72 hours. Redeeming again while a pass is active has been tested and caused no problems.

## 2. Files and locations

| Item | Location |
|---|---|
| Project folder | `/mnt/user/appdata/nytimes-redeem` |
| Settings file (secrets) | `.env` in the project folder (keep permissions at `600`) |
| Persistent data (mounted into the container) | `cookies/` -> `/app/cookies` |
| Chrome profile | `cookies/chrome-profile/` |
| Saved cookies | `cookies/nytimes-cookies.json` |
| Attempt history (last 30) | `cookies/redemption-history.json` |
| Failure screenshots | `cookies/*.png`, for example `library-no-nytimes.png`, `library-login-result.png`, `bot-detected.png` |
| Unraid template | `unraid/my-nytimes-redeem.xml` |
| Seed image files | `Dockerfile.seed`, `seed-entrypoint.sh` |

From a PC on your network the project folder is at `\\<unraid-ip>\appdata\nytimes-redeem\`.

## 3. Install

```
cd /mnt/user/appdata
git clone https://github.com/adammerkley/nytimes-auto-redeem nytimes-redeem
cd nytimes-redeem
mkdir -p cookies
cp .env.example .env
chmod 600 .env
nano .env
docker build -t nytimes-redeem .
```

Fill in the four credential lines in `.env`. Values have no quotes.

## 4. Settings

| Variable | Purpose |
|---|---|
| `LIBRARY_LOGIN_URL` | Defaults to `https://scottsdale.polarislibrary.com/polaris/logon.aspx` |
| `LIBRARY_LINK_URL` | Defaults to `https://scottsdale.polarislibrary.com/polaris/Search/misc/esources.aspx?Target=1557` |
| `LIBRARY_CARD_NUMBER` | Exactly what you type in "Barcode or Username" |
| `LIBRARY_PIN` | Library PIN or password |
| `NYTIMES_EMAIL` | NYT account email |
| `NYTIMES_PASSWORD` | NYT account password |
| `TZ` | `America/Phoenix`. Decides what 6:05 AM means |
| `COOKIE_ENCRYPTION_KEY` | Optional. `openssl rand -base64 32`. Encrypts the cookie file |
| `NYTIMES_GIFT_CODE` | Optional fallback only. Normally read from the redirect, so leave it unset |

After changing `.env`, run `docker restart nytimes-redeem`.

## 5. Seed the Chrome profile

The script logs in with your saved credentials on every run, so seeding mostly helps with NYT's bot detection. It is how you give the browser a believable history before the first automated run. Repeat it if NYT starts blocking logins.

Unraid has no desktop to forward, so use the seed image, which shows Chrome in a browser tab through noVNC.

1. Build the seed image (the main image must exist first):
   ```
   docker build -f Dockerfile.seed -t nytimes-redeem-seed .
   ```
2. If the main container is running, stop it so it does not use the profile at the same time: `docker stop nytimes-redeem`
3. Run the seed container and leave that terminal open:
   ```
   docker run -it --rm --shm-size=1g --name nyt-seed \
     --env-file .env -e TZ=America/Phoenix -p 6080:6080 \
     -v /mnt/user/appdata/nytimes-redeem/cookies:/app/cookies \
     nytimes-redeem-seed
   ```
4. Wait for the "Manual Login Mode" banner and about 30 more seconds, then open `http://<unraid-ip>:6080/vnc.html` and click Connect. Chrome shows two tabs.
5. **Tab 1:** log in to the library, then open the `LIBRARY_LINK_URL` link and confirm it lands on the NYT redeem page. Do not click Redeem. **Tab 2:** log in to NYT and tick "remember me" if offered.
6. Save from a **second** terminal: `docker kill --signal=INT nyt-seed`. Do not press Ctrl+C in the first terminal, because that also shuts down the virtual screen before the script can save.
7. Start the main container again: `docker start nytimes-redeem`

The noVNC page has no password. Keep it running only for the few minutes you need it, and only on your LAN.

## 6. Run it

```
docker run -d --name nytimes-redeem --restart unless-stopped \
  --shm-size=1g \
  -e TZ=America/Phoenix \
  --env-file .env \
  -v /mnt/user/appdata/nytimes-redeem/cookies:/app/cookies \
  nytimes-redeem
```

`--shm-size=1g` matters because Chrome needs shared memory. The `--restart unless-stopped` policy brings the container back after a reboot once the array and Docker service are up. If you stop it with `docker stop`, it stays stopped until you start it again.

### Unraid template (optional)

1. Copy `unraid/my-nytimes-redeem.xml` to `/boot/config/plugins/dockerMan/templates-user/`.
2. `docker rm -f nytimes-redeem`
3. Docker tab, **Add Container**, choose `nytimes-redeem` under User templates.
4. Fill in the four credential fields, click **Apply**, and turn **Autostart** on.

The Docker tab may show "not available" under updates. That is normal for a locally built image. After you rebuild the image, open the container's Edit page and click Apply to recreate it from the new image.

## 7. Daily operation

| Task | Command |
|---|---|
| Recent log output | `docker logs --tail 50 nytimes-redeem` |
| Manual test now (redeems if a pass is available) | `docker exec nytimes-redeem bash -c '. /app/.env-cron && xvfb-run -a --server-args="-screen 0 1440x900x24" node /app/redeem.js' 2>&1 \| tail -40` |
| Attempt history | `docker exec nytimes-redeem bash -c '. /app/.env-cron && node /app/redeem.js --history'` |
| Restart | `docker restart nytimes-redeem` |
| Confirm restart policy | `docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' nytimes-redeem` (should print `unless-stopped`) |

A healthy run looks like this:

```
Logging in to Scottsdale Public Library...
Logging in to NY Times...
NY Times login successful (email/password)
Library link redirected straight to NY Times
Extracted gift code from NY Times URL
Clicking redeem button...
Redemption successful!
```

### Messages that look wrong but are not

- **"Could not find library login button":** cosmetic. The Enter key submits the form before the script looks for the button, and the login does work.
- **"WARNING: Multiple failures":** counts failures among the last 10 attempts. Old failures roll out as new successes accumulate.
- **"Current code age":** refers to the gift code in the library link, not your pass.
- **dbus, machine-id, WebGL or GPU cache errors in raw Chrome logs:** normal inside Docker.

## 8. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Error: connect ECONNREFUSED 127.0.0.1:<port>` right after "Starting redemption" | A stale `chrome-err.log` held the port of an old, killed Chrome | Already handled by `cleanStaleChromeFiles()`. Manual workaround: delete `cookies/chrome-profile/chrome-err.log`, `DevToolsActivePort`, `chrome.pid` and `Singleton*`, then restart the container |
| Library login page says "The system was unable to log you on" and the username appears twice | Chrome autofill plus typed text | Already handled: the fields are emptied before typing. Also check `LIBRARY_CARD_NUMBER` and `LIBRARY_PIN` for quotes or typos |
| "Could not find NY Times link on the library site" | Library login did not happen, or the link did not redirect | Open `cookies/library-no-nytimes.png` and `cookies/library-login-result.png` to see what the browser saw. Check `LIBRARY_LINK_URL` |
| NYT shows a robot check or login page | Session or bot detection | Open `cookies/bot-detected.png` or `login-required.png`, then repeat the seed procedure |
| Seed container exits on Ctrl+C and nothing is saved | Ctrl+C stops every process in the container, including the screen | Use `docker kill --signal=INT nyt-seed` from a second terminal |
| Nothing happens at 6:05 AM | Container stopped, or wrong time zone | `docker ps`, check `TZ`, then read `docker logs` |
| The `docker exec` test seems to hang | Output is piped to `tail`, which waits until the run finishes | Wait up to about 4 minutes, since the script adds human-like delays |
| Chrome processes left behind after a crash | Orphaned processes hold the profile | `docker restart nytimes-redeem` |

## 9. Security notes

- `.env` holds the library PIN and NYT password in plain text. Keep it `chmod 600` and out of version control.
- If the Unraid template is used, the same values are stored in the template on the flash drive.
- Chrome may save your logins in the profile folder. Treat the whole `cookies/` folder as private, and keep the `appdata` share private on your network.
- `COOKIE_ENCRYPTION_KEY` encrypts the saved cookie file. The Chrome profile folder is not encrypted.
- The seed step exposes a desktop with no password on port 6080. Run it briefly, on a trusted LAN only.
- Failure screenshots can show account pages. Do not share them without checking.
- Chrome runs with `--no-sandbox` as root inside the container. The container is not privileged and mounts only `cookies/`. You can add `--security-opt no-new-privileges` as an extra parameter for more hardening, though it has not been tested with this image.
