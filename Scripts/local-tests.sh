#!/bin/bash
# The tests that guard main, on this Mac (docs/notes/ci.md). GitHub runs only
# `swift test`, so a pull request can't merge until this has passed on its
# last commit and posted the "Local tests" status there.
#
# Usage: Scripts/local-tests.sh ["simulator name"]    (default: iPhone Duo)
#
# Run it once the work is committed and up to date with main. If the commit
# isn't on GitHub yet, run it again after pushing: it remembers the pass and
# only posts the status.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

simulator=${1:-iPhone Duo}
sha=$(git rev-parse HEAD)
passed=$(git rev-parse --git-path octavo-local-tests-passed)

# A new file builds here whether or not it's committed, so nothing may be left out.
if [ -n "$(git status --porcelain)" ]; then
    echo "Commit or remove these first:" >&2
    git status --short >&2
    exit 1
fi

git fetch --quiet origin main
if ! git merge-base --is-ancestor origin/main HEAD; then
    echo "This branch is behind main. Update it first." >&2
    exit 1
fi

# Prints a run's result, or what failed and where the whole log is.
run() {
    local log
    log=$(mktemp -t octavo-local-tests)
    if ! "$@" > "$log" 2>&1; then
        grep -E '✘|error:' "$log" | tail -40 >&2 || true
        echo "Failed. Whole log: $log" >&2
        exit 1
    fi
    grep -E 'Test run with' "$log" | tail -1 || true
    rm -f "$log"
}

# The same paths as `ci.yml`. No changed files at all still runs the tests.
files=$(git diff --no-renames --name-only origin/main...HEAD)
if ! grep -qvE '^(docs/|README\.md$|CLAUDE\.md$)' <<< "$files"; then
    echo "Only docs changed, so there's nothing to test."
elif [ "$(cat "$passed" 2> /dev/null)" = "$sha" ]; then
    echo "$sha has already passed here."
else
    (cd Packages/OctavoKit && run swift test)
    # One test at a time: in parallel, a busy Mac fails tests with short limits.
    run xcodebuild test -project Octavo.xcodeproj -scheme Octavo \
        -destination "platform=iOS Simulator,name=$simulator,OS=27.1" \
        -parallel-testing-enabled NO -collect-test-diagnostics never
    echo "$sha" > "$passed"
fi

if ! gh api --silent "repos/{owner}/{repo}/commits/$sha" 2> /dev/null; then
    echo "Passed. Push $sha, then run this again to mark it on GitHub."
    exit 0
fi
gh api --silent "repos/{owner}/{repo}/statuses/$sha" \
    -f state=success -f context="Local tests" -f description="Passed on this Mac"
echo "Marked $sha as passed on GitHub."
