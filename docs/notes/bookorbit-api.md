# BookOrbit API: what the spike learned (v3.6.0)

Spike 1b (`BookOrbitClient` in OctavoKit) and 2a (sync), measured against the local server in `dev/bookorbit/` (start, seed and test accounts are in its README). These are observed behaviours of BookOrbit **v3.6.0**. The API changes between versions, so re-check against a live server when upgrading. Nothing here is copied from BookOrbit's code (AGPL); it comes from calling the API.

## Auth

- **Native mode (v3.0+):** `POST auth/login {username, password, clientKind: "native", deviceLabel}` returns `{accessToken, accessTokenExpiresAt, refreshToken, refreshTokenExpiresAt, sessionId, user}` and sets **no cookies**. Refresh with `POST auth/refresh {refreshToken}`, which returns the same token fields.
- **Web mode (no `clientKind`, and the only mode before 3.0):** the body has `{accessToken, accessTokenExpiresAt, sessionId, user}` and the refresh token is a cookie (`Path=/api/v1/auth; HttpOnly; SameSite=Strict`, `Secure` only over HTTPS). BookOrbit's Android client still uses this mode.
- Access tokens last 15 minutes, refresh tokens 7 days. **Refresh tokens rotate on every refresh** (30 s grace for concurrent reuse), so store the new one every time.
- **Login is rate-limited to 5 per minute per IP** (HTTP 429).
- **Logout:** `POST auth/logout {refreshToken}` revokes the session (measured 2026-11-02: afterwards the refresh token and the access token both get 401, and `auth_sessions.revoked_at` is set). The access token alone (bearer, empty body) gets 200 but revokes nothing. `BookOrbitClient.signOutEverywhere()` sends it, as the refresh cookie for pre-3.0 servers, after forgetting the tokens on the iPhone.
- `BookOrbitClient` uses native mode and falls back to web mode for pre-3.0 servers, which reject `clientKind`. It never uses URLSession's cookie jar: in web mode it lifts the cookie into the token store and replays it as a header. That also avoids BookOrbit's 400 "Conflicting refresh credentials" when a stale cookie and a body token both arrive.

## Validation

- The server rejects **unknown request fields** with 400 (`forbidNonWhitelisted`). Send only documented fields.
- Swagger is **off by default** (`SWAGGER_ENABLED=true` turns it on; the dev server has it on). The published image's OpenAPI lists routes and parameters, but its request and response schemas are empty, so real shapes come from live responses.
- Shapes differ between endpoints, e.g. `authors` is `[String]` in collection listings but `[{id, name, sortName}]` in `GET books/{id}`. Decode tolerantly.

## Progress

- `percentage` is **0–100** (the server rejects values over 100), stored as float4 (about 7 significant digits). `ReadingPosition.fraction` is 0–1, so the client multiplies by 100. BookOrbit's web reader sends foliate's `fraction × 100`.
- `GET books/files/{id}/progress` always returns an object. A never-opened file gives `{cfi: null, pageNumber: null, percentage: 0, textUpdatedAt: null, …}`, plus narration, Kobo and KOReader fields. `textUpdatedAt` is the server's clock.
- `POST books/files/{id}/progress {cfi?, percentage, pageNumber?}` returns 201 with an empty body. Writes are last-write-wins, and **a missing `cfi` clears the stored CFI**. Optional `source: "text" | "narration"`.
- `GET books/{id}/progress` returns one entry per file, with `updatedAt`.
- BookOrbit's own web reader writes through `GET/PUT /api/v1/reading-progress` (batched, with Kobo/KOReader fields). It's the same row as `books/files/{id}/progress`, so either path syncs.
- **Position format:** the web reader stores a collapsed **point** CFI at the start of the visible page; foliate reports a range. Octavo pushes the start point (`CFI.collapse(range)` in `bridge.js`). Element-start pages differ only in string form (ours `/102[id]`, the web's `/102[id]/1:0`), so compare positions by resolving them, never as strings.
- Fixed-layout books: the web reader restores by the percentage alone, which can land a page late. Octavo restores by CFI (`fixed-layout.md`).

## Bookmarks (step 12, measured 2026-11-02)

- `GET books/{bookId}/bookmarks` lists `{id, bookId, cfi, title, note, positionSeconds, createdAt, updatedAt, clientId, origin, chapterId}`; BookOrbit's web reader shows `title`.
- `POST books/{bookId}/bookmarks` takes only `{cfi, title, bookFileId}`: `cfi` and `title` are required (up to 2,000 and 500 characters), and `note`, `color`, `clientId`, `origin` and anything else are rejected (400). So there's no idempotency key: a retry after a lost answer adds a second bookmark, which `BookmarkReconciliation` matches by CFI instead.
- `PATCH books/{bookId}/bookmarks/{id} {title}` renames; `DELETE books/{bookId}/bookmarks/{id}` answers 204, and 404 once it's gone (`DELETE bookmarks/{id}` doesn't exist).

