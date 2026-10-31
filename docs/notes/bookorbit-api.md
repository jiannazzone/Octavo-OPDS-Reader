# BookOrbit API: what the spike learned (v3.6.0)

Spike 1b (`BookOrbitClient` in OctavoKit) and 2a (sync), measured against the local server in `dev/bookorbit/` (start, seed and test accounts are in its README). These are observed behaviours of BookOrbit **v3.6.0**. The API changes between versions, so re-check against a live server when upgrading. Nothing here is copied from BookOrbit's code (AGPL); it comes from calling the API.

## Auth

- **Native mode (v3.0+):** `POST auth/login {username, password, clientKind: "native", deviceLabel}` returns `{accessToken, accessTokenExpiresAt, refreshToken, refreshTokenExpiresAt, sessionId, user}` and sets **no cookies**. Refresh with `POST auth/refresh {refreshToken}`, which returns the same token fields.
- **Web mode (no `clientKind`, and the only mode before 3.0):** the body has `{accessToken, accessTokenExpiresAt, sessionId, user}` and the refresh token is a cookie (`Path=/api/v1/auth; HttpOnly; SameSite=Strict`, `Secure` only over HTTPS). BookOrbit's Android client still uses this mode.
- Access tokens last 15 minutes, refresh tokens 7 days. **Refresh tokens rotate on every refresh** (30 s grace for concurrent reuse), so store the new one every time.
- **Login is rate-limited to 5 per minute per IP** (HTTP 429).
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
- Fixed-layout books restore by fraction, not CFI.

## Library and files

- `GET collections/{id}/books?page=0&size=50[&q=…]` returns `{items, total, page, size}`. Items carry `authors`, `files: [{id, format, role, sizeBytes, mediaOverlay}]`, `readingProgress` (0–100) and a `readStatus` object.
- `GET books/{id}` adds `filename`, `absolutePath`, `fileHash` and `contentVersion` to each file.
- `GET books/files/{id}/serve` returns the file (`application/epub+zip`) with an ETag, `Accept-Ranges: bytes` and a Content-Disposition filename. It is byte-identical to the upload.
- The web reader is at `/read/{bookId}/{fileId}?format=epub`. Opening a book there writes progress for that file.

## Seeding (used by `dev/bookorbit/seed.sh`)

`POST auth/setup` (header `x-setup-token`), `POST libraries {name, icon, folders}`, `POST libraries/{id}/upload` (multipart `file`; 409 `UPLOAD_DESTINATION_CONFLICT` on a duplicate), `POST collections {name, icon}`, `POST collections/{id}/books {bookIds}` (idempotent).

## Networking

- Plain `http://localhost` needs `NSAllowsLocalNetworking` in the app's Info.plist (`Config/Octavo-Info.plist`); it covers `localhost` and `.local` names. Plain-http servers on a LAN IP or a remote host need more. That's an open owner decision.
- On a real device, LAN servers also trigger the Local Network permission prompt (`NSLocalNetworkUsageDescription`). Loopback in the simulator doesn't.

## Side note

BookOrbit has its own iOS app. Its v3.6.0 release notes mention "native support for iPhone Duo".
