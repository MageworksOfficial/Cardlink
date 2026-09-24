#!/bin/sh
set -eu
# Certbot sets RENEWED_LINEAGE. Restrict this hook to the selected certificate.
expected=$(cat /etc/cardlink/certificate-lineage)
[ "${RENEWED_LINEAGE:-}" = "$expected" ] || exit 0
install -o root -g cardlink -m 0640 "$RENEWED_LINEAGE/fullchain.pem" /etc/cardlink/tls/fullchain.pem.new
install -o root -g cardlink -m 0640 "$RENEWED_LINEAGE/privkey.pem" /etc/cardlink/tls/privkey.pem.new
mv /etc/cardlink/tls/fullchain.pem.new /etc/cardlink/tls/fullchain.pem
mv /etc/cardlink/tls/privkey.pem.new /etc/cardlink/tls/privkey.pem
systemctl reload cardlink