## Library and files

- `GET collections/{id}/books?page=0&size=50[&q=…]` returns `{items, total, page, size}`. Items carry `authors`, `files: [{id, format, role, sizeBytes, mediaOverlay}]`, `readingProgress` (0–100) and a `readStatus` object.
- `GET books/{id}` adds `filename`, `absolutePath`, `fileHash` and `contentVersion` to each file.
- `GET books/files/{id}/serve` returns the file (`application/epub+zip`) with an ETag, `Accept-Ranges: bytes` and a Content-Disposition filename. It is byte-identical to the upload.
- The web reader is at `/read/{bookId}/{fileId}?format=epub`. Opening a book there writes progress for that file.

## Browsing (issue #7, `BookOrbitSource`)

Checked live against v3.6.0, plus BookOrbit's request DTOs for parameter names (read for behaviour, nothing copied).

- **All books:** `POST books/query {q?, sort: [{field, dir}], pagination: {page, size}}` returns `{items, total, page, size}` with status **201**. `size` is at most 200. Paging and sort go in the body; the same keys in the query string are ignored. The body is a zod schema that **silently drops unknown keys**, so a misspelt field just does nothing. Sort fields include `title`, `addedAt`, `relevance`, `seriesIndex`, `author`, `lastReadAt`. `q` matches titles, authors and series.
- **Filtering `books/query` (#131):** `filter` is the smart scopes' rule tree, `{type: "group", join: "AND"|"OR", rules: [rule or group]}` with rules `{type: "rule", field, operator, value?}`. Measured 2026-11-09 against v3.6.0 with a throwaway user whose books had each mix of status and progress:
  - A group with **no rules** is a 400 with no detail (so is `{}`). A wrong value type (`includesAny` with a string, not an array) is a 500.
  - `readStatus` takes `includesAny`, `excludesAll`, `isEmpty`, `isNotEmpty`, with statuses `unread, want_to_read, reading, on_hold, rereading, read, skimmed, abandoned`. `includesAny ["unread"]` **also matches books with no status**, as `isEmpty` does.
  - `readProgress` takes `isUnread`, `isInProgress`, `isFinished`. `isUnread` matches no progress **and 0%**, whatever the status.
  - Posting progress sets the status to `reading` (`source: "auto"`), so a book opened and turned once has one even at 0%.
  - **Unread** (status `unread` or none, and no progress) is `readProgress isUnread` AND (`readStatus isEmpty` OR `readStatus includesAny ["unread"]`). It matched by hand on every case: no status, `unread`, `read`, `want_to_read`, 0% `reading`, 0% `unread`, and 30% set back to `unread`. The OR keeps it right if `includesAny` stops matching an empty status.
  - `collections/{id}/books/query` and `smart-scopes/{id}/books/query` take the same body. A scope's own filter still applies under `filter`, and with no `sort` a scope keeps its own order (measured 2026-11-10).
  - `series` takes only `includesAny` (anything else is a 400), matching the **exact** name, case and all. `author` takes `includesAny` and `includesAll` and matches **any part** of a name, in any case: `["Dumas"]` and `["alexandre dumas"]` both find Alexandre Dumas. An id matches nothing in either.
  - BookOrbit's source lists more fields (`genre`, `tag`, `addedAt`, `rating` and others); none of them measured yet.
  - `page` is **0-based**: page 1 of a short list comes back empty with the right `total`.
- **Lists that reject unknown query parameters** (400 `property X should not exist`), with what each accepts:
  - `GET series`: `page, size ≤ 100, q, sort (relevance|name|bookCount|lastAddedAt|readProgress), order, libraryId, completionStatus`. The page adds `facets`. Items: `{id, name, bookCount, readCount, authors: [String], coverBookIds, volumes, gaps, …}`.
  - `GET series/{id}/books`: `page, size ≤ 100, sort (seriesIndex|title|addedAt), order, libraryId`. The page adds `seriesInfo`.
  - `GET authors`: `page, size ≤ 100, q, sort (relevance|name|sortName|bookCount|lastAddedAt|lastEnrichedAt), order, libraryId, …`. Items: `{id, name, sortName, bookCount, coverBookId, imageUrl}`.
  - `GET authors/{id}/books`: `page, size ≤ 100, sort (title|publishedYear|addedAt), order, libraryId, collapseSeries`. Default `addedAt desc`.
  - `GET search`: `q` (2–200 characters), `limit` (1–10, default 5), `libraryId`. Returns `{query, books, authors, series}`, each `{items: [{item, matchedField, matchedText}], total}`.
- **Continue reading (#13):** `GET dashboard/scrollers/continue-reading?limit=N` returns `{books: [book], total}`, the list BookOrbit's own home shows, most recently read first. Items are ordinary list books plus `readStatus {status, source, startedAt, finishedAt, updatedAt}`; `readStatus.updatedAt` gives the order. Not paged. Swagger marks `smartScopeId` required, but the call works without it. `dashboard/widgets/currently-reading` lists the same books in a different shape.
- **Lists that don't validate the query:** `GET collections/{id}/books` (`page, size, q, collapseSeries`) and `GET smart-scopes/{id}/books` (`page, size, q`). Octavo uses their `books/query` forms (step 2 of #131). `GET collections` and `GET smart-scopes` return plain arrays; either can hold `mediaType: "podcasts"` entries.
- **Shapes to decode tolerantly:**
  - `seriesIndex` is a **string** in 3.6 (`"1"`, `"2.5"`), in lists, in `seriesMemberships` and in the detail.
  - `title` can be `null` in lists.
  - `books/{id}` adds `collections: [{id, name}]`, `seriesMemberships: [{seriesId, seriesName, seriesIndex, displayOrder, expectedBookCount}]`, `readStatus` and `addedAt`. Its `readingProgress` is `null`; lists carry it.
- **Covers:** `GET books/{id}/thumbnail` (JPEG about 386×600) and `GET books/{id}/cover` (the original). Both need the bearer token, send `Cache-Control: private, max-age=86400` and an ETag, and reject unknown query parameters. `coverVersion` on a book changes when its cover does.
- **Download progress:** `serve` sends `Content-Length`. URLSession's async `download(for:delegate:)` never calls `didWriteData` on the task delegate; `didCreateTask` plus observing `task.progress` works (370 updates for a 25 MB book).
- **Smart scopes for tests:** `POST smart-scopes {name, icon, filter: {type: "group", join: "AND", rules: [{type: "rule", field, operator, value}]}, defaultSort: [{field, dir}]}`; `DELETE smart-scopes/{id}`.

## Read status, rating and collections (#120, measured 2026-11-12)

Measured as `octavo` on one book with no status, and on 2026-11-13 on four more with no history, then put back: the rows the runs made (reading attempts, the status, the rating) were deleted from the database afterwards. How Octavo uses this is in `book-status.md`.

- **Status:** `PATCH books/{id}/status {status}` answers 200 with `{status, source: "manual", startedAt, finishedAt, updatedAt}` for each of `unread, want_to_read, reading, on_hold, rereading, read, skimmed, abandoned`. Any other value, `null` or an unknown field (`source`) is a 400; `{}` is a 400 that names `status`, `startedAt` and `finishedAt`, so the body can set the dates too. There's no way back to no status: `unread` is the nearest. `POST books/bulk-set-status {bookIds, status}` takes the same values.
  - `reading` on a book that's been read is stored as `rereading`.
  - `reading`, `on_hold` and `rereading` keep a start date and `read` adds a finish date; `want_to_read`, `skimmed`, `abandoned` and `unread` have neither.
  - **`read`, `skimmed` and `abandoned` each end a reading attempt** in `GET reading-history` (outcome `completed`, `skimmed`, `abandoned`), and so does setting `want_to_read` or `unread` on a book being read (outcome `abandoned`). Changing a status back and forth leaves entries behind; Mark finished on and off already did.
  - **A status never moves progress:** `unread` or `read` on a book at 40% leaves it at 40% with its CFI.
- **Progress changes some statuses**, the same through `POST books/files/{id}/progress` (Octavo's) and `PUT reading-progress` (BookOrbit's web reader: `{writes: [{fileId, percentage, text: {cfi}}]}`, up to 25 writes, answering `{results: [{fileId, status: "saved", progress}]}`):
  - Any progress makes no status, `reading`, `rereading` and `on_hold` into `reading` (`rereading` if read before), `source: "auto"`.
  - **`unread` and `want_to_read` become `reading` too, unless the book has been finished before** (a `completed` attempt in its history): then a hand-set one stays at any progress. Measured 2026-11-13 on books with no history, with a finished one and with an abandoned one, through both requests. The first measurement (2026-11-12) ran on a book these tests had already finished, so it looked as if Octavo's request left them and the web reader's didn't; it doesn't.
  - `read`, `skimmed` and `abandoned` set by hand stay.
  - 100% makes `reading`, `rereading` and `on_hold` `read` (`auto`). Measured on a book read before only.
- **Continue reading** (`dashboard/scrollers/continue-reading`) lists books with progress whose status is `reading`, `rereading`, `on_hold` or `want_to_read`. `read`, `skimmed`, `abandoned` and `unread` leave it, and no book without progress is listed. The other scrollers (`dashboard/scrollers/{type}`): `recently-added, continue-listening, want-to-read, up-next-in-series, random, smart-scope`.
- **Filtering on it:** `readProgress isInProgress` is more than 0% and less than 100%, `isUnread` none or 0%, `isFinished` 100%, whatever the status. Groups nest: `{join: "OR", rules: [status in [reading, rereading], {join: "AND", rules: [status in [on_hold, want_to_read], isInProgress]}]}` works.
- **Rating:** per user (table `user_book_ratings`); lists and the detail show the user's own as `rating`. `POST books/bulk-set-rating {bookIds, rating}` answers 204. `rating` is a whole number from 1 to 5 (4.5, 0 and 6 are 400s); `null`, or no `rating`, clears it. One unknown book makes the whole request a 404, an unknown field a 400. `communityRatings` are the metadata providers' ratings. A reading attempt has a rating of its own (`PATCH reading-history/{attemptId}/rating`), not measured on its own.
  - Measured again 2026-11-13 from the app (`book-rating.md`): clearing keeps the user's row with `rating` null, and the book's detail then sends `rating: null`. **Rating a book also writes the rating onto its latest reading attempt** (here a `completed` one made by Mark finished seconds earlier).
- **Collections:**
  - `GET collections?bookIds=33` lists every collection with `memberCount`, how many of those books it holds; `POST collections/membership {bookIds}` answers the same with 201. One request is enough for a checklist.
  - `POST collections/{id}/books {bookIds}` adds (201, the collection with its new `bookCount`); adding again changes nothing. `DELETE collections/{id}/books {bookIds}` removes (200), also safe to repeat. An unknown book or collection is a 404, an unknown field a 400. The book's detail lists the change at once.
  - `isOwner` marks the user's own collections. Adding to another user's shared collection isn't measured (no second account with a known password). A list can hold `mediaType: "podcasts"` collections.

## Seeding (used by `dev/bookorbit/seed.sh`)

`POST auth/setup` (header `x-setup-token`), `POST libraries {name, icon, folders}`, `POST libraries/{id}/upload` (multipart `file`; 409 `UPLOAD_DESTINATION_CONFLICT` on a duplicate), `POST collections {name, icon}`, `POST collections/{id}/books {bookIds}` (idempotent).

## Networking

- Plain `http://localhost` needs `NSAllowsLocalNetworking` in the app's Info.plist (`Config/Octavo-Info.plist`); it covers `localhost` and `.local` names. Plain-http servers on a LAN IP or a remote host need more. That's an open owner decision.
- On a real device, LAN servers also trigger the Local Network permission prompt (`NSLocalNetworkUsageDescription`). Loopback in the simulator doesn't.

## Side note

BookOrbit has its own iOS app. Its v3.6.0 release notes mention "native support for iPhone Duo".
