#!/bin/sh
# Two self-signed certificates for the "Trust this server" tests: `a` is
# the one you trust, `b` stands in for the server's certificate changing.
set -eu
cd "$(dirname "$0")"
mkdir -p certs
for name in a b; do
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
    -keyout "certs/$name.key" -out "certs/$name.crt" -days 3650 \
    -subj "/CN=Octavo trust test $name" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" 2>/dev/null
  printf '%s  ' "$name"; openssl x509 -in "certs/$name.crt" -noout -fingerprint -sha256
done
