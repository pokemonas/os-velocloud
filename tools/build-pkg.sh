#!/bin/sh
# Build the os-velocloud package and a pkg repository from it, on Linux.
#
#   tools/build-pkg.sh <owner> [signing-key.pem]
#
#   <owner>            GitHub user/organisation; the repository is served from
#                      https://<owner>.github.io/os-velocloud (GitHub Pages)
#   signing-key.pem    RSA private key for the repository signature (optional:
#                      without it the repository is unsigned)
#
# Env: REPO_URL overrides the repository URL, REPO_ENABLED=no builds a package
# whose repository entry is disabled (local test builds), PKG the pkg binary
# (default: tools/pkg/src/pkg, built by tools/build-pkgtool.sh).
#
# Input:  plugin/ (OPNsense plugin tree), modules/<kernel commit>/{if_vcigb.ko,info}
# Output: public/freebsd15-amd64/  (meta.conf, packagesite.pkg, data.pkg, All/*.pkg)
#         public/os-velocloud.pkg    (latest package, for the first manual install)
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
OWNER=$1
KEY=$2
[ -n "$OWNER" ] || { sed -n '2,16p' "$0"; exit 1; }
[ -z "$KEY" ] || KEY=$(cd "$(dirname "$KEY")" && pwd)/$(basename "$KEY")
REPO_URL=${REPO_URL:-https://$(echo "$OWNER" | tr A-Z a-z).github.io/os-velocloud}
PKG=${PKG:-$HERE/tools/pkg/src/pkg}
ABI=FreeBSD:15:amd64
[ -x "$PKG" ] || { echo "no pkg tool at $PKG (run tools/build-pkgtool.sh)"; exit 1; }

. "$HERE/plugin/Makefile.conf"
NMOD=$(ls -d "$HERE"/modules/*/ 2>/dev/null | wc -l)
[ "$NMOD" -gt 0 ] || { echo "no modules in modules/"; exit 1; }
# revision grows with every module added, so each new kernel is an update
PKGVERSION=${PLUGIN_VERSION}_${NMOD}
PKGNAME=os-$PLUGIN_NAME

W=$HERE/work/pkg
ST=$W/stage
L=$ST/usr/local
rm -rf "$W"; mkdir -p "$L"

sub() {
	sed -e "s#%%REPO_URL%%#$REPO_URL#g" -e "s#%%OWNER%%#$OWNER#g" \
	    -e "s#%%SIGNATURE_TYPE%%#$SIGTYPE#g" -e "s#%%REPO_ENABLED%%#${REPO_ENABLED:-yes}#g" "$@"
}

if [ -n "$KEY" ]; then
	SIGTYPE=fingerprints
else
	SIGTYPE=none
	echo "WARNING: no signing key, building an unsigned repository"
fi

# ---- plugin files
( cd "$HERE/plugin/src" && find . -type f ! -path "*/__pycache__/*" ) | while read -r F; do
	F=${F#./}
	mkdir -p "$L/$(dirname "$F")"
	case "$F" in
	*.in)	sub "$HERE/plugin/src/$F" > "$L/${F%.in}"
		chmod --reference="$HERE/plugin/src/$F" "$L/${F%.in}" ;;
	*)	cp -p "$HERE/plugin/src/$F" "$L/$F" ;;
	esac
done

# ---- repository fingerprint (sha256 of the public key, as pkg(8) expects)
if [ -n "$KEY" ]; then
	mkdir -p "$L/etc/pkg/fingerprints/VeloCloud/trusted"
	FP=$(openssl rsa -in "$KEY" -pubout 2>/dev/null | sha256sum | cut -d' ' -f1)
	printf 'function: "sha256"\nfingerprint: "%s"\n' "$FP" \
	    > "$L/etc/pkg/fingerprints/VeloCloud/trusted/os-velocloud"
fi

# ---- driver modules, one directory per kernel commit
for D in "$HERE"/modules/*/; do
	C=$(basename "$D")
	mkdir -p "$L/lib/velocloud/$C"
	cp "$D/if_vcigb.ko" "$D/info" "$L/lib/velocloud/$C/"
done

# ---- OPNsense plugin version info (System: Firmware: Plugins)
mkdir -p "$L/opnsense/version"
cat > "$L/opnsense/version/$PLUGIN_NAME" <<EOF
{
    "product_abi": "26.7",
    "product_arch": "amd64",
    "product_conflicts": "",
    "product_email": "$(echo "$PLUGIN_MAINTAINER" | sub)",
    "product_hash": "$(git -C "$HERE" rev-parse --short HEAD 2>/dev/null || echo unknown)",
    "product_id": "$PKGNAME",
    "product_name": "$PLUGIN_NAME",
    "product_tier": "$PLUGIN_TIER",
    "product_version": "$PKGVERSION",
    "product_website": "$(echo "$PLUGIN_WWW" | sub)"
}
EOF

# ---- package scripts
cat > "$W/post-install" <<'EOF'
echo "os-velocloud: activating"
if grep -q '^if_vcigb_load=' /boot/loader.conf.local 2>/dev/null; then
	# a manual install; the package's loader chunk loads the driver now
	cp /boot/loader.conf.local /boot/loader.conf.local.velocloud-bak
	sed -i '' 's/^if_vcigb_load=/#if_vcigb_load=/' /boot/loader.conf.local
	echo "os-velocloud: disabled if_vcigb_load in /boot/loader.conf.local (backup: loader.conf.local.velocloud-bak)"
fi
/usr/local/opnsense/scripts/velocloud/select.sh
if [ -f /usr/local/opnsense/mvc/script/run_migrations.php ]; then /usr/local/opnsense/mvc/script/run_migrations.php OPNsense/VeloCloud; fi
if [ -f /usr/local/etc/rc.d/configd ]; then /usr/local/etc/rc.d/configd restart; fi
if [ -f /usr/local/sbin/configctl ]; then /usr/local/sbin/configctl template reload OPNsense/VeloCloud; fi
if [ -f /usr/local/etc/rc.configure_firmware ]; then /usr/local/etc/rc.configure_firmware; fi
if [ -f /usr/local/opnsense/scripts/firmware/register.php ]; then /usr/local/opnsense/scripts/firmware/register.php install os-velocloud; fi
if ! kldstat -q -m vcigb; then
	echo "os-velocloud: reboot to bring up LAN1-8, GE1 and GE2"
fi
EOF
cat > "$W/post-deinstall" <<'EOF'
rm -f /usr/local/etc/pkg/repos/VeloCloud.conf /usr/local/etc/velocloud.conf \
    /usr/local/etc/rc.loader.d/50-velocloud /var/run/velocloud.state \
    /boot/kernel/if_vcigb.ko /boot/modules/if_vcigb.ko
if [ -f /usr/local/etc/rc.d/configd ]; then /usr/local/etc/rc.d/configd restart; fi
if [ -f /usr/local/etc/rc.configure_firmware ]; then /usr/local/etc/rc.configure_firmware; fi
if [ -f /usr/local/opnsense/scripts/firmware/register.php ]; then /usr/local/opnsense/scripts/firmware/register.php remove os-velocloud; fi
echo "os-velocloud: removed; LAN1-8, GE1 and GE2 disappear at the next boot"
EOF

json() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }

# ---- manifest + plist
COMMENT=$(echo "$PLUGIN_COMMENT" | sub)
cat > "$W/+MANIFEST" <<EOF
name: "$PKGNAME"
version: "$PKGVERSION"
origin: "opnsense/$PKGNAME"
comment: "$COMMENT"
maintainer: "$(echo "$PLUGIN_MAINTAINER" | sub)"
www: "$(echo "$PLUGIN_WWW" | sub)"
prefix: "/usr/local"
abi: "$ABI"
arch: "freebsd:15:x86:64"
licenselogic: "single"
licenses: [ "BSD2CLAUSE" ]
categories: [ "sysutils" ]
desc: $(json < "$HERE/plugin/pkg-descr")
scripts: {
  post-install: $(json < "$W/post-install")
  post-deinstall: $(json < "$W/post-deinstall")
}
annotations: {
  product_tier: "$PLUGIN_TIER"
}
EOF
( cd "$ST" && find . -type f | sed 's#^\./#/#' | sort ) > "$W/plist"

# ---- package
OUT=$HERE/public
REPO=$OUT/freebsd15-amd64
mkdir -p "$REPO/All"
rm -rf "$OUT"; mkdir -p "$REPO/All"
"$PKG" -o ABI="$ABI" -o OSVERSION=1501000 create -M "$W/+MANIFEST" -p "$W/plist" -r "$ST" -o "$REPO/All"
P=$REPO/All/$PKGNAME-$PKGVERSION.pkg
[ -f "$P" ] || { echo "package not created"; exit 1; }
cp "$P" "$OUT/$PKGNAME.pkg"

# ---- repository catalogue
if [ -n "$KEY" ]; then
	"$PKG" -o ABI="$ABI" -o OSVERSION=1501000 repo "$REPO" signing_command: "$HERE/tools/sign.sh" "$KEY"
else
	"$PKG" -o ABI="$ABI" -o OSVERSION=1501000 repo "$REPO"
fi
echo "$REPO_URL" > "$OUT/REPO_URL"
echo
echo "built $PKGNAME-$PKGVERSION ($NMOD driver modules), repository: $REPO"
