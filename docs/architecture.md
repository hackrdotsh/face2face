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

No Bluetooth scan, geolocation permission, encounter upload, or matching runs yet.
Choose a discovery approach after testing physical iPhones. Measure background
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

Add profiles, interest selection, and a clearly labeled encounter simulator.
Use the simulator to test matching and blocking rules without collecting location.
Then test discovery on two physical iPhones. A simulated encounter must never
count as proof of actual proximity.
