#!/bin/sh

set -e

# Installs the latest stable Tailscale build by default.
#
# Pin a specific version (e.g. to roll back) with:
#   TAILSCALE_VERSION=1.72.1 ./install-tailscale.sh
#
# Track a different channel (stable or unstable) with:
#   TAILSCALE_CHANNEL=unstable ./install-tailscale.sh
TAILSCALE_VERSION="${TAILSCALE_VERSION:-}"
TAILSCALE_CHANNEL="${TAILSCALE_CHANNEL:-stable}"

if [ "$(id -u)" -ne 0 ]; then
  echo "This installer must be run as root." >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
WORK_DIR="$SCRIPT_DIR/.install-tmp"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

case "$(uname -m)" in
  armv6l|armv7l|arm) ARCH="arm" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)
    echo "Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

echo
echo "Installing Tailscale on this Kobo ($(uname -m)) ..."
uname -a
echo

echo "Installing iptables into /sbin and /lib ..."
cp "$SCRIPT_DIR"/binaries/iptables/sbin/* /sbin/
cp "$SCRIPT_DIR"/binaries/iptables/lib/* /lib/

ln -sf /sbin/xtables-multi /sbin/iptables
ln -sf /lib/libxtables.so.10.0.0 /lib/libxtables.so.10
ln -sf /lib/libip4tc.so.0.1.0 /lib/libip4tc.so.0
ln -sf /lib/libip6tc.so.0.1.0 /lib/libip6tc.so.0

# Some Kobo models (e.g. Libra 2) don't ship the TUN driver in the kernel, so
# we install the module here. on-boot.sh only loads it when the kernel needs
# it; on other models the module is simply never used.
if [ -f "$SCRIPT_DIR/modules/tun.ko" ]; then
  echo "Installing TUN kernel module into /lib/modules/tailscale ..."
  mkdir -p /lib/modules/tailscale/kernel/drivers/net
  cp "$SCRIPT_DIR/modules/tun.ko" /lib/modules/tailscale/kernel/drivers/net/tun.ko
fi

if [ -n "$TAILSCALE_VERSION" ]; then
  URL="https://pkgs.tailscale.com/$TAILSCALE_CHANNEL/tailscale_${TAILSCALE_VERSION}_${ARCH}.tgz"
else
  echo "Looking up the latest Tailscale version ..."
  TARBALL=$(wget -qO- "https://pkgs.tailscale.com/$TAILSCALE_CHANNEL/?mode=json" \
    | grep -o "\"$ARCH\": \"tailscale_[^\"]*\"" \
    | head -n 1 \
    | sed 's/.*"\(tailscale_[^"]*\)"/\1/') || TARBALL=""

  if [ -n "$TARBALL" ]; then
    URL="https://pkgs.tailscale.com/$TAILSCALE_CHANNEL/$TARBALL"
  else
    # Fall back to the redirecting "latest" tarball if the JSON lookup failed.
    URL="https://pkgs.tailscale.com/$TAILSCALE_CHANNEL/tailscale_latest_${ARCH}.tgz"
  fi
fi

echo "Downloading $URL ..."
mkdir -p "$WORK_DIR"
wget -O "$WORK_DIR/tailscale.tgz" "$URL"
tar -xzf "$WORK_DIR/tailscale.tgz" -C "$WORK_DIR"

set -- "$WORK_DIR"/tailscale_*/
PKG_DIR="$1"
if [ ! -d "$PKG_DIR" ]; then
  echo "Failed to extract the Tailscale tarball." >&2
  exit 1
fi

VERSION=$(basename "$PKG_DIR")
VERSION="${VERSION#tailscale_}"
VERSION="${VERSION%_$ARCH}"
echo "Downloaded Tailscale $VERSION."

pids=$(pidof tailscaled) || true
if [ -n "$pids" ]; then
  echo "Stopping running tailscaled (PID(s): $pids) ..."
  # Word splitting is intentional: pidof may return more than one PID.
  kill -15 $pids 2>/dev/null || true
  sleep 2
fi

echo "Installing tailscale binaries into /mnt/onboard/tailscale and symlinking them into /usr/bin ..."
mkdir -p /mnt/onboard/tailscale
cp "$PKG_DIR"/tailscale "$PKG_DIR"/tailscaled /mnt/onboard/tailscale/
chmod +x /mnt/onboard/tailscale/tailscale /mnt/onboard/tailscale/tailscaled

# Record a pinned install so the on-Wi-Fi update check leaves it alone. A
# plain install clears the marker, which re-enables automatic updates.
if [ -n "$TAILSCALE_VERSION" ]; then
  echo "$VERSION" > /mnt/onboard/tailscale/pinned-version
else
  rm -f /mnt/onboard/tailscale/pinned-version
fi

ln -sf /mnt/onboard/tailscale/tailscale /usr/bin/tailscale
ln -sf /mnt/onboard/tailscale/tailscaled /usr/bin/tailscaled

echo "Installing tailscale boot and load scripts into /usr/local/tailscale ..."
mkdir -p /usr/local/tailscale
cp "$SCRIPT_DIR"/scripts/* /usr/local/tailscale/
chmod +x /usr/local/tailscale/*.sh

echo "Installing tailscale udev rule into /etc/udev/rules.d ..."
mkdir -p /etc/udev/rules.d
cp "$SCRIPT_DIR"/rules/* /etc/udev/rules.d/

echo
echo "Installation complete! Attempting to boot tailscale daemon ..."
/usr/local/tailscale/boot.sh
echo

echo "Tailscale $VERSION is installed."
echo "You can now configure it by running 'tailscale up' and following the instructions."
echo "The tailscale binaries are located in /mnt/onboard/tailscale."
echo
