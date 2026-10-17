# Web client feasibility: the core in a browser

Status: research note from a spike, 2026-10-17, revised after two reviews the same day. It
is not a decision and does not change v1 scope ([0009](decisions/0009-v1-scope.md)). The path
chosen from it is the roadmap epic
[#309](https://github.com/samtak-svf/icelandic-messenger/issues/309): a social platform with
an encrypted messenger, web first as a plain web app whose sign-in makes a session, not an
MLS device, and encrypted chat in the browser last. Each step there needs its own record
before code.

## Question

Could a browser be a messaging client today, with the same end-to-end encryption as the
apps? If so, what stands in the way? The social-platform story lists "a browser and
native client exchange encrypted messages" as its first experiment. Everything web in
that story rests on the answer.

## Short answer

**The engine travels.** The core compiles to wasm32 and its MLS interoperates with the
shipped core, so a browser can be an ordinary MLS device under
[0014](decisions/0014-accounts-devices-and-auth.md). The seams around the engine (clock,
files, transport, store connections, socket auth) are known engineering.

**The real blocker is product, not code.** Every E2EE browser client in production rests
on a history and device-lifecycle model that this project has deliberately left out of v1
([0006](decisions/0006-device-local-history.md)). The model has to be chosen before web
code is written. Choosing it costs decision records, not an architecture change.

## What was measured

All on `wasm32-unknown-unknown`, with the toolchain pinned in `core/rust-toolchain.toml`,
openmls 0.9.0, and rusqlite 0.40.2.

| Check                                           | Result                                                                                                                                                                                                                                                                      |
| ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cargo check` envelope, mls, store, client, ffi | All compile once `core/mls/Cargo.toml` gains target-only features: getrandom 0.2 `js` (via p256), getrandom 0.4 `wasm_js`, openmls `js`. Without them, mls fails on getrandom. store also needs `clang` on the build machine for sqlite-wasm-rs. No `RUSTFLAGS` are needed. |
| Shipped graph on Android, iOS, Linux            | `cargo tree -p spjall-ffi -e normal` before and after: identical for `aarch64-linux-android`, `aarch64-apple-ios`, and `x86_64-unknown-linux-gnu`.                                                                                                                          |
| MLS interop (`core/web-spike/run.sh`)           | spjall-mls in wasm makes a KeyPackage. A native spjall-mls with its SQLCipher store creates a group and adds it. The wasm side joins from the Welcome. A text envelope crosses each way, and each side sees the right sender (`b/d2`, `a/d1`).                              |
| Store on plain wasm SQLite                      | **The file is plaintext.** On wasm32, rusqlite drops `libsqlite3-sys` for `sqlite-wasm-rs`, and `bundled-sqlcipher-vendored-openssl` silently does nothing. SQLite ignores `PRAGMA key`, the file starts with `SQLite format 3\0`, and a wrong key opens it.                |
| Store with `sqlite-wasm-rs/sqlite3mc`           | **The file is encrypted, and a wrong key is refused.** The `Store::open` and `connect` code is unchanged, with the same `PRAGMA key = "x'…'"` (SQLite3 Multiple Ciphers).                                                                                                   |
| `std::fs::write`                                | Returns `operation not supported on this platform`.                                                                                                                                                                                                                         |
| `SystemTime::now`, `Instant::now`               | Trap (`RuntimeError: unreachable`). wasm32 aborts on a panic, so a trap ends the module instance.                                                                                                                                                                           |
| Size                                            | 3.75 MB wasm with sqlite3mc and no `wasm-opt`, 1.33 MB gzipped (3.45 MB without sqlite3mc).                                                                                                                                                                                 |

Reproduce from a checkout:

```bash
rustup target add wasm32-unknown-unknown
cargo install wasm-bindgen-cli --version 0.2.129 --locked   # the version Cargo.lock pins
sudo dnf install clang                                      # sqlite-wasm-rs builds SQLite with it
cd core && ./web-spike/run.sh
```

`run.sh` builds the browser side twice, once without sqlite3mc and once with it. It
asserts the plaintext and wrong-key results above for each build. It works with or
without `CARGO_TARGET_DIR`. The output of `wasm-bindgen --target nodejs` is CommonJS, so
the script marks the package directory as such. Otherwise the repo's root `package.json`
would make Node load the output as an ES module.

## What other E2EE messengers do in a browser

Many messengers have a web client, but each one gives up something. They solve the
problem in one of four ways:

| Product          | Browser E2EE                                                                                                | How history and keys reach the browser                                                                                                                                                                                                                                                                                                                                                                                                                             |
| ---------------- | ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Discord          | Text: no. Calls: yes ([DAVE](https://discord.com/blog/meet-dave-e2ee-for-audio-video), MLS in every client) | The browser has no encrypted history to keep. Call keys are ephemeral.                                                                                                                                                                                                                                                                                                                                                                                             |
| Messenger        | Yes, by default since Dec 2023                                                                              | [Labyrinth](https://engineering.fb.com/wp-content/uploads/2023/12/theLabyrintHencryptedMessagestorageProtocol_12-6-2023.pdf): server-side encrypted history. A new device restores it with a PIN (HSM-backed) or a code from another device. Browsers are treated as "ephemeral devices". The JavaScript is checked by [Code Verify](https://engineering.fb.com/2022/03/10/security/code-verify/).                                                                 |
| WhatsApp Web     | Yes                                                                                                         | Since 2021 the browser is a linked device with its own identity. The phone transfers history to it, encrypted to it, and the link expires after inactivity. Also Code Verify.                                                                                                                                                                                                                                                                                      |
| Signal           | No browser client, by choice                                                                                | An Electron desktop app linked by QR code. Since 2025 the phone [transfers history](https://signal.org/blog/a-synchronized-start-for-linked-devices/) to a new linked device, and opt-in [Secure Backups](https://signal.org/blog/introducing-secure-backups/) keep an encrypted copy on the server. The desktop's SQLCipher key is behind the OS keychain since 2024 ([write-up](https://cryptographycaffe.sandboxaq.com/posts/protecting-signal-desktop-keys/)). |
| Wire             | Yes (MLS, Rust core-crypto in wasm)                                                                         | Records in IndexedDB, encrypted with a WebCrypto key; this note's SQLite-in-OPFS is a different store (see core point 2). [History is lost when browser data is cleared](https://support.wire.com/hc/en-us/articles/360000377138). The only mitigation is a manual backup file.                                                                                                                                                                                    |
| Element / Matrix | Yes (vodozemac in wasm)                                                                                     | Crypto state in IndexedDB. A new login must be verified. It reads old messages only through a server-side encrypted key backup with a recovery key ([docs](https://ems-docs.element.io/books/element-support/page/verify-new-login)).                                                                                                                                                                                                                              |

The four patterns:

1. no encrypted history in the browser (Discord text);
2. a second key system that holds encrypted history on the server (Messenger, Matrix);
3. a browser linked to a primary phone that transfers history to it (WhatsApp, Signal
   desktop);
4. accepted loss, plus a manual backup (Wire).

No one ships "history is device-local, full stop" in a browser and is satisfied with it.
The hard part of a browser client is persistence and code delivery, not MLS.

## What it means for this project

### In the core

1. **A store must refuse to be plaintext.** Today a wasm build would ship history
   unencrypted with no error. `connect` (`core/store/src/lib.rs:631-640`) runs `PRAGMA key`
   and checks nothing after it. It must confirm the cipher is active (SQLCipher answers
   `PRAGMA cipher_version`; sqlite3mc has its own probe) and fail otherwise. The check costs
   nothing on the apps, and it closes the same hole in any future build that loses
   SQLCipher. Worth doing now.
2. **Encryption at rest: sqlite3mc.** It keeps the store's code and its one-transaction
   decrypt-and-store ([0016](decisions/0016-one-encrypted-store-owned-by-the-core.md)).
   The cipher scheme would differ from the apps, but no file ever moves between a browser
   and a phone. The alternative is what Wire and Element ship: records in IndexedDB,
   encrypted with a non-extractable WebCrypto key. IndexedDB serves several tabs and needs
   no C toolchain, but it gives up the store's SQL and its transactions. Which one wins is
   measured in a real browser before the record
   ([#297](https://github.com/samtak-svf/icelandic-messenger/issues/297)).
3. **One thread, one connection.** sqlite-wasm-rs offers OPFS (`sahpool`, dedicated Worker
   only) and IndexedDB VFSes, and none of them supports several connections. `Store::reader`
   opens a second connection
   ([0056](decisions/0056-a-read-never-waits-for-the-network.md)). The core would also run
   on a single Worker thread, so a blocking `sync()` would hold every `View` read
   (`core/client/src/lib.rs:1023`) behind the network. That is the slow list 0056 fixed on
   the apps. A web client must either make the core async or keep a UI-side mirror of the
   lists, which 0056 rules out for the apps. **This is the first engineering decision for
   web, not a detail.**
4. **One clock, agreeing with SQL.** `spjall-client` reads `SystemTime` and `Instant`
   directly (`core/client/src/lib.rs:365`, `:1007`). A `Clock` owned by `Client` fixes
   that, and `web-time` is already in the wasm graph through openmls. The `UNEXPIRED` views
   use SQLite's own `unixepoch()` (`core/store/src/lib.rs:605-609`), as does `migrate()`
   (`:659`), which the VFS serves on wasm. The injected clock must agree with it, or expiry differs between read and purge.
5. **Files become bytes.** `Transport::upload` and `download` take `&Path`
   (`core/client/src/api.rs:62-72`), and `media.rs`, `photo.rs` and `account.rs:624` use
   `std::fs`. `Client::forward` passes a media file's path on (`core/client/src/forward.rs:47`),
   and `Client::open` derives the media directory from the store's path. On the web these must become bytes or an OPFS handle behind a seam. This is the
   largest core change.
6. **Transport.** `Transport` is a blocking callback. A dedicated Worker could implement it
   with synchronous `XMLHttpRequest`, but given point 3 that is a spike convenience, not a
   design.
7. **Several tabs.** Only one opener per OPFS database is allowed, and Chrome for Android
   has no SharedWorker. A second tab needs a lock and a handover. The social story lists
   this as an experiment, and it is not measured here.

### The device lifecycle

- **A lost browser leaves a ghost device.** Safari deletes all script-writable storage,
  OPFS included, after 7 days without a visit
  ([WebKit](https://bugs.webkit.org/show_bug.cgi?id=276998)). Clearing site data has the
  same effect. The dead device keeps its D1 row, and under
  [0028](decisions/0028-removing-a-device-from-its-groups.md) its leaf stays in every
  group until a sibling device revokes it. Members keep encrypting to it, and the Inbox
  keeps a cursor for it. A non-phone device needs server-side inactivity expiry (Signal
  [unlinks](https://support.signal.org/hc/en-us/articles/360007320551) a linked device
  after 45 days, WhatsApp after 14).
- **History.** Under 0006 a new device sees only future messages. In a browser that means
  an empty client after every eviction. The cheapest of the four patterns that keeps
  history off the server is the linked device: the phone transfers history to the new
  device, encrypted to its MLS key. Signal shipped exactly this in 2025. The same transfer is
  also the "new phone" feature that 0006 leaves users without today.

### Key custody and code delivery

A browser has no Keystore or Keychain. The best available option is a non-extractable
WebCrypto AES key in IndexedDB that wraps the 32 store bytes. A copied OPFS file is then
useless without that origin's IndexedDB, but script running in the origin can still use
the key. Other options:

- a passphrase-derived key: stronger, but the user must type it on every start;
- history held only in memory.

**Code delivery is the deeper weakness.** On every visit the server can send one user
different JavaScript, and that server would be the same Worker that relays the
ciphertext. This is why Signal has no browser client and why Meta built Code Verify. No
cheap fix exists (reproducible builds, SRI, a published hash and a verifying extension
each help only partly). A web record must say plainly that a browser is a weaker device
than a phone, on both counts, and require a strict CSP and no third-party script.

### In the backend

- **Session is not device.** Today signing in creates an MLS device: `POST /v1/devices`
  turns an OIDC code into a device row with `device_key BLOB NOT NULL`
  (`backend/migrations/0001_accounts.sql:14-24`), and every `/v1/*` route needs that
  device's bearer token (`backend/src/app.ts:66`, `:107-111`). A browser that signs in only
  to read a community would join every group and become a ghost device on eviction. The
  web therefore signs in to a **session**: a D1 row referenced by an HttpOnly, Secure,
  SameSite=Lax cookie, with an explicit Origin check on every state-changing request. Page
  script never holds a bearer token. The native apps keep 0014's device token.
- **Sockets.** A browser `WebSocket` cannot send `Authorization`, but it does send a
  same-origin cookie on the upgrade. A session needs no socket ticket. Whether a linked
  browser device later authenticates its socket by its session or by a ticket for its
  device is part of the linked-device record.
- **Hosting.** Serving the app from the Worker's own host avoids CORS and keeps the cookie
  first-party. The link host already shares the Worker (`backend/src/app.ts:476`). A web
  host is a frozen-id change and a record.
- **Platform `web`.** `android` and `ios` are written out in zod
  (`backend/src/api/devices.ts:53,276`, `backend/src/api/health.ts:11`), in the version
  header and its comparison (`backend/src/client-version.ts:9,35`), in the env types
  (`backend/src/env/index.ts:28`), in the D1 CHECK constraint
  (`backend/migrations/0001_accounts.sql:17`) and in the core (`core/client/src/api.rs:284-287`).
  They should come from one list before `web` joins it
  ([0030](decisions/0030-client-version-floor.md)).
- **Contract.** A TypeScript client is generated from `api/openapi.json`, like the Kotlin
  frames ([0005](decisions/0005-contract-zod-openapi-generated-clients.md)).
- **Push.** Web Push (VAPID) is new, so the first web slice has none.

### Alternatives to a browser

- **A desktop app (Tauri) as a linked device.** The native core runs unchanged: SQLCipher,
  the blocking transport, `std::fs` and `SystemTime` all work, and the OS keychain holds the
  key. For a messenger alone it would be the cheapest non-phone client. For a social
  platform it is a detour: it adds a third release pipeline and gives no links to share,
  and a UI built on the native core's two connections would hide the browser's
  one-connection constraint until the move to the web.
- **A PWA** is a way to deliver the web client, not an alternative to it. It gives
  installability, Web Push on iOS, and exemption from Safari's 7-day cap.
- **A phone-tethered proxy** (WhatsApp in 2015) needs the phone online, which is a dead
  end.

### For the maintainer, not an agent

- Register an `https` redirect URI for the web client with Kenni, and a Google web client.
- Any new host or DNS.
- The records themselves.

## The chosen path

The maintainer chose the social platform with an encrypted messenger, web first. The
roadmap is [#309](https://github.com/samtak-svf/icelandic-messenger/issues/309). In short:

1. **Decisions:** the product scope (amends 0009 and 0044); account, login identity,
   session and device as four things (amends 0014); the web host; communities and
   moderation; and, last, non-phone devices as linked devices (amends 0006).
2. **Groundwork beside the closed beta:** the core's web guards
   ([#265](https://github.com/samtak-svf/icelandic-messenger/pull/265)), platforms from one
   list, backend modules with enforced boundaries, and a measured D1 social workload.
3. **Sessions:** a `sessions` table, server-handled web sign-in, revocation, and `web` in
   the client-version contract.
4. **The web shell**, served by the same Worker, consuming the generated contract and
   brand.
5. **The first social slice** after the open beta, web first; then news.
6. **Encrypted chat in the browser last:** the storage measurement, the async core
   (the first engineering decision under core point 3), enrolment approved by a phone, and
   history from a sibling device.

**Expensive to reverse, so worth knowing now:**

- **The blocking `Transport`.** Leave it alone, because the apps and 0056 rest on it. The
  async-core decision comes before any browser chat.
- **History must stay exportable from a device.** Nothing today prevents that. Keep it so;
  the sibling transfer depends on it.

## Sketch for the linked-device record

> **A non-phone device is a linked device** (draft)
>
> - A desktop or browser client is linked from a signed-in session and approved on a phone,
>   as its own MLS device under 0014. History reaches it from a sibling device, encrypted to
>   it, never as a server-side backup.
> - A non-phone device expires after a period without use, and the server removes its
>   leaves as under 0028.
> - In a browser it runs the wasm core in a Worker after the async-core decision, on the
>   store the browser measurement chose, with a store that refuses to be plaintext and a
>   key wrapped by a non-extractable WebCrypto key. Every script carries SRI, and build
>   hashes are published.
> - Rules out: a server-side key or history backup, a third-party script on the app's
>   origin, and MLS enrolment as a side effect of signing in.
