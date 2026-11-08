#!/bin/bash
# The KOReader round trip (docs/notes/koreader-sync.md): KOReader's release
# build, headless in a throwaway Linux container (container.sh), against the
# sample books, with places built here by xpointer_check.py.
#
# Usage: run.sh <SampleBooks dir> <work dir>
# Leaves `octavo-koreader-check` running for another pass;
# `docker rm -f octavo-koreader-check` when done.
set -euo pipefail
books=$(cd "$1" && pwd)
work=$(mkdir -p "$2" && cd "$2" && pwd)
tools=$(cd "$(dirname "$0")" && pwd)
source "$tools/container.sh"
ensure_koreader "$books" "$work"
mkdir -p "$work/places"

for epub in "$books"/*.epub; do
    b=$(basename "$epub" .epub)
    python3 -I "$tools/xpointer_check.py" make "$epub" "$work/places/$b.tsv"
    koreader_places "$b"
done

for epub in "$books"/*.epub; do
    b=$(basename "$epub" .epub)
    echo "=== $b"
    python3 -I "$tools/xpointer_check.py" check "$epub" "$work/out/$b-ko.tsv"
    python3 -I "$tools/xpointer_check.py" compare "$work/places/$b.tsv" "$work/out/$b-landed.tsv"
done
