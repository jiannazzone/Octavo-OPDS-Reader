---
name: octavo-prepare-update
description: Prepare an Octavo release and sync its App Store Connect text. Reviews what merged, bumps the version, writes the changelog, and fetches, compares or publishes the listing with the API key. Use when Adam says "prepare for update", "prep the next release", or asks to fetch, diff or publish the App Store listing. Never uploads a build or submits for review.
---

# octavo-prepare-update

Each step stops for Adam's explicit OK. All public wording is his to approve, and plain (see the `ui-wording-plain` memory).

## Hard limits

Never do these, even if asked in passing. Hand Adam the steps instead.

- Upload or attach a build, submit for review, or release.
- Create an App Store version, or change price, age rating, privacy answers or screenshots.
- Change the bundle ID.
- Print, save or commit the API key. It stays in 1Password, and the client reads it through `op`.
- `git push` or `gh pr create` without Adam's OK for that push.
- Run `publish --confirm` without his go-ahead for that diff.

## The client

```bash
asc() { python3 .claude/skills/octavo-prepare-update/scripts/asc_client.py "$@"; }
asc check             # Apple's limits on the repo's files. No network.
asc status            # versions in App Store Connect, and the repo's version
asc fetch             # what App Store Connect has now
asc diff              # the fields that differ
asc publish           # prints the diff, sends nothing
asc publish --confirm # sends it, then re-fetches to confirm
```

Define `asc` in the same Bash call that uses it. Say a 1Password prompt may appear before the first call that needs the network, because it takes focus. Later calls within 20 minutes use the cached token.

Needs `op`, `pyjwt[crypto]` and `requests`. A 401 usually means the key's role is too narrow, or a cached token is stale: `rm ~/.cache/octavo-asc-client/session.json`.

## The files

- `docs/app-store/listing.json`: the listing text, copyright and App Review notes. The repo is the source: change text here, then publish.
- `docs/app-store/changelog.json`: `[{"version": "1.1", "notes": "..."}]`, newest first, plain text. It feeds What's New.
- `Config/Versions.xcconfig`: the version and build number, the only place they're set.

## Syncing the listing only

Run `asc diff`. If App Store Connect has text the repo doesn't, someone edited it there: show Adam, and ask which to keep before changing anything. Then `asc publish`, his go-ahead, and `asc publish --confirm`.

## A release

1. **Review changes.** List the pull requests merged since the last tag (`git log <tag>..origin/main --merges`; before the first tag, everything). Show which ones a reader would notice, and let Adam confirm.
2. **Bump.** Propose the version and the next build number. A new build number is needed for every upload. Edit `Config/Versions.xcconfig` after his OK.
3. **Changelog.** Draft the entry in plain wording, with no jargon or pull request numbers, and show it to him. Add it to the top of `changelog.json`, then run `asc check`. Apple doesn't take What's New on the first version, so the client leaves it out until a version is live.
4. **Commit** the bump and changelog on a branch. Ask before pushing. `docs/` alone needs no tests, but `Config/` does, so run `Scripts/local-tests.sh` first.
5. **Publish the text.** `asc status`. If the new version isn't in App Store Connect, stop and ask Adam to add it. Otherwise follow "Syncing the listing only".
6. **Hand over.** Give Adam the steps: Xcode > Product > Archive, then Distribute App, attach the build to the version, check any new prompts, and submit.
7. **Tag.** Once Apple approves it, and with his OK to push, tag the merge commit `v<version>`.
