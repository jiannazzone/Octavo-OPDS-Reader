# CI

`.github/workflows/ci.yml` runs on every pull request and every push to `main` (#19).

| Job | Runner | What it does |
|---|---|---|
| Changes | `ubuntu-latest` | Decides whether tests are needed |
| OctavoKit tests | `xcode-27` | `swift test` |
| App tests | `xcode-27` | `xcodebuild` on an iPhone Duo, iOS 27.1 |
| CI passed | `ubuntu-latest` | Fails unless the jobs that had to run passed. The one check for "Protect main" to require |

## Runner

GitHub's `xcode-27` image lists Xcode 27.2, an iOS 27.1 runtime and the iPhone Duo device type, so no self-hosted runner is needed for these jobs. The image is still a preview, so it may queue or change. It lists no Docker, so the checks that need `dev/bookorbit`, `dev/opds` or `dev/trust` aren't part of this workflow, and those live tests skip themselves when their environment variables aren't set.

The repo is public, so these standard runners should cost nothing. Pull requests from first-time and other outside contributors wait for approval, because the repo's setting is `all_external_contributors`.

## Docs-only changes

Pull requests and pushes to `main` use the same check, which compares the commit with its first parent. Tests are skipped only when every changed file is under `docs/`, or is the root `README.md` or `CLAUDE.md`. These are exact paths, not "all Markdown", because a test reads `THIRD-PARTY-NOTICES.md`. Anything else runs the tests, and so does a commit that changes no files. Moving a file counts as changing both paths, so moving code into `docs/` runs them too.

## Build cache

The App tests job turns on Xcode's compilation cache with `COMPILATION_CACHE_ENABLE_CACHING=YES`, in the workflow only, so local builds are unchanged. It keeps only `CompilationCache.noindex`, not the rest of DerivedData. Its entries are keyed by the compiler's input, not by file dates, so a fresh checkout still hits the cache and a stale result can't be reused the way it can with DerivedData.

- Only pushes to `main` that run the tests save the cache, so a docs-only merge doesn't. A pull request restores it but never writes it, so the first build after the cache is empty is a full one.
- The key holds the Xcode build and the month, so a new Xcode or a new month starts a fresh cache. Otherwise it would grow with every save, because each one keeps the old entries. The first build of a month is a full one until a merge to `main` that changes code saves again.
- The DerivedData path has to stay the same between runs. The same code built at a different path hit only 99 of 156 tasks locally. `$RUNNER_TEMP` should be the same path on every GitHub run.
- `OctavoKit tests` has no cache: it saved only a few seconds locally.

## Signing

CI has no signing identity, so the build signs ad hoc (`CODE_SIGN_IDENTITY=-`). All 434 app tests pass that way on the simulator.

## Timings (2026-11-03)

Measured on an 18-core Mac that was busy with other work, from a fresh clone each time, with only the cache kept between runs. Treat them as rough, and expect GitHub's runners to be slower.

| Step | Cold | Same code, cached | Small change, cached |
|---|---|---|---|
| `swift test` (253 tests) | 13–49 s | not used | not used |
| App build | 164 s | 7 s | 18 s |
| App tests (434 tests) | 27 s | 18 s | 18 s |

The small change added one line to an app file and one to an OctavoKit file: 99 of 156 cacheable compile tasks hit. A change to a widely used OctavoKit file would hit less.

## Watch for

- `AttemptTests` and any other test with short time limits may be flaky on a slower runner. `aServerThatDoesntAnswerTimesOut` expects a 50 ms limit to have fired after 150 ms.
- Some tests start requests to `localhost`, which nothing answers in CI. None waits for the answer.
- Changing a pull request's base branch doesn't re-run CI, so its old result stays. This shouldn't come up while branches are cut from `main`. If a pull request is ever retargeted, re-run CI by hand. Adding the `edited` trigger would fix it, but would also re-run the tests on every title or description edit.
- A rebase merge pushes several commits at once, but a push's check reads only the last one. If that commit is docs-only, `main` skips the tests, though the pull request already ran them. Merge commits and squash merges aren't affected.
- A pull request's own copy of `ci.yml` is what runs, so it can turn "CI passed" green without testing anything. Read every `.github/` change by hand.

## Still to do (#19)

- Add "CI passed" to the "Protect main" ruleset once it has passed on a few real pull requests. Require it from GitHub Actions specifically, and decide whether branches must be up to date with `main` first.
- Turn the foliate-update checks into one script and run them. They need the simulator and Docker together, so probably a self-hosted runner.
- Run the OPDS source against `dev/opds` and the network-trust checks against `dev/trust`.
