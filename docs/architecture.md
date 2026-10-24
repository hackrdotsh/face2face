# Architecture and next steps

## Current boundaries

The iPhone SwiftUI app lives in `apps/ios/Face2Face`. Its dependency-free Swift
package, `Face2FaceCore`, owns URL validation, Codable response models, HTTP
requests, and session storage. The app owns presentation and form state on the
main actor. No backend or database code is bundled into the app.

The app calls the Hono Worker in `apps/api`. Better Auth owns credentials and
sessions in D1 through Drizzle. Its bearer plugin requires signed tokens. The
Swift client stores the `set-auth-token` response header in Keychain and sends
it as an Authorization header. It never treats the unsigned JSON token as the
credential. Keychain entries are scoped to each normalized API URL, and the HTTP
transport does not follow redirects with credentials.

`GET /health` checks the Worker response, not database readiness. `/api/auth/*`
handles authentication. `GET /api/me` returns the authenticated person's ID and
name. `GET /api/coordinator` calls that person's SQLite-backed Durable Object.
Neither protected route accepts a user ID from the caller.

Swift core tests run on Linux and Mac. Keychain and SwiftUI need Apple's SDKs;
the macOS CI job builds the simulator target. Physical-device behavior still
requires Xcode and an iPhone. Generated projects and local build output are ignored.

## Proximity is a separate milestone

Debug builds retain the account-free Stage 1 Bluetooth test and add a separate
Connected test. Stage 2 issues expiring server-side discovery sessions, exchanges opaque
UUID tokens through the same Bluetooth protocol, and submits authenticated observations.
Names become available only after reciprocal reports from the same two active sessions.
The server deduplicates encounters by account pair and labels them client-reported Bluetooth
observations; they do not prove identity or proximity. See the [Stage 2 contract](streetpass-stage2.md).

Discovery sessions are bound to the initiating auth session. Start replaces the account's
previous session; Stop and sign-out revoke it. Tokens are stored hashed on the server and
held in memory on the phone. Persistent signed bearer credentials remain in Keychain.
No auth credential is included in the radio payload. The native client freezes its
credential for each run, bounds upload retries, rotates tokens, and stops at safe expiry.

The two foreground experiments stop on backgrounding or closing their screen. A separate
[Stage 3 Pocket experiment](streetpass-stage3.md) opts into five minutes of anonymous
background radio requests and OS-driven state restoration. Only non-secret consent metadata
is persisted; token exchange checks expiry on every resumed operation. It does not resolve
accounts or upload observations. A process-wide owner prevents overlapping radio tests.

A separate [Stage 4 Walk experiment](streetpass-stage4.md) opts into a five-minute
authenticated walk. It holds a captured bearer credential only in memory and can attempt
bounded, event-driven background uploads. It never renews locators or polls history in the
background, never extends the original consent window, and does not restore signed walks
after process death. Names are hidden until foreground account checks and history fetches
succeed. Locked-screen operation remains a hardware question.
The [Stage 5 live Walk flow](streetpass-stage5.md) tracks a pre-start history baseline
and the new lease's server timestamp so historical records cannot trigger a fresh reveal.
The server retains the reciprocal-report rule; presentation never infers a match from radio
activity or an accepted one-sided observation alone.

Release builds omit the diagnostic screens, native Bluetooth transport, permission, and
background modes. Geolocation, interest matching, friend requests, and notifications are not
implemented in this discovery slice.
Physical-device validation remains pending. Follow the [Stage 1 guide](streetpass-stage1.md)
and Stage 2 hardware checklist before claiming the two-phone gate passed.

Constraints for the first real-user release:
- Make discovery opt-in and easy to pause.
- Never broadcast a stable account ID or profile. Evaluate rotating, expiring identifiers.
- Treat client observations as untrusted. Plan for replay and fabricated encounters.
- Do not expose precise locations or a live nearby-person map by default.
- Decide what each person must consent to before revealing identity or messaging.
- Include blocking, reporting, account deletion, retention, and age/safety policy
  in the first real-user release.
- Keep interest matching separate from evidence of physical proximity.

## Suggested next slice

Run both foreground hardware checklists, record actual success rates and timings, and
integrate the encounter contract with the team's profiles and interest matching. Resolve
blocking, reporting, retention scheduling, and disclosure policies before a real-user release.
Run the Pocket and Walk hardware matrices before claiming background discovery works.
Neither simulated nor client-reported encounters prove physical proximity.
