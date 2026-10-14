vcigb-build - if_vcigb.ko (VeloCloud Edge 520/540 I354 ports) for any OPNsense release

On a Debian/Ubuntu/Mint machine (e.g. melynas):
  sudo apt install clang lld llvm git python3 libarchive-dev libbz2-dev zlib1g-dev time xz-utils

Recommended (exact match with the running kernel), after upgrading OPNsense:
  ssh root@192.168.2.1 'uname -v'                         # -> stable/26.7-n283674-12334a596709
  ssh root@192.168.2.1 'sysctl -n kern.conftxt' > kernconf.txt
  ./build-vcigb.sh 12334a596709 26.7 kernconf.txt         # commit + series + the box's config

Shorter forms:
  ./build-vcigb.sh 26.7.1                  # OPNsense src tag, config from opnsense/tools at that tag
  ./build-vcigb.sh 12334a596709 26.7       # commit + series, config from opnsense/tools

Why both: the module must be compiled from the same source commit (uname -v) and with
the same kernel options (kern.conftxt) as the running kernel; then structures match 1:1.

Result: out/<ref>/vcigb-opnsense-<ref>.tar.xz -> copy to the box, see its README.txt
Time:   first run per release 10-30 min (FreeBSD toolchain), then ~1 min. ~6 GB disk.

Important: after an OPNsense upgrade that changes the kernel, the old if_vcigb.ko may not
load (kldload refuses it, nothing breaks; SFP ports with igb keep working). Rebuild and
copy the new module, reboot. Keep a cable/SFP for management during upgrades.

patches/vcigb-vs-e1000.diff   changes vs sys/dev/e1000 (applied to a copy, sys/dev/vcigb)
patches/module.Makefile       sys/modules/vcigb/Makefile (MK_SSP=no is passed by the script)
patches/loader.conf.local     module autoload + COM2 serial console

If "the vcigb patch no longer applies": e1000 changed in that release; the diff
must be adapted by hand (the logic is in e1000_vc.c, the hooks are small).

Runs fine in the background or in CI: the bmake self-tests that depend on signal
handling (cmd-interrupt, deptgt-interrupt) are skipped by the script.
