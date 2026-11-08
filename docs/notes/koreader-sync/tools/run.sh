#!/bin/bash
# The KOReader round trip (docs/notes/koreader-sync.md): KOReader's release
# build, headless, in a throwaway Linux container, against the sample books.
#
# Usage: run.sh <SampleBooks dir> <work dir>
# Leaves the container `octavo-koreader-check` running for another pass;
# `docker rm -f octavo-koreader-check` when done.
set -euo pipefail
books=$(cd "$1" && pwd)
work=$(mkdir -p "$2" && cd "$2" && pwd)
tools=$(cd "$(dirname "$0")" && pwd)
version=v2026.07.1
mkdir -p "$work/places"

if ! docker ps --format '{{.Names}}' | grep -qx octavo-koreader-check; then
    docker run -d --name octavo-koreader-check --platform linux/arm64 \
        -v "$books:/books:ro" -v "$tools:/tools:ro" -v "$work/places:/places:ro" \
        debian:bookworm-slim sleep 86400 > /dev/null
    docker exec octavo-koreader-check sh -c "apt-get update -qq > /dev/null && \
        apt-get install -y -qq xz-utils curl ca-certificates libsdl2-2.0-0 > /dev/null && mkdir -p /opt/ko && cd /opt/ko && \
        curl -sSL -o k.tar.xz https://github.com/koreader/koreader/releases/download/$version/koreader-linux-arm64-$version.tar.xz && \
        tar xJf k.tar.xz && rm k.tar.xz"
fi

for epub in "$books"/*.epub; do
    b=$(basename "$epub" .epub)
    python3 -I "$tools/xpointer_check.py" make "$epub" "$work/places/$b.tsv"
    docker exec octavo-koreader-check sh -c "mkdir -p /tmp/out && cd /opt/ko/lib/koreader && \
        HOME=/tmp ./luajit /tools/places.lua /books/$b.epub /tmp/out/$b /places/$b.tsv > /dev/null 2>&1"
done
rm -rf "$work/out"
docker cp octavo-koreader-check:/tmp/out "$work/out" > /dev/null

for epub in "$books"/*.epub; do
    b=$(basename "$epub" .epub)
    echo "=== $b"
    python3 -I "$tools/xpointer_check.py" check "$epub" "$work/out/$b-ko.tsv"
    python3 -I "$tools/xpointer_check.py" compare "$work/places/$b.tsv" "$work/out/$b-landed.tsv"
done
