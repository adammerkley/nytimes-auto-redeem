FROM node:24-slim

# Install real Google Chrome (NOT Chromium) plus Xvfb so we can run headful
# inside the container — headful real Chrome is dramatically harder for NY
# Times to detect than headless Chromium.
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    gnupg \
    ca-certificates \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libatspi2.0-0 \
    libcups2 \
    libdbus-1-3 \
    libdrm2 \
    libgbm1 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libwayland-client0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxkbcommon0 \
    libxrandr2 \
    xdg-utils \
    xvfb \
    xauth \
    dbus-x11 \
    cron \
 && wget -q -O- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
 && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google-chrome.list \
 && apt-get update && apt-get install -y --no-install-recommends google-chrome-stable \
 && rm -rf /var/lib/apt/lists/*

ENV CHROME_EXECUTABLE_PATH=/usr/bin/google-chrome-stable

WORKDIR /app

# Install the exact versions recorded in package-lock.json. `npm ci` fails if the
# lockfile and package.json disagree, and --ignore-scripts stops dependencies from
# running install-time scripts (the only one is the optional native `sleep` addon,
# which the xvfb package does not need).
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund

COPY redeem.js ./
COPY crontab /etc/cron.d/nytimes-cron

RUN chmod 0644 /etc/cron.d/nytimes-cron \
 && crontab /etc/cron.d/nytimes-cron \
 && touch /var/log/cron.log \
 && mkdir -p /app/cookies

# cron starts with a sanitized env, so dump the container env to a file the
# cron job can source before running redeem.js. Then start cron, write a startup
# line so the log window is not blank, and tail the log (last 60 lines first).
CMD printenv | grep -E '^(NYTIMES_|LIBRARY_|COOKIE_|CHROME_|USER_DATA_|TZ|LOCALE|USER_AGENT_)' \
        | sed 's/^\(.*\)$/export \1/' > /app/.env-cron \
 && cron \
 && echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] nytimes-redeem started. Next run: 06:05 daily (TZ=${TZ:-not set})" >> /var/log/cron.log \
 && tail -n 60 -f /var/log/cron.log
