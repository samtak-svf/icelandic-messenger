# Web client feasibility: the core in a browser

Status: research note from a spike, 2026-10-17. Not a decision. Nothing here changes v1
scope ([0009](decisions/0009-v1-scope.md)). A web client needs its own record before any
product code. The draft at the end is a starting point for that record.

## Question

Could a browser be a messaging client today, with the same end-to-end encryption as the
apps? If so, what stands in the way? The social-platform story lists "a browser and
native client exchange encrypted messages" as its first experiment. Everything web in
that story rests on the answer.

## What was measured

All on `wasm32-unknown-unknown`, with the toolchain pinned in `core/rust-toolchain.toml`,
openmls 0.9.0, and rusqlite 0.40.2.

| Check                                           | Result                                                                                                                                                                                                                                                       |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `cargo check` envelope, mls, store, client, ffi | All compile once `core/mls/Cargo.toml` gains target-only features: getrandom 0.2 `js` (via p256), getrandom 0.4 `wasm_js`, openmls `js`. Without them, mls fails on getrandom. store also needs `clang` on the build machine for sqlite-wasm-rs.             |
| Shipped graph on Android, iOS, Linux            | `cargo tree -p spjall-ffi -e normal` before and after: identical for `aarch64-linux-android`, `aarch64-apple-ios`, and `x86_64-unknown-linux-gnu`.                                                                                                           |
| MLS interop (`core/web-spike/run.sh`)           | spjall-mls in wasm makes a KeyPackage. A native spjall-mls with its SQLCipher store creates a group and adds it. The wasm side joins from the Welcome. A text envelope crosses each way, and each side sees the right sender (`b/d2`, `a/d1`).               |
| Store on plain wasm SQLite                      | **The file is plaintext.** On wasm32, rusqlite drops `libsqlite3-sys` for `sqlite-wasm-rs`, and `bundled-sqlcipher-vendored-openssl` silently does nothing. SQLite ignores `PRAGMA key`, the file starts with `SQLite format 3\0`, and a wrong key opens it. |
| Store with `sqlite-wasm-rs/sqlite3mc`           | **The file is encrypted, and a wrong key is refused.** The `Store::open` and `connect` code is unchanged, with the same `PRAGMA key = "x'…'"` (SQLite3 Multiple Ciphers).                                                                                    |
| `std::fs::write`                                | Returns `operation not supported on this platform`.                                                                                                                                                                                                          |
| `SystemTime::now`, `Instant::now`               | Trap (`RuntimeError: unreachable`). wasm32 aborts on a panic, so a trap ends the module instance.                                                                                                                                                            |
| Size                                            | 3.75 MB wasm with sqlite3mc and no `wasm-opt`, 1.33 MB gzipped (3.45 MB without sqlite3mc).                                                                                                                                                                  |

Reproduce from a checkout:

```bash
rustup target add wasm32-unknown-unknown
cargo install wasm-bindgen-cli --version 0.2.129 --locked   # the version Cargo.lock pins
sudo dnf install clang                                      # sqlite-wasm-rs builds SQLite with it
cd core && ./web-spike/run.sh
```

`run.sh` builds the browser side twice, once without sqlite3mc and once with it. It
asserts the plaintext and wrong-key results above for each build.

## What it means

**The engine travels.** MLS, the envelope and the store's SQL run in a browser without
changes to their logic, and the result interoperates with the shipped core. The browser is
an ordinary MLS device under [0014](decisions/0014-accounts-devices-and-auth.md). It is not
a second protocol. The open questions are the platform seams around the engine.

### In the core

1. **A store must refuse to be plaintext.** Today a wasm build would ship history
   unencrypted with no error. Before any wasm store ships, `connect` in
   `core/store/src/lib.rs` must check that the cipher is active (SQLCipher answers
   `PRAGMA cipher_version`; sqlite3mc has its own probe) and fail otherwise. The check
   costs nothing on the apps and closes the same hole for any future build that loses
   SQLCipher.
2. **Encryption at rest: sqlite3mc.** It keeps the store's code and its one-transaction
   decrypt-and-store ([0016](decisions/0016-one-encrypted-store-owned-by-the-core.md)).
   The cipher scheme would differ from the apps, but no file ever moves between a browser
   and a phone.
3. **Persistence.** sqlite-wasm-rs offers OPFS (`sahpool`, dedicated Worker only) and
   IndexedDB VFSes. Its README says none of them supports several connections.
   `Store::reader` opens a second connection
   ([0056](decisions/0056-a-read-never-waits-for-the-network.md)). The web build needs reads
   on the writer's one connection, which is a store change. This is not measured here.
