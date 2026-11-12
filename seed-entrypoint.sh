#!/bin/bash
# Entrypoint for Dockerfile.seed: starts a virtual screen, a tiny window manager,
# and a browser-based remote desktop (noVNC on port 6080), then runs the script's
# manual login mode so you can log in once and seed the Chrome profile.
export DISPLAY=:99
/usr/local/bin/ensure-chrome.sh || echo "WARNING: Chrome is not installed; manual login will fail."
mkdir -p /app/cookies/chrome-profile
rm -f /app/cookies/chrome-profile/Singleton*
Xvfb :99 -screen 0 1440x900x24 &
sleep 1
fluxbox >/dev/null 2>&1 &
x11vnc -display :99 -forever -shared -nopw -rfbport 5900 -quiet &
websockify --web /usr/share/novnc 6080 localhost:5900 &
exec node /app/redeem.js --manual-login
