#!/bin/sh

tailscale up

# Check for a newer Tailscale build in the background. Detach it the same way
# boot.sh does, otherwise udev kills it when the wlan event finishes.
env -i -- setsid /usr/local/tailscale/update-tailscale.sh >/tailscale-update.log 2>&1 &
