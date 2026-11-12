#!/bin/sh
# Installs Google Chrome from Google's own apt repository if it is not present.
# The published image does not contain Chrome, so this runs on a fresh container
# (once per container) and, as a safety net, before every scheduled run.
CHROME="${CHROME_EXECUTABLE_PATH:-/usr/bin/google-chrome-stable}"
DELAY="${CHROME_INSTALL_DELAY:-20}"
LOG=/tmp/chrome-install.log

stamp() { date '+%Y-%m-%d %H:%M:%S %Z'; }

if [ -x "$CHROME" ]; then
    exit 0
fi

export DEBIAN_FRONTEND=noninteractive
echo "[$(stamp)] Chrome not found. Installing google-chrome-stable from Google's repository (about a minute)..."

attempt=1
while [ "$attempt" -le 3 ]; do
    if apt-get update -qq >"$LOG" 2>&1 \
        && apt-get install -y --no-install-recommends google-chrome-stable >>"$LOG" 2>&1 \
        && [ -x "$CHROME" ]; then
        rm -rf /var/lib/apt/lists/*
        echo "[$(stamp)] Chrome installed: $("$CHROME" --version 2>/dev/null)"
        exit 0
    fi
    echo "[$(stamp)] Chrome install attempt $attempt of 3 failed."
    attempt=$((attempt + 1))
    [ "$attempt" -le 3 ] && sleep "$DELAY"
done

echo "[$(stamp)] ERROR: could not install Chrome. Last lines of the install log:"
tail -n 5 "$LOG"
exit 1
