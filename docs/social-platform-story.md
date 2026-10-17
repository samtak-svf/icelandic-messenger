# Story: Prepare the messenger for a social network and future platform

Status: proposed; issue-ready draft. This story does not supersede accepted decision records.

## User story

As a member of the Icelandic community, I want one account across conversations,
communities, social feeds and Skrapi news on web and native mobile, so that I can
discover information, participate in discussions and communicate privately in one product.

As a 2–3-person side-project team, we need a small, understandable architecture
that supports these features without creating unnecessary infrastructure or release work.

## Goal

Evolve the existing project into a modular application: one repository, one backend
deployment, one primary application database initially, three client interfaces,
and the existing encrypted-messaging core. Prepare for additional first-party
features through clear boundaries rather than a general plugin framework.

This is an umbrella story. The implementation slices below should become smaller
issues, each with independently verifiable completion criteria.

## Proposed architecture

- Keep native Android (Kotlin/Compose) and iOS (SwiftUI), and add a web client.
- Use React, TypeScript and Vite as the proposed web baseline, subject to team agreement.
- Serve web assets and the API from the existing Worker deployment where practical.
- Keep one modular backend with identity, profiles, communities, social content,
  news, messaging, notifications and moderation responsibilities.
- Retain the Rust core for MLS, messaging keys, encrypted local history and message processing.
- Keep social business rules on the backend, with contract-checked client adapters.
- Preserve Zod as the HTTP schema source and generated OpenAPI as the shared contract.
- Keep existing native, API, brand and identifier paths; avoid a cosmetic repository migration.
- Enforce module import boundaries and ownership of table writes. Permit documented
  cross-module read queries where feeds require efficient joins.

### Incremental layout

```text
android/                       Existing native client
ios/                           Existing native client
web/                           Web shell, features, components and API adapter
core/                          Existing Rust messaging engine
backend/src/
  identity/                    Accounts, login identities and application sessions
  modules/
    messaging/
    profiles/
    communities/
    social/                    Posts, comments, reactions, follows and feed queries
    news/
    notifications/
    moderation/
  integrations/skrapi/
  jobs/                        Bounded, retryable background tasks
  env/                         Existing controlled infrastructure access
  app.ts                       Composition and route registration
api/                           Generated contracts and client artifacts
brand/                         Shared strings and tokens, extended for web
identifiers/                   Frozen resource identifiers
docs/                          Architecture and decision records
```

Create modules when code moves or functionality arrives, not as empty scaffolding.

## Core design requirements

### Identity and authorization

- Separate an account, external login identity, application session and cryptographic
  messaging device. Social access must not require MLS-device enrollment.
- Preserve existing native authentication during a compatible transition.
- Prefer server-handled web sign-in and secure HttpOnly session cookies, with explicit
  CSRF protection and origin validation.
- Define session revocation, messaging-device revocation and account deletion separately.
- Enforce community permissions, blocks and moderation restrictions on the backend,
  including direct URLs, media, shared cards and notifications.

### Communities and social content

- Start with profiles, follows, text/image posts, comments, reactions and chronological feeds.
- Initially support discoverable open communities readable by signed-in members, and
  discoverable private communities whose content requires approved membership.
- Treat these audience defaults as proposals to settle in the scope decision.
- Keep hosted community discussions separate from MLS conversations. Access-controlled
  community content is not end-to-end encrypted.
- Include reporting, group/platform moderation and an action history in the first social beta.
- Use stable typed resource references for sharing and navigation; resolving a reference
  must recheck access, removal and moderation state.

### Storage and infrastructure

- Retain EU-jurisdiction D1, R2 and Durable Objects under the existing infrastructure rules.
- Keep one primary D1 database initially, conditional on a realistic social-workload experiment.
- Preserve native device-local encrypted chat history and the existing messaging delivery model.
- Give social media separate validation, access and retention handling from encrypted attachments.
- Introduce a database-backed outbox/jobs table only for concrete retryable work.
  Persist each job atomically with its originating change where applicable, and make consumers
  idempotent. Do not assume atomic transactions across D1 and Durable Objects.
