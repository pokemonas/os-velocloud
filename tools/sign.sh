#!/bin/sh
# pkg repo signing_command: reads the checksum on stdin, prints signature + public key
# (the "fingerprints" signature type, as used by the OPNsense repositories).
KEY=$1
read -r SUM
[ -n "$SUM" ] || exit 1
echo SIGNATURE
printf '%s' "$SUM" | openssl dgst -sign "$KEY" -sha256 -binary
echo
echo CERT
openssl rsa -in "$KEY" -pubout 2>/dev/null
echo END
