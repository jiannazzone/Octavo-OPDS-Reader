# Rating BookOrbit books (#120)

Your own rating of a BookOrbit book, 1 to 5 whole stars, from its screen. Decided with Adam and built on 2026-11-13, after the read statuses (`book-status.md`). The server's side is measured in `bookorbit-api.md`, "Read status, rating and collections". Collections, the issue's last action, come next.

## Decided (Adam, 2026-11-13)

- **Where:** a star button beside "…", folded beside Mark finished and unfolded beside the title. It opens one flat menu: ★★★★★ down to ★, with a tick on your rating, and Clear rating once there is one. A Rate submenu inside "…" was proposed first; Adam didn't want a menu in a menu. Five stars in a details row (one tap, but a custom control) wasn't chosen.
- **Once rated:** the button says it, "★ 4", growing from a circle to a capsule. Not chosen: a circle whose star only fills (says rated, not how many), and a row of stars (squeezes the title and Mark finished).
- **Book screen only:** covers and lists don't show a rating; the badge already holds the finished or status glyph and the download arrow. Sorting or filtering by rating is parked in `UI-IDEAS.md`.
- **BookOrbit books only,** like "…". OPDS and Files books have no server to keep a rating.
- **"Rate it":** right after you mark a book Finished, Skimmed or Abandoned on its screen, and only if it isn't rated, a row under the buttons asks: "Rate it", five stars and ✕. A star saves the rating and the row goes, leaving "★ 4" on the button. ✕, leaving the screen, or undoing the mark puts it away; it asks again only when the book is marked again. No pop-up (decision 22).
  - Not chosen: a card at the end of the book. Many books end in glossaries, notes and legal pages that readers skip, and finding where the story ends from landmarks or the contents was too unreliable.
  - BookOrbit marking a book read on its own at 100% doesn't ask: only a mark you make does.

## How it's built

- OctavoKit: `LibraryBook.rating` from BookOrbit's `rating` (anything but a whole 1 to 5 reads as not rated), `LibrarySource.tracksRating` and `setRating(_:for:)`, and `BookOrbitClient.setRating`, which sends `{bookIds, rating}` with `null` to clear. A rating outside 1 to 5 is refused before sending, as the server would refuse it.
- `BookPage.rating` is the one set here over the server's. `setRating` shows the change at once and puts it back if the server refuses ("Couldn’t change the rating. Check your connection."). Only the latest of several quick choices puts things back, to the rating the server last took from here.
- `BookPage.asksRating` is "Rate it". It asks only once the book's details are in: before then the rating is the list's, which can be older than the server's.
- `BookRateButton` (the button and its menu) and `BookRatingPrompt` (the row) are in `Octavo/Book/BookRateButton.swift`. The round buttons share their size and glass (`bookRoundLabel`, `bookRoundButton`).
- The row's stars and ✕ are 44 pt wide; where the row is too narrow, "Rate it" goes above them (`ViewThatFits`). Each star is its own button for VoiceOver ("Rate 4 stars"), and ✕ is "Not now". The button reads "Rating, 4 stars", or "Rating, None".

## Checked

- OctavoKit: the request for each rating and for clearing, nothing else in the body, out-of-range ratings refused, and decoding.
- App: rating, clearing, a refusal put back, quick choices answered out of order, when "Rate it" asks (each status, a rated book, before the details, a server without ratings) and what puts it away.
- End to end on iPhone Duo #120 against the local BookOrbit: rating from the menu (on the server), re-rating, Clear rating (the row kept with `null`), and Mark finished bringing up "Rate it", whose fourth star saved 4. The server was put back afterwards.
- Simulator screenshots: the button and its menu unfolded, "★ 4" folded and unfolded, "Rate it" unfolded.

## Not done

- "Rate it" folded: scripted taps don't reach the folded sheet, so it was only seen unfolded.
- Rating from the reader, or a long press on a cover.
- A rating set elsewhere shows once the book's screen is opened afresh: an open page keeps the one it loaded.
