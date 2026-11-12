# Notice

This project is a fork of
[rawhideron/nytimes-auto-redeem](https://github.com/rawhideron/nytimes-auto-redeem)
by rawhideron (Ron Goodman). The original design, the `redeem.js` automation, and
most of the code are theirs.

The upstream repository declares the MIT license in its `package.json`
(`"license": "MIT"`) but does not include a `LICENSE` file or name a copyright
holder. Changes made in this fork are offered under the same MIT terms. If the
upstream author adds a `LICENSE` file, copy it here and keep its copyright notice.

## What this fork changes

- Targets the Scottsdale Public Library (Polaris) and its login and e-resources pages.
- Handles the Polaris e-resources link, which redirects straight to the NYT redeem
  page with the gift code in the URL.
- Fixes `ECONNREFUSED` after an unclean Chrome shutdown by clearing stale
  `chrome-err.log`, `DevToolsActivePort`, `chrome.pid` and `Singleton*` files
  before every launch.
- Fixes a false "already logged in" result on the Polaris login page, and clears
  autofilled library login fields before typing.
- Fixes an intermittent `Execution context was destroyed` error during library login by
  waiting for the login navigation and retrying on transient page errors.
- Adds a seed image with a virtual desktop and noVNC for headless hosts, an Unraid
  template, and an Unraid guide.
- Installs dependencies from `package-lock.json` with `npm ci --ignore-scripts`, and
  writes a startup line to the container log.
- Publishes the image to the GitHub Container Registry on every push to `main`. The
  image does not contain Chrome: `ensure-chrome.sh` installs it from Google's
  repository when the container starts.
- Quotes the settings that cron reads, so passwords containing characters such as
  `&`, `;`, `$` or a space work in the scheduled run.
- Defaults the time zone to `America/Phoenix` and renames the library settings
  (`LIBRARY_LINK_URL` replaces the old home-page setting).

The upstream investigation note about the original library site was removed
because it does not apply here.
