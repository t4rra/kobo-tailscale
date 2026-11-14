# kobo-tailscale

Install script for getting [Tailscale](https://tailscale.com) running on Kobo e-readers and persisting through reboots.

A single installer handles every supported device. It detects the CPU
architecture, installs the latest stable Tailscale build, and only uses the
bundled TUN kernel module on models whose kernel needs it.

## Supported devices

- *Kobo Libra 2*
- *Kobo Libra Colour* / *Kobo Elipsa 2e*
- *Kobo Clara BW*

## Installation

1. Download this repo onto your Kobo e-reader's onboard storage.
2. Run `./install-tailscale.sh` from the repo directory (as root — that's the
   default shell on a Kobo). The device needs working internet access, since the
   installer downloads Tailscale.
3. Run `tailscale up` and follow the instructions to authenticate your e-reader.

The installer downloads the newest stable build at install time, so there is
nothing to bump by hand.

### Updates

The boot scripts also check for a newer build whenever Wi-Fi comes up and
install it in the background. If the binaries change, `tailscaled` is
restarted so the new version takes effect. `/tailscale-update.log` contains
the result of the last check.

Tailscale's built-in auto-updater is not used, because it cannot handle this
install layout (the binaries live on the onboard storage and there is no
systemd or init script to restart the daemon).

### Choosing a version

By default the latest stable release is installed. To pin a version — for
example to roll back after an upgrade — set `TAILSCALE_VERSION`:

```sh
TAILSCALE_VERSION=1.72.1 ./install-tailscale.sh
```

A pinned install is marked with `/mnt/onboard/tailscale/pinned-version` and the
Wi-Fi update check skips it. Re-run the installer without `TAILSCALE_VERSION`
to unpin.

To track the unstable channel instead:

```sh
TAILSCALE_CHANNEL=unstable ./install-tailscale.sh
```

Every Kobo uses the same ARM build — there is no per-device version. If a future
release turns out not to work on an older device (the Libra 2 runs an older
kernel than the rest), pin the last known-good version and open an issue.

## Uninstallation

Run `./uninstall-tailscale.sh`. This stops the daemon and removes the binaries,
scripts, udev rule, iptables files, and the Tailscale state directory in
`/mnt/onboard/tailscale` (which contains your node identity).

## How it works

- **Tailscale binaries** are installed to `/mnt/onboard/tailscale` and symlinked
  into `/usr/bin`, so they survive firmware updates that reset the root
  filesystem.
- **Boot scripts** in `/usr/local/tailscale` are started by a udev rule when the
  internal storage mounts, and bring the daemon up/down with Wi-Fi.
- **TUN**: Tailscale needs the TUN/TAP driver. Most current Kobo kernels include
  it. The Libra 2 does not, so this repo ships a pre-built `tun.ko` (built from
  the [Libra 2 kernel source](https://github.com/kobolabs/Kobo-Reader/tree/master/hw/imx6sll-libra2)
  following the [kobo-kernel-modules](https://github.com/jmacindoe/kobo-kernel-modules/tree/main/Kobo%20Mark%209%20-%20Libra%202)
  instructions). The installer always copies it; the boot script only loads it
  when the kernel hasn't already provided TUN, and a mismatched module is
  rejected safely by the kernel.
- **iptables** is not included in stock Kobo images, so pre-built binaries and
  shared libraries are bundled in `binaries/iptables`. They come from the
  [July 5th 2017 build of Raspbian](http://downloads.raspberrypi.org/raspbian/images/raspbian-2017-07-05),
  which also bundles the source code, matching the glibc used by Kobo firmware.

## DNS issues

When there's no DNS manager on a system, Tailscale will resort to just
[overwriting resolv.conf](https://tailscale.com/kb/1235/resolv-conf/), which can
cause issues on Kobo devices. If you find that DNS breaks after a while you can
fix this by running `tailscale set --accept-dns=false` on your device to prevent
it from overwriting resolv.conf.

## Acknowledgements

[Dylan Staley for initial work and scripts on the Kobo Sage](https://dstaley.com/posts/tailscale-on-kobo-sage)

[jmacindoe for documenting kernel module compilation on Kobo readers](https://github.com/jmacindoe/kobo-kernel-modules)
