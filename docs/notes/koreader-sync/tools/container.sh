# Sourced by run.sh and bridge-check.sh: KOReader's release build in a
# throwaway Linux container, `octavo-koreader-check`, with the books at
# /books, these tools at /tools and the work folder at /work. A container
# made for other folders is made again, so a run never reads another's files.
KOREADER_VERSION=v2026.07.1

ensure_koreader() {
    local books=$1 work=$2 tools
    tools=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    local mounts
    mounts=$(docker inspect -f '{{range .Mounts}}{{.Destination}}={{.Source}};{{end}}' octavo-koreader-check 2>/dev/null || true)
    if [[ -n "$mounts" && "$mounts" != *"/books=$books;"* || -n "$mounts" && "$mounts" != *"/work=$work;"* ]]; then
        docker rm -f octavo-koreader-check > /dev/null
        mounts=
    fi
    if [[ -z "$mounts" ]]; then
        docker run -d --name octavo-koreader-check --platform linux/arm64 \
            -v "$books:/books:ro" -v "$tools:/tools:ro" -v "$work:/work" \
            debian:bookworm-slim sleep 86400 > /dev/null
    fi
    docker start octavo-koreader-check > /dev/null
    docker exec octavo-koreader-check sh -c "[ -x /opt/ko/lib/koreader/luajit ] || { apt-get update -qq > /dev/null && \
        apt-get install -y -qq xz-utils curl ca-certificates libsdl2-2.0-0 > /dev/null && mkdir -p /opt/ko && cd /opt/ko && \
        curl -sSL -o k.tar.xz https://github.com/koreader/koreader/releases/download/$KOREADER_VERSION/koreader-linux-arm64-$KOREADER_VERSION.tar.xz && \
        tar xJf k.tar.xz && rm k.tar.xz; }"
}

# `places.lua` on one book: KOReader's own places to <work>/out/<book>-ko.tsv
# and, given <work>/places/<book>.tsv, where those land.
koreader_places() {
    local book=$1
    docker exec octavo-koreader-check sh -c "mkdir -p /work/out && cd /opt/ko/lib/koreader && \
        HOME=/tmp ./luajit /tools/places.lua /books/$book.epub /work/out/$book /work/places/$book.tsv > /dev/null 2>&1"
}
