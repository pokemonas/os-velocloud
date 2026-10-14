#!/bin/sh
# Build if_vcigb.ko (VeloCloud Edge 520/540 I354 ports) for an OPNsense release,
# on Linux (Debian/Ubuntu/Mint), cross-compiling with the FreeBSD build system.
#
#   ./build-vcigb.sh <opnsense-ref> [series] [kernconf]
#
#   <opnsense-ref>  OPNsense src tag ("26.7", "26.7.1", ...) or the commit hash
#                   that "uname -v" prints on the box
#                   (e.g. "stable/26.7-n283674-12334a596709" -> 12334a596709)
#   [series]        "26.7" etc.; only needed when <ref> is a hash and the series
#                   cannot be guessed (selects the OPNsense kernel config)
#   [kernconf]      the box's own kernel config: on OPNsense run
#                     sysctl -n kern.conftxt > kernconf.txt
#                   and pass that file - then the module is built with exactly the
#                   options of the running kernel (recommended)
#
# Result: out/<ref>/vcigb-opnsense-<ref>.tar.xz (module + loader.conf.local + README)
# Time: ~10-30 min the first time per release (FreeBSD toolchain), ~1 min after.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REF=$1
SERIES=$2
KCONF=$3
[ -z "$KCONF" ] || KCONF=$(cd "$(dirname "$KCONF")" && pwd)/$(basename "$KCONF")
[ -z "$KCONF" ] || [ -r "$KCONF" ] || { echo "cannot read $KCONF"; exit 1; }
[ -n "$REF" ] || { sed -n '2,15p' "$0"; exit 1; }

# ---- host tools
LLVM_BIN=""
for v in 21 20 19 18 17; do
	[ -x /usr/lib/llvm-$v/bin/clang ] && [ -x /usr/lib/llvm-$v/bin/ld.lld ] && { LLVM_BIN=/usr/lib/llvm-$v/bin; break; }
done
missing=""
[ -n "$LLVM_BIN" ] || missing="$missing clang lld llvm"
for p in git python3 libarchive-dev libbz2-dev zlib1g-dev time xz-utils; do
	dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"
done
[ -z "$missing" ] || { echo "install first: sudo apt install$missing"; exit 1; }

SRC_URL=https://github.com/opnsense/src.git
TOOLS_URL=https://github.com/opnsense/tools.git
W=$HERE/work/$REF
mkdir -p "$W"
cd "$W"

# ---- resolve the ref to a commit
if [ ! -d src/.git ]; then
	echo "== resolving $REF"
	SHA=$(git ls-remote --tags "$SRC_URL" "refs/tags/$REF^{}" | awk '{print $1}')
	[ -n "$SHA" ] || SHA=$(git ls-remote --tags "$SRC_URL" "refs/tags/$REF" | awk '{print $1}')
	if [ -z "$SHA" ]; then
		SHA=$(git ls-remote "$SRC_URL" | awk -v p="$REF" 'index($1, p) == 1 {print $1; exit}')
	fi
	[ -n "$SHA" ] || { echo "no tag or commit '$REF' in opnsense/src"; exit 1; }
	echo "   commit $SHA"
	git init -q src
	git -C src fetch -q --depth 1 "$SRC_URL" "$SHA"
	git -C src checkout -q FETCH_HEAD
fi
S=$W/src

# ---- kernel config: the box's own (kern.conftxt) or OPNsense SMP from opnsense/tools
if [ -n "$KCONF" ]; then
	cp "$KCONF" "$S/sys/amd64/conf/SMP"
	echo "== kernel config: $KCONF (from the box)"
else
	if [ ! -d tools/.git ]; then
		# same tag as the kernel when opnsense/tools has it, else its master
		git clone -q --depth 1 --branch "$REF" "$TOOLS_URL" tools 2>/dev/null ||
		    git clone -q --depth 1 "$TOOLS_URL" tools
	fi
	[ -n "$SERIES" ] || SERIES=$(echo "$REF" | grep -oE '^[0-9]+\.[0-9]+' || true)
	[ -n "$SERIES" ] || SERIES=$(ls tools/config | grep -E '^[0-9]+\.[0-9]+$' | sort -V | tail -1)
	[ -f "tools/config/$SERIES/SMP" ] || { echo "no tools/config/$SERIES/SMP"; exit 1; }
	grep -v '%%DEBUG%%' "tools/config/$SERIES/SMP" > "$S/sys/amd64/conf/SMP"
	echo "== kernel config: opnsense/tools $(git -C tools describe --tags --always 2>/dev/null) config/$SERIES/SMP"
fi

# ---- driver: copy of sys/dev/e1000 + VeloCloud patch
if [ ! -d "$S/sys/dev/vcigb" ]; then
	echo "== applying vcigb patch"
	cp -r "$S/sys/dev/e1000" "$S/sys/dev/vcigb"
	( cd "$S/sys/dev/vcigb" && patch -p2 --no-backup-if-mismatch < "$HERE/patches/vcigb-vs-e1000.diff" ) || {
		echo "the vcigb patch no longer applies to this release's e1000 driver"
		rm -rf "$S/sys/dev/vcigb"; exit 1; }
	mkdir -p "$S/sys/modules/vcigb"
	cp "$HERE/patches/module.Makefile" "$S/sys/modules/vcigb/Makefile"
