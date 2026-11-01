#!/bin/sh
# Downloads public-domain books from Project Gutenberg into SampleBooks/ (gitignored).
# Skips files already present. Usage: Scripts/fetch-sample-books.sh
#
# For each book: the EPUB3, and Gutenberg's two Kindle files for the formats
# spike (docs/notes/formats-spike.md): "Kindle" (KF8) saved as .azw3 and
# "older Kindle" (MOBI 6) saved as .mobi. dev/bookorbit/seed.sh uploads only
# SampleBooks/*.epub, so none of the formats spike's files reach that server.
#
# FB2 has no trustworthy public-domain source (Gutenberg and Standard Ebooks
# don't publish it), so if calibre is installed, each EPUB is also converted
# to FB2 with calibre's ebook-convert, as a calibre-based OPDS server would.
# calibre (GPL) only runs here as a tool; nothing of it is in the repo.
# Treat every file in SampleBooks/ as untrusted.
set -eu

dest="$(cd "$(dirname "$0")/.." && pwd)/SampleBooks"
mkdir -p "$dest"

# id:name. The first five are the spike's EPUB set (dev/bookorbit/seed.sh).
books="
1342:pride-and-prejudice
11:alice-in-wonderland
84:frankenstein
2701:moby-dick
1661:sherlock-holmes
"
# Only in Kindle/FB2 form: uploaded to BookOrbit for the formats round trip,
# titles that aren't in the seeded EPUB set.
format_books="
120:treasure-island
35:the-time-machine
"

fetch() { # url file
    if [ -s "$2" ]; then
        echo "have  $(basename "$2")"
        return
    fi
    echo "fetch $(basename "$2")"
    curl --fail --silent --show-error --location \
        --user-agent "Octavo-dev-fetch (+https://github.com/jiannazzone/Octavo-OPDS-Reader)" \
        --output "$2.part" "$1"
    mv "$2.part" "$2"
    sleep 2 # be polite to gutenberg.org
}

kindle() { # id name
    fetch "https://www.gutenberg.org/ebooks/$1.kf8.images" "$dest/$2.azw3"
    fetch "https://www.gutenberg.org/ebooks/$1.kindle.images" "$dest/$2.mobi"
}
for entry in $books; do
    fetch "https://www.gutenberg.org/ebooks/${entry%%:*}.epub3.images" "$dest/${entry#*:}.epub"
    kindle "${entry%%:*}" "${entry#*:}"
done
# Their EPUBs only feed the FB2 conversion, so they stay out of seed.sh's way.
mkdir -p "$dest/formats-src"
for entry in $format_books; do
    fetch "https://www.gutenberg.org/ebooks/${entry%%:*}.epub3.images" "$dest/formats-src/${entry#*:}.epub"
    kindle "${entry%%:*}" "${entry#*:}"
done

convert="${EBOOK_CONVERT:-$(command -v ebook-convert || echo /Applications/calibre.app/Contents/MacOS/ebook-convert)}"
if [ ! -x "$convert" ]; then
    echo "calibre's ebook-convert not found: skipping FB2 (set EBOOK_CONVERT to its path)"
    exit 0
fi
for epub in "$dest"/*.epub "$dest"/formats-src/*.epub; do
    [ -e "$epub" ] || continue
    fb2="$dest/$(basename "$epub" .epub).fb2"
    if [ -s "$fb2" ]; then
        echo "have  $(basename "$fb2")"
        continue
    fi
    echo "make  $(basename "$fb2")"
    "$convert" "$epub" "$fb2.part.fb2" >/dev/null
    mv "$fb2.part.fb2" "$fb2"
done
