# Leaving the app doesn't move the place (2026-11-04)

Leaving the app could save the wrong reading place, and folding soon after could make it stick and send it to BookOrbit. It no longer does. Measured on 'Octavo Background Place Duo' (C590BB4D-A0B3-4197-A10E-9539FA060ABF, iPhone Duo, iOS 27.1 simulator), debug builds.

## Summary

- **Cause:** as the app goes to the background, iOS turns it sideways and back for its snapshots. The reader laid out for those sizes, the page landed somewhere else, and the model saved that as a real move.
- **Fix:** while the app is in the background, size and hinge changes wait, and the reader lays out for how the phone really is when the app comes back. A move that lands meanwhile is still saved.
- **Tests:** `OctavoTests/ReaderBackgroundTests.swift`. Three of the four fail without the fix. The fourth checks that a real move is still saved, so it passes either way.
- **Not measured:** a real Duo, a Release build, and how the moment of return looks after unfolding while away (section 4).

## 1. The cause

Going to the background unfolded, from temporary logging on `main`'s reader code:

```
17:11:19.904  scene background
17:11:20.225  safeAreaChanged top 82, right 0
17:11:20.227  call setLayout (2 columns, top inset 82)
17:11:20.269  geometryChanged (hinge region now runs sideways)
17:11:20.269  call setLayout (1 column)
17:11:20.491  safeAreaChanged top 0, right 84
17:11:20.491  call setLayout (1 column)
17:11:20.510  geometryChanged (hinge region upright again)
17:11:20.510  call setLayout (2 columns)
17:11:20.737  relocate /8/1:752
17:11:20.737  save /8/1:752, the reader's place being /14/1:549
```

The four layouts come from `safeAreaChanged` and `geometryChanged`. The page's own size doesn't change, so there's no `viewport` message. Turned sideways is my reading of those values: the side column becomes a band along the top and the hinge region runs across.

The next re-layout normally restores the place, because foliate keeps its anchor. If the reader closes first, the wrong place stays. A fold closes it, and closing pushes what's waiting.

The bug is older than the closed-reader fix (`reader-release.md`). On `main`'s reader code a fold moved the place in every round from 1 s on that ran: local at 1, 2 and 5 s, BookOrbit at 1 s, before the script stopped on a bug of its own. There, with no limit on waiting for a frame, the correction waited for the app to come back. The 1 s limit from that fix shortened the gap but didn't close it.

## 2. The fix

`ReaderModel.isInBackground`, set by `ReaderScreen` from `scenePhase`:

- **`updateGeometry` and `hingeChanged` stop there while it's set.** The latest safe area, geometry and hinge are still kept. A hinge change skips `beginFold`, whose cover and batch are for a fold you can see.
- **When the app comes back,** the model lays out from those latest values. If they match what the page has, nothing is sent.
- **Relocations aren't held back.** A page still loading as you left is a real move, and with no layouts sent, nothing else moves the page.

It goes by `.background`, not `.inactive`. In every trip logged, the layouts came after `scene background`.

## 3. Measured in the app

`check.py left_the_app`, reading the saved place every 0.2 s from leaving until 4 s after coming back. "Without the fix" is this branch with the guards in `updateGeometry` and `hingeChanged` removed, so the closed-reader fix and its 1 s limit are still there.

| Round | Without the fix | With the fix |
|---|---|---|
| Local, no fold | Changes, then back | Never changes |
| Local, fold after 1 s | **Stays wrong:** `/14/1:549` → `/8/1:752` | Never changes |
| Local, fold after 5 s | Changes, then back | Never changes |
| BookOrbit, no fold | Changes, then back. Server the same | Never changes. Server the same |
| BookOrbit, fold after 1 s | **Stays wrong, on the server too:** `/140/3:47` → `/108/1:160` | Never changes. Server the same |
| BookOrbit, fold after 5 s | Changes, then back. Server the same | Never changes. Server the same |

**Fold times** count from when `simctl launch` of another app returns, not from `scene background`, which came 0.3 to 6.5 s after the app went inactive.

**Real changes while away** (`changed_while_away`) end up the same as on screen, and the page still turns:

| Change | Layout when it comes back |
|---|---|
| Rotated while away | 1 column, top inset 82, as when rotated on screen |
| Rotated back while away | 2 columns, side insets 84, as upright on screen |
| Unfolded while away | 2 columns, side insets 84, fold at 455.5–495.5, as unfolded on screen |

A screenshot after unfolding while away shows the spread on either side of the fold, with no text on the hinge.

`place_kept` (the place on closing) and `stays_open` (a reader still turns after folds, rotation and the background) pass. All 539 app tests pass.

## 4. Not covered

- **A real Duo.** The app kept running in the simulator's background, and a phone may suspend it sooner. The snapshots' sizes may also differ. With no layout sent, the place shouldn't move either way, but that's untested.
- **The moment of return.** Unfolding while away lays out as the app returns, without the cover that hides a fold on screen. The result is right; a brief flash wouldn't show in a screenshot, and nobody has watched it.
- **Leaving just after a fold on screen.** The fold still finishes while the app is away, using the geometry from before it left. Not measured.

## 5. Running it again

As in `reader-release.md` section 5, with:

```bash
python3 docs/notes/reader-release/tools/check.py <udid> left_the_app changed_while_away
```

`left_the_app` needs the local BookOrbit.
