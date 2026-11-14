#!/bin/sh

if [ "$(id -u)" -ne 0 ]; then
  echo "This uninstaller must be run as root." >&2
  exit 1
fi

echo "Uninstalling Tailscale ..."

pids=$(pidof tailscaled) || true
if [ -n "$pids" ]; then
  echo "Terminating tailscale daemon with PID(s): $pids ..."
  # Word splitting is intentional: pidof may return more than one PID.
  kill -15 $pids 2>/dev/null || true

  # Wait a little bit for the daemon to terminate cleanly.
  sleep 3

  echo "Tailscale daemon terminated."
fi

echo "Removing TUN kernel module from /lib/modules/tailscale ..."
rm -rf /lib/modules/tailscale

echo "Removing iptables binaries from /sbin and /lib ..."
rm -f /sbin/xtables-multi /sbin/iptables
rm -f /lib/libxtables.so.10 /lib/libip4tc.so.0 /lib/libip6tc.so.0
rm -f /lib/libxtables.so.10.0.0 /lib/libip4tc.so.0.1.0 /lib/libip6tc.so.0.1.0

echo "Removing tailscale binaries and state from /mnt/onboard/tailscale ..."
rm -rf /mnt/onboard/tailscale
rm -f /usr/bin/tailscale /usr/bin/tailscaled

echo "Removing tailscale boot and load scripts from /usr/local/tailscale ..."
rm -rf /usr/local/tailscale

echo "Removing tailscale udev rule from /etc/udev/rules.d ..."
rm -f /etc/udev/rules.d/98-tailscale.rules

echo "Removing tailscale logs ..."
rm -f /tailscaled.log /tailscale-update.log

echo "Uninstallation complete!"
