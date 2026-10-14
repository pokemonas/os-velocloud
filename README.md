# os-velocloud

OPNsense plugin for the **VeloCloud Edge 520/540**: brings up LAN1–8, GE1 and GE2
(the Intel I354 ports behind two Marvell 88E6176 switches and two 88E1514 PHYs)
with the `if_vcigb` driver, and adds **Interfaces: VeloCloud Edge** to the GUI.

| Jacks      | Interface | Notes                                   |
|------------|-----------|-----------------------------------------|
| LAN5–8     | vcigb0    | 88E6176 switch A, unmanaged             |
| LAN1–4     | vcigb1    | 88E6176 switch B, unmanaged             |
| GE1        | vcigb2    | 88E1514 PHY 0                           |
| GE2        | vcigb3    | 88E1514 PHY 1                           |
| SFP1, SFP2 | igb0, igb1| I350, stock FreeBSD driver              |

## What the plugin does

* Carries one `if_vcigb.ko` per OPNsense kernel (`modules/<kernel commit>/`).
  The commit is the hash at the end of `uname -v`.
* Puts the module for the installed kernel in `/boot/kernel/if_vcigb.ko` and the
  newest one in `/boot/modules/if_vcigb.ko`. The loader loads the first one it
  finds (`if_vcigb_load="YES"` from `/usr/local/etc/rc.loader.d/50-velocloud`).
  A kernel update removes the copy in `/boot/kernel`, so the next boot uses the
  newest module from `/boot/modules`, and the early boot hook then installs the
  exact one if the package has it.
* Each module refuses to attach on a kernel it was not built for unless
  `hw.vcigb.strict=0` (set by the *Fallback module* option, on by default).
* GUI page: per-jack link status read from the switch registers
  (`dev.vcigb.N.vc_ports`), driver/kernel match, next-boot module, settings
  (load driver, fallback, serial console on the micro-USB port = COM2).
* Dashboard widget with the port tiles.
* Installs its own signed package repository, so new modules (new OPNsense
  kernels) arrive as normal **System: Firmware** updates.

## Install on the box (first time)

From the OPNsense shell (option 8):

```
fetch -o /tmp/os-velocloud.pkg https://OWNER.github.io/os-velocloud/os-velocloud.pkg
pkg add /tmp/os-velocloud.pkg
reboot
```

After that, os-velocloud is listed under System: Firmware: Plugins as
installed, and updates come from the VeloCloud repository.

If you installed the module by hand before (`if_vcigb_load` in
`/boot/loader.conf.local`), the package comments that line out (backup in
`loader.conf.local.velocloud-bak`) and takes over.

## Before an OPNsense update with a new kernel

The repository is checked daily; when OPNsense tags a new release, GitHub
Actions builds the module for its kernel and publishes a new os-velocloud.
Firmware updates install packages first and the kernel last, so when the new
module is already published everything is in place before the reboot.
If it is not yet, the box boots with the newest module (fallback), which so far
has worked across minor updates; update os-velocloud later and reboot once.
Keep SFP1 or the serial console for management during updates.

## Repository layout

```
plugin/      OPNsense plugin tree (src/ = files under /usr/local)
modules/     if_vcigb.ko + info per kernel commit (built by CI or by hand)
kit/         build-vcigb.sh: builds if_vcigb.ko for an opnsense/src tag on Linux
tools/       build-pkg.sh (package + repository), missing-kernels.sh, sign.sh
series       OPNsense series to follow (e.g. 26.7)
.github/     daily workflow: build missing modules, package, publish to Pages
```

## Setup of the GitHub repository (once)

1. Create a public repository `os-velocloud` and push this tree to `main`.
2. Signing key, kept only as a secret:
   ```
   openssl genrsa -out repo.key 4096
   ```
   Repository *Settings → Secrets and variables → Actions → New secret*:
   `REPO_SIGNING_KEY` = contents of `repo.key`. Keep `repo.key` offline as a
   backup; the fingerprint inside the package is derived from it, so a new key
   means users have to reinstall os-velocloud by hand.
3. *Settings → Pages → Source: GitHub Actions*.
4. *Actions → build → Run workflow*. The first run builds the package from the
   modules already in `modules/` and publishes
   `https://OWNER.github.io/os-velocloud/`.

To follow the next series (e.g. 27.1), add it to `series`.

## Building by hand

```
tools/build-pkgtool.sh                              # FreeBSD pkg(8) for Linux, once
kit/build-vcigb.sh 26.7.7 26.7                      # module for a tag
cp -r kit/out/modules/* modules/
tools/build-pkg.sh OWNER repo.key                   # -> public/
```

`kit/build-vcigb.sh <commit> <series> kernconf.txt` builds for the exact
kernel of a box: `uname -v` gives the commit, `sysctl -n kern.conftxt` the
kernel configuration.

## Credits

Register sequences and wiring from
[velo540openwrt](https://github.com/gallops-gannets/velo540openwrt); the driver
is a copy of FreeBSD's e1000/igb driver from
[opnsense/src](https://github.com/opnsense/src).
