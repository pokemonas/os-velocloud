#!/bin/sh
# List OPNsense src tags of the series in ./series whose kernel commit has no
# module in modules/ yet:  "<tag> <commit12>" per line, oldest first.
#   --newer   only tags newer than the newest module already in modules/
set -e
NEWER=$1
HERE=$(cd "$(dirname "$0")/.." && pwd)
SRC_URL=https://github.com/opnsense/src.git
git ls-remote --tags "$SRC_URL" | awk '{print $2, $1}' | sed 's#^refs/tags/##' |
    awk '{ if ($1 ~ /\^\{\}$/) { sub(/\^\{\}$/, "", $1); peeled[$1] = $2 } else plain[$1] = $2 }
	END { for (t in plain) print t, (t in peeled ? peeled[t] : plain[t]) }' |
while read -r TAG SHA; do
	while read -r S; do
		[ -n "$S" ] || continue
		if echo "$TAG" | grep -Eq "^$(echo "$S" | sed 's/\./\\./g')(\.[0-9]+)?(_[0-9]+)?\$"; then
			C=$(echo "$SHA" | cut -c1-12)
			[ -d "$HERE/modules/$C" ] || echo "$TAG $C"
		fi
	done < "$HERE/series"
done | sort -V | awk '!seen[$2]++' | {
	if [ "$NEWER" = "--newer" ]; then
		LAST=$(cat "$HERE"/modules/*/info 2>/dev/null | sed -n 's/^ref=//p' | sort -V | tail -n 1)
		while read -r TAG C; do
			[ -z "$LAST" ] || [ "$(printf '%s\n%s\n' "$LAST" "$TAG" | sort -V | tail -n 1)" != "$LAST" ] &&
			    echo "$TAG $C"
		done
	else
		cat
	fi
}
