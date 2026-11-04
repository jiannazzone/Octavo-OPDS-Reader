# CI

`.github/workflows/ci.yml` runs on every pull request and every push to `main` (#19).

| Job | Runner | What it does |
|---|---|---|
| Changes | `ubuntu-latest` | Decides whether tests are needed |
| Tests | `xcode-27` | `swift test`, then `xcodebuild` on an iPhone Duo, iOS 27.1 |
| CI passed | `ubuntu-latest` | Fails unless the jobs that had to run passed. The one check "Protect main" requires |

## Merging

"Protect main" requires "CI passed" from GitHub Actions, so a pull request can't merge to `main` until it's green. Branches don't have to be up to date with `main` first, because that would make every merge re-run CI on the other open pull requests.

The ruleset allows merge commits only. It has no bypass, so if the runner is down or a test is flaky, nothing merges until the ruleset is edited.

To skip the wait, use auto-merge, which lands the pull request when the check passes:

```bash
gh pr merge <number> --auto --merge
```

That command hasn't been tried on a stacked pull request, and GitHub's docs say the older merge APIs can't merge a stack, so use the merge button there. Merging a stack's top pull request lands everything below it too: #51 and #52 landed a second apart, in one push.

## Runner

GitHub's `xcode-27` image lists Xcode 27.2, an iOS 27.1 runtime and the iPhone Duo device type, so no self-hosted runner is needed for these jobs. The image is still a preview, so it may queue or change. It lists no Docker, so the checks that need `dev/bookorbit`, `dev/opds` or `dev/trust` aren't part of this workflow, and those live tests skip themselves when their environment variables aren't set.

The repo is public, so these standard runners should cost nothing. Pull requests from first-time and other outside contributors wait for approval, because the repo's setting is `all_external_contributors`.

`swift test` and the app's tests share one job, so a run asks for one runner. They were two jobs until 2026-11-04. A run waited about 10 minutes for a runner, and on #57's run `41866624185` the OctavoKit job failed with "The job was not acquired by Runner of type hosted even after multiple attempts" while App tests passed, which turned the required check red. `swift test` goes first because it takes 1–2 minutes, so a failure there stops the run early. The app's results then wait until it's fixed. The job's limit is 35 minutes: the App tests job's 30, which one bad run nearly reached (see below), plus 5 for `swift test`.

## Docs-only changes

A pull request compares its merge commit with the base. A push to `main` compares with where `main` was before the push, so every commit in it counts when a stack lands several at once. Tests are skipped only when every changed file is under `docs/`, or is the root `README.md` or `CLAUDE.md`. These are exact paths, not "all Markdown", because a test reads `THIRD-PARTY-NOTICES.md`. Anything else runs the tests, and so does a change with no files. Moving a file counts as changing both paths, so moving code into `docs/` runs them too.

## Build cache

The Tests job turns on Xcode's compilation cache with `COMPILATION_CACHE_ENABLE_CACHING=YES`, in the workflow only, so local builds are unchanged. It keeps only `CompilationCache.noindex`, not the rest of DerivedData. Its entries are keyed by the compiler's input, not by file dates, so a fresh checkout still hits the cache and a stale result can't be reused the way it can with DerivedData.

- Only pushes to `main` that run the tests save the cache, so a docs-only merge doesn't. A pull request restores it but never writes it, so the first build after the cache is empty is a full one.
- The key holds the Xcode build and the month, so a new Xcode or a new month starts a fresh cache. Otherwise it would grow with every save, because each one keeps the old entries. The first build of a month is a full one until a merge to `main` that changes code saves again.
- The DerivedData path has to stay the same between runs. The same code built at a different path hit only 99 of 156 tasks locally. `$RUNNER_TEMP` should be the same path on every GitHub run.
- `swift test` has no cache: it saved only a few seconds locally.

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

## Timings on GitHub's runners (2026-11-04)

Four runs of what was then the App tests job, with the simulator booting before the build. Most of the job's time comes before compiling, and the first `xcodebuild` on a new runner is the largest part. The second one, in the Test step, printed its first output in 6–8 s.

| Phase | No cache (2 runs) | Cached (2 runs) |
|---|---|---|
| First `xcodebuild` output | 346 s, 277 s | 354 s, 329 s |
| Setup before compiling | 232 s, 118 s | 252 s, 176 s |
| Compiling and linking | 157 s, 423 s | 61 s, 15 s |
| Running the tests | 75 s, 65 s | 129 s, 52 s |
| Whole job | 13m47s, 15m07s | 13m52s, 9m52s |

Booting the simulator after the build was tried once (#52), and went back. Commit `1802bb3` on `main` still has the title "CI: boot the simulator after the build", but it only changes docs. The build took 41 s and the boot 75 s, but the Test step took 27 minutes and failed, and the job came within seconds of its 30-minute limit. WebKit's GPU process took 1,169 s to launch, against 1–5 s in the earlier runs that logged it, so `BookInspector` hit its 30 s limit and reported `.damaged`. One run doesn't prove the cause. It does suggest that a new runner's slow start goes with the simulator's first start, and that moving the boot doesn't remove it.

## Watch for

- `AttemptTests` and any other test with short time limits may be flaky on a slower runner. `aServerThatDoesntAnswerTimesOut` expects a 50 ms limit to have fired after 150 ms.
- A WebKit process that stalls on the runner makes `BookInspectorTests` fail with `.damaged`, which looks like a bad book but is a timeout. "CI passed" is required, so re-run before looking for a bug.
- Some tests start requests to `localhost`, which nothing answers in CI. None waits for the answer.
- Changing a pull request's base branch doesn't re-run CI, so its old result stays. If a pull request is ever retargeted, re-run CI by hand. Adding the `edited` trigger would fix it, but would also re-run the tests on every title or description edit.
- A pull request's own copy of `ci.yml` is what runs, so it can turn "CI passed" green without testing anything. Read every `.github/` change by hand.

## Still to do (#19)

- Turn the foliate-update checks into one script and run them. They need the simulator and Docker together, so probably a self-hosted runner.
- Run the OPDS source against `dev/opds` and the network-trust checks against `dev/trust`.
