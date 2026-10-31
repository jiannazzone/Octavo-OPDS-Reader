#!/bin/sh
# Downloads public-domain EPUB3s from Project Gutenberg into SampleBooks/ (gitignored).
# Skips books already present. Usage: Scripts/fetch-sample-books.sh
set -eu

dest="$(cd "$(dirname "$0")/.." && pwd)/SampleBooks"
mkdir -p "$dest"

# id:filename
books="
1342:pride-and-prejudice.epub
11:alice-in-wonderland.epub
84:frankenstein.epub
2701:moby-dick.epub
1661:sherlock-holmes.epub
"

for entry in $books; do
    id="${entry%%:*}"
    file="$dest/${entry#*:}"
    if [ -s "$file" ]; then
        echo "have  $(basename "$file")"
        continue
    fi
    echo "fetch $(basename "$file")"
    curl --fail --silent --show-error --location \
        --user-agent "Octavo-dev-fetch (+https://github.com/jiannazzone/Octavo-OPDS-Reader)" \
        --output "$file.part" "https://www.gutenberg.org/ebooks/$id.epub3.images"
    mv "$file.part" "$file"
    sleep 2 # be polite to gutenberg.org
done
