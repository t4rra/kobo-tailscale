#!/bin/sh

# Checks for a newer Tailscale build and installs it. Called in the background
# from on-wlan-up.sh.
#
# Tailscale's built-in auto-updater cannot be used on this install: it only
# recognizes /usr/bin/tailscaled (the binaries live on /mnt/onboard and are
# symlinked from /usr/bin), and it cannot restart tailscaled because there is
# no systemd unit or init script. So run `tailscale update` ourselves and
# restart the daemon through on-boot.sh afterwards.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

STATE_DIR=/mnt/onboard/tailscale
LOCK_DIR=/tmp/tailscale-update.lock

# The binaries and state live on /mnt/onboard. If this event beats the mount,
# wait briefly (same as on-boot.sh) and let the next connect try again.
if ! timeout 5 sh -c 'while ! grep -q /mnt/onboard /proc/mounts; do sleep 0.1; done'; then
  echo "/mnt/onboard is not mounted; skipping Tailscale update check"
  exit 0
fi

# A pinned install (TAILSCALE_VERSION=... at install time) must not move.
if [ -f "$STATE_DIR/pinned-version" ]; then
  echo "tailscale is pinned to $(cat "$STATE_DIR/pinned-version"); not updating"
  exit 0
fi

# Only one update at a time. Recover a lock left behind by a killed run.
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  old=$(cat "$LOCK_DIR/pid" 2>/dev/null)
  if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
    exit 0
  fi
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" 2>/dev/null || exit 0
fi
echo $$ >"$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR"' EXIT INT TERM

# Clean up half-written binaries from an interrupted update; tailscale update
# refuses to start if a .new file is left over.
rm -f "$STATE_DIR"/tailscale.new "$STATE_DIR"/tailscaled.new

# The wlan interface appears before DHCP has finished, so wait for the
# network to actually be usable. Give up after a minute; the next Wi-Fi
# connect will try again.
i=0
while [ "$i" -lt 30 ]; do
  wget -q -O /dev/null "https://pkgs.tailscale.com/stable/?mode=json" && break
  i=$((i + 1))
  sleep 2
done
if [ "$i" -ge 30 ]; then
  echo "network is not up; skipping Tailscale update check"
  exit 0
fi

before=$(tailscale version | head -n 1)

# --yes skips the prompt. This is a no-op when the installed build is current.
if ! tailscale update --yes; then
  echo "tailscale update failed"
  exit 1
fi

after=$(tailscale version | head -n 1)
if [ -z "$after" ] || [ "$before" = "$after" ]; then
  echo "tailscale $after is up to date"
  exit 0
fi

echo "updated tailscale $before -> $after; restarting tailscaled"

# tailscale update replaced the binaries but cannot restart the daemon on a
# Kobo (no systemd unit or init script), so restart it through the boot script.
pids=$(pidof tailscaled) || true
if [ -n "$pids" ]; then
  # Word splitting is intentional: pidof may return more than one PID.
  kill -15 $pids 2>/dev/null || true
  i=0
  while [ -n "$(pidof tailscaled)" ] && [ "$i" -lt 20 ]; do
    i=$((i + 1))
    sleep 0.5
  done
fi
if [ -n "$(pidof tailscaled)" ]; then
  echo "tailscaled did not stop; the new version will be used after its next restart"
  exit 0
fi
/usr/local/tailscale/on-boot.sh