fi

NOTOOLS="WITHOUT_CLANG_BOOTSTRAP=yes WITHOUT_LLD_BOOTSTRAP=yes WITHOUT_LLVM_TARGET_ALL=yes WITHOUT_CLANG=yes WITHOUT_LLD=yes WITHOUT_LLDB=yes"
OBJ=$W/obj
mkdir -p "$OBJ"
J=$(nproc)

# ---- FreeBSD cross toolchain (once per release)
# bmake's self-test of signal handling (cmd-interrupt) fails depending on how
# the shell was started (nohup, CI runners); it says nothing about the build
UT=$S/contrib/bmake/unit-tests/Makefile
if [ -f "$UT" ] && ! grep -q '^BROKEN_TESTS+= cmd-interrupt deptgt-interrupt' "$UT"; then
	awk '/^\.if .*BROKEN_TESTS/ && !d { print "BROKEN_TESTS+= cmd-interrupt deptgt-interrupt"; d=1 } { print }' \
	    "$UT" > "$UT.vc" && mv "$UT.vc" "$UT"
fi
if [ ! -f "$W/.toolchain-done" ]; then
	echo "== building the FreeBSD toolchain with $J jobs (10-30 min), log: $W/toolchain.log"
	( cd "$S" && MAKEOBJDIRPREFIX=$OBJ python3 tools/build/make.py --cross-bindir="$LLVM_BIN" \
	    TARGET=amd64 TARGET_ARCH=amd64 -j"$J" kernel-toolchain $NOTOOLS ) > "$W/toolchain.log" 2>&1 || {
		tail -20 "$W/toolchain.log"; exit 1; }
	touch "$W/.toolchain-done"
fi

# ---- kernel option headers + module, inside the FreeBSD build environment
KCOMMIT=$(git -C "$S" rev-parse --short=12 HEAD)
cat > "$W/inner.sh" <<EOF
#!/bin/sh
set -e
rm -rf "$W/kern" "$W/modobj"; mkdir -p "$W/kern"
cd "$S/sys/amd64/conf"
config -d "$W/kern" SMP
cd "$S/sys/modules/vcigb"
M="make -m $S/share/mk SRCTOP=$S SYSDIR=$S/sys MK_SSP=no KERNBUILDDIR=$W/kern MAKEOBJDIRPREFIX=$W/modobj VCIGB_KERNCOMMIT=$KCOMMIT"
\$M obj
\$M all
EOF
chmod +x "$W/inner.sh"
echo "== building if_vcigb.ko, log: $W/module.log"
( cd "$S" && MAKEOBJDIRPREFIX=$OBJ python3 tools/build/make.py --cross-bindir="$LLVM_BIN" \
    TARGET=amd64 TARGET_ARCH=amd64 buildenv BUILDENV_SHELL="$W/inner.sh" $NOTOOLS ) > "$W/module.log" 2>&1 || {
	grep -E 'error:' "$W/module.log" | head; tail -5 "$W/module.log"; exit 1; }

KO=$(find "$W/modobj" -name if_vcigb.ko -type f | head -1)
[ -n "$KO" ] || { echo "module not built"; exit 1; }
# the FreeBSD kernel linker cannot relocate GOT references
if "$LLVM_BIN/llvm-readelf" -r "$KO" | grep -q GOTPCREL; then
	echo "module has GOT relocations, it would not load"; exit 1
fi

if ! strings "$KO" | grep -q "^$KCOMMIT\$"; then
	echo "kernel commit $KCOMMIT not compiled into the module"; exit 1
fi

# ---- package
KREV=$(sed -n 's/^REVISION="\(.*\)"/\1/p; s/^BRANCH="\(.*\)"/\1/p' "$S/sys/conf/newvers.sh" | paste -sd- -)
# for os-velocloud: out/modules/<kernel commit>/if_vcigb.ko + info
MD=$HERE/out/modules/$KCOMMIT
rm -rf "$MD"; mkdir -p "$MD"
cp "$KO" "$MD/"
printf 'commit=%s\nfreebsd=%s\nref=%s\n' "$KCOMMIT" "$KREV" "$REF" > "$MD/info"

OUT=$HERE/out/$REF/vcigb-opnsense
rm -rf "$OUT"; mkdir -p "$OUT"
cp "$KO" "$OUT/"
cp "$HERE/patches/loader.conf.local" "$OUT/"
cat > "$OUT/README.txt" <<EOF
if_vcigb for OPNsense $REF (FreeBSD $KREV, opnsense/src $KCOMMIT)
The module attaches only on the kernel whose "uname -v" ends in $KCOMMIT.

Install (OPNsense shell, option 8):
  cp if_vcigb.ko /boot/modules/
  grep -q if_vcigb_load /boot/loader.conf.local || cat loader.conf.local >> /boot/loader.conf.local
  reboot
Check: dmesg | grep vcigb ; ifconfig -l   (vcigb0..vcigb3)
Undo:  remove the if_vcigb_load line from /boot/loader.conf.local
EOF
tar cJf "$HERE/out/$REF/vcigb-opnsense-$REF.tar.xz" -C "$HERE/out/$REF" vcigb-opnsense
echo
echo "done: $HERE/out/$REF/vcigb-opnsense-$REF.tar.xz"
