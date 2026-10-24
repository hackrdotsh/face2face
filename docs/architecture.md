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

Debug builds have a foreground-only Core Bluetooth experiment in a separate
Device test tab. It exchanges anonymous, per-session test tokens and deduplicates
them in memory. It needs no account or backend and stops when the app backgrounds
or the test screen closes. Release builds omit this experiment.

No geolocation, account resolution, encounter upload, interest matching, background
restoration, or notifications run yet. Physical-device discovery remains unvalidated.
Follow the [Stage 1 hardware test guide](streetpass-stage1.md) before claiming the
two-phone gate passed. Production discovery still requires measurements of background
execution, battery use, permissions, false positives, and force-quit behavior.

Before building the protocol:
- Make discovery opt-in and easy to pause.
- Never broadcast a stable account ID or profile. Evaluate rotating, expiring identifiers.
- Treat client observations as untrusted. Plan for replay and fabricated encounters.
- Do not expose precise locations or a live nearby-person map by default.
- Decide what each person must consent to before revealing identity or messaging.
- Include blocking, reporting, account deletion, retention, and age/safety policy
  in the first real-user release.
- Keep interest matching separate from evidence of physical proximity.

## Suggested next slice

Run Stage 1 on two physical iPhones and record the actual success rate and
timings. Then add expiring server-issued discovery tokens and authenticated encounter
submission, keeping profiles and interest matching independent of radio observations.
A separately labeled encounter simulator can test matching and blocking without
collecting location; neither simulated nor client-reported encounters prove proximity.
