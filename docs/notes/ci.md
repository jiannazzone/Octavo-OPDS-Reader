# CI

GitHub runs only `swift test`. The app's tests run on this Mac, through `Scripts/local-tests.sh`, and a pull request can't merge until they've passed on its last commit (see "Why the app's tests left GitHub").

`.github/workflows/ci.yml` runs on every pull request and every push to `main` (#19).

| Job | Runner | What it does |
|---|---|---|
| Changes | `ubuntu-latest` | Decides whether tests are needed |
| Tests | `xcode-27` | `swift test` |
| App tests | `xcode-27` | Only when started by hand: `xcodebuild` on an iPhone Duo, iOS 27.1 |
| CI passed | `ubuntu-latest` | Fails unless the jobs that had to run passed |

## Local tests

`Scripts/local-tests.sh ["simulator name"]`:

1. Refuses uncommitted or untracked files, because a new file builds here whether or not it's committed, and a branch behind `main`.
2. Runs `swift test` and `xcodebuild test -parallel-testing-enabled NO`. If only `docs/`, `site/`, `README.md` or `CLAUDE.md` changed, it skips both, as CI does.
3. Remembers the pass for that commit and posts the "Local tests" status on it. A commit that isn't on GitHub yet can't take a status, so it says to push and run it again, and that run only posts.

A status belongs to one commit, so a new push clears it. Anyone with write access could post one by hand. `CLAUDE.md` says not to, and nothing else stops them.

## Merging

"Protect main" requires "CI passed" from GitHub Actions and "Local tests" from any source, so a pull request can't merge to `main` until both are green. Branches don't have to be up to date with `main` first, because that would mean a new local run on every open pull request after each merge.

The ruleset allows merge commits only. It has no bypass, so if the runner is down, nothing merges until the ruleset is edited.

To skip the wait, use auto-merge, which lands the pull request when the checks pass:

```bash
gh pr merge <number> --auto --merge
```

That command hasn't been tried on a stacked pull request, and GitHub's docs say the older merge APIs can't merge a stack, so use the merge button there. Merging a stack's top pull request lands everything below it too: #51 and #52 landed a second apart, in one push.

## Outside contributors

They can't post the status, and testing their code here would run it on the Mac that holds `op` and the App Store key. Read it, push it to a branch in this repo and start the App tests job there: `gh workflow run ci.yml --ref <branch>`. If it passes, the owner posts the status by hand on that commit. All 58 pull requests so far are the owner's and the repo has no forks, so this hasn't been tried.

## Runner

GitHub's `xcode-27` image lists Xcode 27.2, an iOS 27.1 runtime and the iPhone Duo device type, so no self-hosted runner is needed for these jobs. The image is still a preview, so it may queue or change. It lists no Docker, so the checks that need `dev/bookorbit`, `dev/opds` or `dev/trust` aren't part of this workflow, and those live tests skip themselves when their environment variables aren't set.

The repo is public, so these standard runners should cost nothing. Pull requests from first-time and other outside contributors wait for approval, because the repo's setting is `all_external_contributors`.

A run waited about 10 minutes for a runner, and on #57's run `41866624185` a job failed with "The job was not acquired by Runner of type hosted even after multiple attempts", which turned the required check red. A queue can still do that. The Tests job's limit is 15 minutes, and App tests keeps the 35 it needed before (see below).

## Docs-only changes

A pull request compares its merge commit with the base. A push to `main` compares with where `main` was before the push, so every commit in it counts when a stack lands several at once. Tests are skipped only when every changed file is under `docs/` or `site/` (the website), or is the root `README.md` or `CLAUDE.md`. These are exact paths, not "all Markdown", because a test reads `THIRD-PARTY-NOTICES.md`. Anything else runs the tests, and so does a change with no files. Moving a file counts as changing both paths, so moving code into `docs/` runs them too. `Scripts/local-tests.sh` goes by the same paths.

## The website

Cloudflare Pages serves `site/` (project `octavo-opds-reader`, output directory `site`), connected to this repository. Its build watch paths (`site/*`) skipped every merge into `main`, even ones that changed only `site/` (#128 needed a retry, and #129 never deployed), so they can't be what decides. Every change reaches `main` as a merge commit (the ruleset), and Cloudflare evidently doesn't see a merge's files.

So GitHub decides. `.github/workflows/site.yml` runs on a push to `main` that changes `site/**`, since GitHub's path filter compares with where `main` was, and posts to a Cloudflare deploy hook for `main`, whose URL is the `CLOUDFLARE_DEPLOY_HOOK` secret. Automatic production deployments are off in Cloudflare (Settings > Builds > Branch control), so app changes never redeploy the site. `gh workflow run site.yml` redeploys without a change. The job needs no permissions and runs nothing from the repository.

## Signing

The App tests job has no signing identity, so the build signs ad hoc (`CODE_SIGN_IDENTITY=-`). All 434 app tests passed that way on the simulator.

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

## Test time (2026-11-04)

The Test step grew from 1.6 minutes at `c1b4b19` to 8.6 at `a853701`, one run each, as `ReaderFixedLayoutTests` and `ReaderPicturesTests` grew. Between them they opened a book in a new `WebPage` 59 times a run. Now 9 of those are new pages and 50 are reloads. Before and after in turn on 'Octavo Faster CI Duo' (930C4032-9107-4E7B-98F3-95CE00807CBC), with the machine's load about 4:

| | Before (2 runs) | After (3 runs) |
|---|---|---|
| All app tests (473, the same ones) | 104 s | 31 s |
| `ReaderFixedLayoutTests` | 81 s | 19 s |
| `ReaderPicturesTests` | 14.5 s | 2.8 s |
| `BookInspectorTests`, not changed | 5.2 s | 5.2 s |

These aren't measured on GitHub's runners yet.

**What a new page costs:** about 0.4 s to load the reader and 1.15 s to open the book, plus about 4 s for the first page of a run. Nearly all of the 1.15 s is the first `application/xhtml+xml` frame in that page's WebKit process, even an empty one. An HTML frame takes 2 ms, and so does every XHTML frame after the first. I didn't find out why. Reloading takes about 15 ms to load the reader and 20 ms to open the book.

**How the two suites use that:**

- They keep one page and reload it for each test. They're `.serialized`, because plain `xcodebuild test` would otherwise run their tests at the same time on it.
- A reload starts the scripts again, so nothing in the bridge or foliate carries over. With a `ReaderModel` it opens the way a new page does: the bridge's `ready`, `openBook`, then the saved position.
- It doesn't reset the Swift model. A test that changes the model's settings, reads `lastError` or has a `sync` uses `openInItsOwnPage`. So do one open each from the start, a CFI and a fraction, to keep a new page's path covered.
- A new test in these suites should use the suite's `open` unless one of those applies.

**Checks:** I broke the reader 25 ways, one at a time: the picture rules, and the fixes and places listed in `fixed-layout.md`. The test that covers each one failed each time. The tests also pass in three shuffled orders.

**`-parallel-testing-enabled NO` stays.** The history doesn't say why it was added. Without it, `xcodebuild` shuts down the simulator that CI boots during the build, to clone it. With it, the tests run one at a time. Plain `xcodebuild test` passes on a quiet Mac, in 58 s here, but not on a busy one (see Watch for).

## Why the app's tests left GitHub (2026-11-05)

In about 60 runs over 38 hours, the app build and app tests on GitHub caught no compile failure, missing file or merge break, and one real bug, the pictures race below. 8 of the 10 bad attempts were WebKit pages that stalled or hung, a run took about 16 minutes, and `42148056516` hung until the job was killed, leaving no log. The same tests take about a minute here. 38 hours is a small sample.

A review of the plan argued against relying on a rule in `CLAUDE.md`. OctavoKit hasn't changed since before CI's first run, so `swift test` can't go red on today's pull requests, and #72 and #86 both left the tests to CI. So the local run posts a required status instead.

**What this gives up:**

- Nothing on GitHub compiles the app, so two pull requests that pass alone could break `main` together. The next local run would find it. If that starts to happen, add a build on pushes to `main` that blocks nothing.
- GitHub's slower machines no longer run these tests, and a slow machine is what showed the pictures race, which misses only 1 time in 150–700 here.

## Two flaky tests (2026-11-05)

Both failed on `main` and held up pull requests that didn't touch them, and a re-run costs about 16 minutes.

**`picturesStillFitWhenThePageChangesSize`: a race in the reader, fixed.** It failed in `41897289597` and `42089316037` attempt 2, and it reproduces here (1 miss in 150 opens, 1 in 400, 9 in 700, more on a busier machine). foliate's ResizeObserver could render a section before its `load` event, and the bridge then read that layout's column as the table's own width. Foliate patch 0004 stops that (`reader-pictures.md`, section 6), and the test now also forces the order, so a return of this fails every run.

**`encryptedContentIsDRM`: the first WebKit page of a run, on a new runner.** It's the first app test in 28 of the 29 runs checked, so it opens the run's first page, and nothing about it is to do with DRM. It failed in `42049512673`, `42089316037` attempt 1, `41842337100` and `42142872810`.

- **It isn't the book.** In `42049512673` the page got no answer in 30 s, then the next page answered in about 2 s.
- **The first page is slow, and most of that comes before the book.** The test's two reads took 3.2–10.2 s in 28 passing runs. On 'Octavo Flaky Tests Duo' (943BCED0-F564-4571-AA17-8B78F00DBF28), erased and booted each time, with its processes at background priority, 8 first pages took 10.5–15.1 s: 9.4–14.1 s before the bridge started on the book, and 0.2–1 s on the book.
- **The failed run's log shows the same steps stretched.** Between WebKit's "Unable to filter" and "Unable to hide" lines, a passing run took 0.5 s, `42049512673` took 5.5 s and `41842337100` took 13 s.
- **A frozen page matches the failure.** Holding that simulator's WebContent processes with `SIGSTOP` for 34 s gave `.damaged` at the limit, the next page fine, and no `updateFreezerStatus` line from the first process, as in the failed run.
- **Ruled out, by measuring:** the page's wait for the bridge giving up after 250 tries (a hidden page's repeating timers slow to one every 1–3 s, and a bridge 8 s late was still answered); the process being suspended once the page has loaded (a hidden page kept running for the 70 s tried); and Swift's thread pool running out (one thread, `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`, took 1.4 s).
- **More time on one page doesn't help.** These reads were given 2 minutes first, and `42142872810` still failed, with `.timedOut` on both reads, after 246 s. Its second page reached the same log line as a healthy page, then sent nothing for 118 s, while the app's timer fired on time and the next page answered in 8 s.
- **A slow GPU process goes with the worst runs, but doesn't cause them.** It took 1169 s to start in `41842337100` and 75.8 s in `42142872810`, and at most 9.5 s in the 27 other runs checked, `42049512673` among them (1.1 s). On 'Octavo Hang Duo' (EDEFC536-F367-453D-8142-F3C9EAF5B048), with the 2-minute limit, holding it for 75 s from its start changed nothing: the test passed in 1.4 s. Holding the Networking process the same way only delayed the answer, to 76.5 s. Neither leaves a page stuck.

**What else was tried:** a wait before the first suite, opening pages until one answered. With the Networking process held for 75 s, the test failed without it (`.timedOut` twice in 60.9 s, as in CI) and passed with it, in 0.96 s. Its one run on GitHub, `42148056516`, hung until the job was killed, with no log, so whether it played a part isn't known. It went when these tests left GitHub.

**Not known:** what stops a page on a runner. Nothing tried here leaves a page stuck for good. These failures came in 4 of about 30 runs. In `41842337100` the whole app stopped for 19 minutes, in the run that moved the simulator's boot, which went back.

**Also stalled:** reader tests that allow 30 s to open, later in a run: `aLinkOutOfTheBookGoesNowhere` in `42114104467` and `aTurnAskedForOverANoteOnlyClosesIt` in `42142872810`. That's 2 failures in the same 30 or so runs, each after a test that took 12–13 s.

**`.timedOut`:** a timeout used to be `.damaged`, so a stall read as a bad book, in CI and in an import. `BookInspector` now throws `.timedOut`, so the two can't be confused, and `anEPUBThatWontOpenIsDamaged` can no longer pass on a timeout. A real import still has its 30 s and still says the file may be damaged (`BookImporter.reason`), so nothing on screen changes. Better wording is parked in `docs/UI-IDEAS.md`. No stall has been seen outside a simulator, but no real device has been measured for this.

## Watch for

- `AttemptTests` and any other test with short time limits may be flaky on a slower runner. `aServerThatDoesntAnswerTimesOut` expects a 50 ms limit to have fired after 150 ms. Plain `xcodebuild test`, in parallel on a Mac with a load of 25–70, fails it every time, and `BookPlacesTests.rowsFetchStartedBooksAtMostOnceAMinute` most times (2026-11-05, at `765f007` too). With `-parallel-testing-enabled NO`, as `Scripts/local-tests.sh` runs them, both passed.
- `BookInspectionError.timedOut` from `BookInspectorTests` means a page gave no answer in 30 s, which is WebKit, not the book (see above).
- The App tests job can still stall as above, so a failure there may say nothing about the code.
- Some tests start requests to `localhost`, which nothing answers in CI. None waits for the answer.
- Changing a pull request's base branch doesn't re-run CI, so its old result stays. If a pull request is ever retargeted, re-run CI by hand. Adding the `edited` trigger would fix it, but would also re-run the tests on every title or description edit.
- A pull request's own copy of `ci.yml` is what runs, so it can turn "CI passed" green without testing anything. Read every `.github/` change by hand.

## Still to do (#19)

- Turn the foliate-update checks into one script and run them. They need the simulator and Docker together, so probably a self-hosted runner.
- Run the OPDS source against `dev/opds` and the network-trust checks against `dev/trust`.