- Use bounded scheduled processing initially; respect the existing prohibition on Cloudflare Queues.
- Preserve the distinction between durable EU storage and processing on Cloudflare's network.

### Skrapi

- Integrate through one backend adapter rather than exposing upstream credentials to clients.
- Store stable internal article references mapped to Skrapi workspace and article IDs.
- Cache permitted preview metadata, canonical source URLs and freshness information.
- Initially link to publishers; full-text/image republication requires appropriate rights.
- Allow separate discussions of the same article in different communities.
- Existing posts and core social operations must remain usable during an upstream outage.

## Implementation slices and acceptance criteria

### 1. Scope and module boundaries

- [ ] A maintainer-approved decision record amends the messenger-only scope, especially
  decisions 0009 and 0044, and records affected client-engine, identity and media decisions.
- [ ] Module ownership, allowed dependencies and the hosting model are documented.
- [ ] Existing backend functionality is extracted incrementally with existing checks passing.
- [ ] Import-boundary checks prevent access to module internals.

### 2. Browser messaging and storage experiments

- [ ] Using pinned dependencies, a browser and native client exchange encrypted messages.
- [ ] The experiment covers reload persistence, multiple-tab coordination, device revocation
  and local-storage loss; limitations and the implementation recommendation are recorded.
- [ ] New-device history expectations are decided explicitly, preserving decision 0006
  unless amended through a separate approved record.
- [ ] A repeatable D1 experiment measures representative feeds, access filtering, writes,
  notification work and projected table/index growth against agreed usage assumptions.
- [ ] The storage recommendation records measured results and D1's 10 GB per-database limit.

### 3. Web and session foundation

- [ ] Web sign-in supports social access without cryptographic-device enrollment.
- [ ] Session handling, CSRF/origin protections and revocation have targeted verification.
- [ ] Web consumes generated API types and generated brand strings/tokens.
- [ ] Existing native clients remain compatible during the authentication transition.
- [ ] Web client-version handling is explicitly supported by the backend contract.

### 4. First complete social slice

- [ ] A member can join a community, publish a post, comment and receive a social notification.
- [ ] A member can report content; an authorized moderator can review and act on the report.
- [ ] Tests verify unauthorized access is rejected through list routes, direct routes,
  media access and shared references, including blocks and private-community membership.
- [ ] The slice is delivered on a lead client, with tracked Android, iOS and web follow-ups.
- [ ] Social notifications preserve the existing encrypted-chat push privacy contract.

### 5. News integration and operational readiness

- [ ] Members can browse Skrapi article cards and share references into community discussions.
- [ ] Cached article cards remain usable during a simulated upstream outage.
- [ ] Retryable jobs handle duplicate execution and expose terminal failures.
- [ ] Deployment, migration, restore and rollback procedures are documented.
- [ ] Monitoring respects the existing prohibition on personal information in logs.

## Out of scope for this story

- Native-client rewrite or replacement with a cross-platform UI framework.
- Microservices, database-per-module deployment or speculative sharding.
- Third-party mini-app execution, plugin runtime or universal UI language.
- Algorithmic feeds, payments, marketplace, bookings or events.
- Mandatory simultaneous release of every feature on all three clients.
- Full public-web indexing and server-rendered public pages unless separately prioritized.

## Research informing the proposal

- [Monolith First](https://martinfowler.com/bliki/MonolithFirst.html): evolve boundaries
  before paying the operational cost of separate services.
- [OpenMLS upstream](https://github.com/openmls/openmls): WASM compilation exists, but
  browser suitability must be validated against the project's pinned versions and storage needs.
- [OAuth for browser applications](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-browser-based-apps):
  browser authentication has different constraints from native applications.
- [D1 limits](https://developers.cloudflare.com/d1/platform/limits/): per-database storage
  limits and single-threaded execution require workload-specific validation.
- [Durable Object data location](https://developers.cloudflare.com/durable-objects/reference/data-location/):
  jurisdiction restrictions differ from location hints and Worker processing locations.
- [Transactional outbox](https://microservices.io/patterns/data/transactional-outbox.html):
  atomic recording and idempotent delivery for reliable asynchronous work.
