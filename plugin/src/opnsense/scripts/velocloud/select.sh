#!/bin/sh

# os-velocloud: put the right if_vcigb.ko where the loader finds it.
#
# The driver must be loaded by the loader (the built-in igb would claim the
# I354 otherwise), and the loader looks in module_path = /boot/kernel;/boot/modules:
#
#   /boot/kernel/if_vcigb.ko   module built for the kernel installed in
#                              /boot/kernel; disappears with a kernel update
#   /boot/modules/if_vcigb.ko  fallback: the newest module of the package,
#                              used when /boot/kernel has none (attaches on a
#                              foreign kernel only with hw.vcigb.strict=0)
#
# The target kernel is read from /boot/kernel/kernel, not "uname -v", so this
# is also right between a kernel update and the reboot.
# Writes /var/run/velocloud.state.  -q: no output unless something changed.

MODDIR=/usr/local/lib/velocloud
STATE=/var/run/velocloud.state
QUIET=
[ "$1" = "-q" ] && QUIET=1

say() {
	echo "velocloud: $*"
	logger -t velocloud "$*"
}

commit_of() {	# kernel or module file -> 12-hex kernel commit
	strings -a -n 16 "$1" 2>/dev/null |
	    sed -n 's/^FreeBSD [0-9].*-\([0-9a-f]\{12\}\) .*/\1/p' | head -n 1
}

install_file() {	# src dst
	if ! cmp -s "$1" "$2"; then
		cp "$1" "$2.velocloud.tmp" && mv "$2.velocloud.tmp" "$2"
		CHANGED=1
	fi
}

KCOMMIT=$(commit_of /boot/kernel/kernel)
if [ -z "${KCOMMIT}" ]; then
	KCOMMIT=$(uname -v | sed -n 's/.*-\([0-9a-f]\{12\}\) .*/\1/p')
fi
CHANGED=

# 1. exact module next to the kernel
if [ -n "${KCOMMIT}" ] && [ -f ${MODDIR}/${KCOMMIT}/if_vcigb.ko ]; then
	install_file ${MODDIR}/${KCOMMIT}/if_vcigb.ko /boot/kernel/if_vcigb.ko
	EXACT=${KCOMMIT}
elif [ -f /boot/kernel/if_vcigb.ko ]; then
	# left over from an older package for another kernel
	rm -f /boot/kernel/if_vcigb.ko
	CHANGED=1
	EXACT=
fi

# 2. fallback: newest module ("ref" = OPNsense version it was built for)
NEWEST=$(for I in ${MODDIR}/*/info; do
	[ -f "${I}" ] || continue
	echo "$(sed -n 's/^ref=//p' "${I}") $(basename "$(dirname "${I}")")"
done | sort -V | tail -n 1 | awk '{print $2}')
if [ -n "${NEWEST}" ]; then
	install_file ${MODDIR}/${NEWEST}/if_vcigb.ko /boot/modules/if_vcigb.ko
fi

cat > ${STATE} <<EOF
kernel=${KCOMMIT}
exact=${EXACT}
fallback=${NEWEST}
EOF

if [ -n "${CHANGED}" ] || [ -z "${QUIET}" ]; then
	if [ -n "${EXACT}" ]; then
		say "module for kernel ${KCOMMIT} installed in /boot/kernel"
	else
		say "no module for kernel ${KCOMMIT:-unknown} yet; fallback ${NEWEST:-none} in /boot/modules"
	fi
fi

exit 0
