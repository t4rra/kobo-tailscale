#!/bin/sh

# Load the TUN driver. Most Kobo kernels include it, but some (e.g. Libra 2)
# need the module installed by install-tailscale.sh. On kernels where it is
# built in, insmod fails harmlessly and is ignored.
if ! grep -q '^tun ' /proc/modules 2>/dev/null; then
  insmod /lib/modules/tailscale/kernel/drivers/net/tun.ko 2>/dev/null || true
fi

# Make sure the TUN device node exists.
if [ ! -c /dev/net/tun ]; then
  mkdir -p /dev/net
  mknod /dev/net/tun c 10 200 2>/dev/null || true
fi

if [ ! -c /dev/net/tun ]; then
  echo "tun device is unavailable; not starting tailscaled" >&2
  exit 1
fi

# Make absolutely sure that iptables is in the PATH
export PATH=/usr/sbin:/usr/bin:$PATH

# Make sure /mnt/onboard is mounted
if ! timeout 5 sh -c 'while ! grep -q /mnt/onboard /proc/mounts; do sleep 0.1; done'; then
  echo "/mnt/onboard is not mounted; not starting tailscaled" >&2
  exit 1
fi

if [ -z "$(pidof tailscaled)" ]; then
  tailscaled --statedir=/mnt/onboard/tailscale >/tailscaled.log 2>&1 &
fi

exit 0
