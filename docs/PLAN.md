# Build order

One area at a time, in this order. Each step goes to the simulator when it's built, and each phase ends on Adam's Duo for sign-off. The decisions behind each step are in `docs/design/direction.md`; steps marked *needs decisions* get designed with Adam first.

## Phase 1: Library

- [x] **1. Shell.** Three tabs, one stack of screens per tab, each screen a spread across both pages; Back and swipe back; Settings button.
- [x] **2. Library.** Sections as shelves; a section opens over the whole spread (grid of covers, or a list flowing left page → right page).
- [x] **3. A book's screen.** Folded: the cover with a sheet (title, progress, Mark finished, Open or Download; pull up for details). Unfolded: Cover | Details. Unfolding opens a downloaded book.
- [x] **4. Downloads.** A check on downloaded covers and a ring while downloading, everywhere covers show; downloads kept where iOS won't clear them; Remove download; nothing downloads in the background.
- [x] **5. Home.** The book you're reading, large, with your other books in progress beneath (or on the right page).
- [x] **6. Series and authors.** Series as cover stacks, opening in reading order; Authors first name first, filed by last name, with an A–Z strip on long lists.
- [x] **7. Search tab.** The field under the title; Recent and Browse before typing; Books, then Series and Authors, as you type, with books on the iPhone included.
- [x] **8. Adding your server.** Setup before there's a server: BookOrbit (sign in, then where progress syncs) or an OPDS catalog (its address, a sign-in only if it asks), trusting a self-signed certificate on the way; each step a screen across the spread. Signing in again from the signed-out banner.
- [x] **Library on the Duo:** Adam signed off (2026-11-02), then a pull request to `main` (with Adam's OK). Setup touches the Keychain and address handling, so it gets a security review that Adam signs off before the merge.

## Phase 2: Reading

- [x] **9. Reader controls.** A quiet "…" in the side column is the one way to bring the controls up, in every posture; every other tap turns (left of the middle back, right of it and the column forward).
- [ ] **10. Page turning.** Taps, swipes, keyboard and trackpad; book mode; folding and unfolding mid-book.
- [ ] **11. Rendering.** The rendering problems seen on the Duo.
- [ ] **12. Panels.** Text and theme, Contents and bookmarks, Search in book. *Needs decisions.*
- [ ] **Reading on the Duo:** sign-off, pull request.

## Phase 3: The rest of v1

- [ ] **13. Sync you can see.** Last synced, "not synced yet". The place on a book's screen matches where the book opens (a server percentage without a position opens at the start today), and unfolding opens at once (the server's position is fetched while the cover shows, not after the unfold).
- [ ] **14. Settings.** Server, Storage (books on iPhone), About, Remove server.
- [ ] **15. Other ways in.** Import from Files, the bundled sample book, MOBI/AZW3/FB2 check.
- [ ] **16. Security follow-up.** Confirm whether a server counts as local by its name alone (#9), and fix it if so. From the setup review (2026-11-02, all Low or Info): a Keychain read error at launch builds the server without its pinned certificate (fail closed instead); secrets left by an abandoned setup stay until a reinstall (clear them at launch); in-address secrets other than Kavita's key are saved as typed; the "Not encrypted" note could name the other-network risk (wording is Adam's).

## Phase 4: First impressions

- [ ] **17. The new-install flow.** What someone sees the first time, from opening the app to their first book (Adam, 2026-11-02). *Needs decisions.*

## To revisit

- The book sheet at rest, folded, is still quite tall; try a smaller resting state (Adam, after step 4).

## What you'll see that isn't right yet

These screens are still the old ones or stand-ins; the step that replaces them is on the right.

| You see | Fixed in |
|---|---|
| Settings is a stand-in | 14 |
| Anything in the reader | 9–12 |
| A book opens somewhere other than the % its screen shows, or after a pause on unfolding | 13 |

Something wrong in a step that's ticked is a bug in that step, fixed before moving on.