4. **A clock seam.** `spjall-client` reads `SystemTime` and `Instant` directly
   (`core/client/src/lib.rs:365`, `:1007`). It needs one injected clock, or `web-time` on
   wasm32.
5. **Files become bytes.** `Transport::upload` and `download` take paths, and
   `media.rs`, `photo.rs` and `account.rs` use `std::fs`. On the web these must become
   bytes or an OPFS handle behind a seam. This is the largest core change.
6. **The transport stays blocking, in a Worker.** `Transport` is a blocking callback
   (`core/client/src/api.rs:62-70`). A dedicated Worker can implement it with synchronous
   `XMLHttpRequest`, which browsers still allow in workers, so the core does not have to
   become async. This is not measured here; it is the next spike if the record goes ahead.

### Key custody (a decision, not engineering)

A browser has no Keystore or Keychain. The best available option is a non-extractable
WebCrypto AES key in IndexedDB that wraps the 32 store bytes. A copied OPFS file is then
useless without that origin's IndexedDB, but script running in the origin can still use
the key. So the web client needs a strict CSP and no third-party script, and the record
must say plainly that a browser is a weaker device than a phone. Other options:

- a passphrase-derived key: stronger, but the user must type it on every start;
- history held only in memory, so a closed tab is a new device under
  [0006](decisions/0006-device-local-history.md).

Clearing site data always makes the browser a new device. `navigator.storage.persist()`
should be requested.

### In the backend

- **Auth.** A browser `WebSocket` cannot send `Authorization` (`backend/src/app.ts:66`,
  `:109`). Two ways:
  - a short-lived, single-use socket ticket from an authenticated REST call, which keeps
    the bearer device token of 0014;
  - an HttpOnly cookie session with CSRF and origin checks, as the social story proposes.

  The ticket is the smaller change, and it keeps one session model for every client.

- **Hosting.** Serving the app from the Worker's own host, with a static-assets binding,
  avoids CORS. `tooling/jurisdiction-check.mjs` and the frozen hosts in
  `identifiers/ids.json` would need updating. A separate host is a frozen-id change and a
  record.
- **Client version.** `Spjall-Client` and `/health` know only `android` and `ios`
  ([0030](decisions/0030-client-version-floor.md)), so a `web` platform has to be added.
- **Contract.** A TypeScript client would be generated from `api/openapi.json` (an
  amendment to [0005](decisions/0005-contract-zod-openapi-generated-clients.md)).
- **Push.** Web Push (VAPID) is new, so the first slice should have none: messages
  arrive while the tab is open.

### For the maintainer, not an agent

- Register an `https` redirect URI for the web client with Kenni. The Google web client
  id already exists.
- Any new host or DNS.
- The scope record itself.

## Suggested order, one reviewable PR each

1. A record that brings a web client into scope, or rules it out for v1 (the draft
   below). Nothing else starts without it.
2. The fail-closed cipher check in `connect`, with a test (useful on its own, today).
3. Core seams: clock, files as bytes, reads on one connection, and a `wasm32` CI job that
   builds and runs `web-spike/run.sh`. The apps must stay byte-identical, which
   `cargo tree` and `check:core` show.
4. A spike of the sync-XHR transport in a dedicated Worker, plus OPFS persistence across a
   reload.
5. Backend: the `web` platform, the socket ticket, static hosting and the https redirect.
6. The web shell: sign-in, the conversation list and text conversations. Media, photos,
   location and the rest follow, one decision at a time, as on the apps.

Steps 2 and 3 change the core the apps ship, so they need a core release. Step 5 changes
the contract additively.

## Draft for the scope record

> **0060. A browser is a device: a web client after the closed beta** (draft)
>
> - The web client is a messaging client: the core compiled to wasm32 in a dedicated
>   Worker, an MLS device under 0014, history device-local under 0006.
> - Its store is the core's store on sqlite3mc in OPFS. `connect` refuses any connection
>   whose cipher is not active. The key is wrapped by a non-extractable WebCrypto key.
>   A browser is a weaker device than a phone, and the app says so.
> - Served from the Worker's host, same-origin. A socket ticket instead of a cookie
>   session. Platform `web` in the version floor. No push in the first slice.
> - Rules out: a web client without end-to-end encryption, a server-side key, a
>   third-party script on the app's origin, and a web build before the closed beta's UX
>   pass is done.
