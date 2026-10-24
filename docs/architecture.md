# Architecture and next steps

## Current boundaries

The Expo app calls the Hono Worker. Better Auth owns credentials and sessions,
stored in D1 through Drizzle. The Expo client stores native cookies in
SecureStore. Browser clients use normal cookie handling. No database code is
imported into the mobile app.

`GET /health` checks that the Worker responds. It is not a database readiness check.
`/api/auth/*` is the Better Auth handler. `GET /api/me` returns the authenticated
person's ID and name. `GET /api/coordinator` makes a read-only RPC call to that
person's Durable Object and exercises SQLite. Neither route accepts a user ID
from the caller. There is no public Durable Object forwarding route.

D1 will own durable product records such as profiles, interest memberships,
friendships, blocks, and approved encounter history. Durable Objects will own
coordination where ordering matters. Their final responsibilities should follow
the encounter protocol, not determine it. The current per-user coordinator only
proves that the binding works.

## Proximity is a separate engineering milestone

No Bluetooth scan, geolocation permission, encounter upload, or matching runs yet.
Expo Go and a browser preview cannot verify reliable background proximity.
Decide between BLE and a location-based approach after testing physical iOS and
Android development builds. Measure background execution, battery use, radio
permissions, false positives, and behavior after force-quit.

Before building the protocol:
- Make discovery opt-in and easy to pause. Explain foreground/background permissions.
- Never broadcast a stable account ID or profile. Evaluate rotating, expiring identifiers.
- Treat client observations as untrusted. Include replay prevention, expiration,
  rate limits, and a threat model for fabricated encounters.
- Do not expose precise locations or a live nearby-person map by default.
- Decide what each person must consent to before revealing identity or messaging.
- Make blocking, reporting, account deletion, retention, and age/safety policy part
  of the first real-user release, not a later cleanup.
- Keep interest matching separate from evidence of physical proximity.

## Suggested next slice

Build account screens, profile editing, interest selection, and a consented
encounter simulator. Use the simulator to test matching and blocking rules
without collecting location. Then evaluate the native discovery protocol on two
physical devices. The simulator must be clearly labeled and never count as proof
of an actual encounter.
