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
handles authentication. `GET /api/me` returns the authenticated person's ID, name,
email, and whether onboarding is complete. `GET /api/coordinator` calls that person's SQLite-backed Durable Object.
Neither protected route accepts a user ID from the caller.

Swift core tests run on Linux and Mac. Keychain and SwiftUI need Apple's SDKs;
the macOS CI job builds the simulator target. Physical-device behavior still
requires Xcode and an iPhone. Generated projects and local build output are ignored.

## Accounts and onboarding

Better Auth owns sign-in. A person can use any of these methods:
1. An emailed 6-digit code. The first code sign-in creates the account.
2. An email and password. A new password account gets no session until the person
   enters the code from the verification email. A password sign-in with an
   unverified email sends a new code.
3. A passkey, after the person adds one while signed in.

Password reset also uses an emailed code. A reset ends every existing session.
The server stores codes as hashes. Codes expire after 10 minutes.

`EMAIL_TRANSPORT` selects how email goes out. `console` writes each message to
the Worker log for development. `resend` sends it through the Resend API with the
`RESEND_API_KEY` secret and the `EMAIL_FROM` address.

### Data

Better Auth owns `user`, `session`, `account`, `verification`, `rate_limit`,
and `passkey`. These tables hold identity and credentials only. Product data is
in separate tables that reference `user.id` and cascade on account deletion.
- `user.name` is the only copy of the person's name. Onboarding writes it.
- `profile` has one row per person. It stores `birth_date` as `YYYY-MM-DD`,
  not an age, because an age changes over time.
- `gender` is a lookup table. `profile.gender_id` references it. A seed
  migration adds Male, Female, and Other. An option with `allows_description`
  accepts free text, which the server stores in `profile.gender_description`.
- A field with more than one value gets its own junction table, for example
  `profile_interest(user_id, interest_id)`. Do not store lists in one column.

### Onboarding fields

`apps/api/src/onboarding/fields.ts` is the list of onboarding fields. Each entry
declares a key, a type (`text`, `date`, or `singleChoice`), a label, whether it
is required, its validation, and how it reads and writes the database.
- `GET /api/onboarding` returns every field with its current value.
- `PATCH /api/onboarding` validates the submitted values with Zod and saves them
  in one D1 batch. It saves nothing if any value is invalid.
- Onboarding is complete when every required field has a value. The server
  calculates this from the current field list on each request.
- `requireOnboarded` returns 403 `onboarding_required` until onboarding is
  complete. Put it on every product route.

The iPhone app renders fields from the server description, so a new field of a
known type needs no app release. To add a field:
1. Add a column to `profile`, or a new table for a list or lookup.
2. Run `pnpm db:generate`. Use `drizzle-kit generate --custom` for seed data.
3. Add an entry to `onboardingFields`.

If the new field is required, existing accounts return to onboarding and see
only that field. A field type that the app does not know makes the app ask the
person to update it.

### Passkeys

Passkey challenges travel in a signed cookie. The iPhone transport ignores
cookies, so `Face2FaceCore` returns that one cookie with the matching verify
request. `PASSKEY_RP_ID` and `PASSKEY_ORIGINS` configure the relying party.
The local default is `localhost`, which an iPhone does not accept. Before
passkeys work on a device:
1. Choose an HTTPS domain for the relying party.
2. Serve `/.well-known/apple-app-site-association` from it with a
   `webcredentials` entry for the app.
3. Add the `webcredentials:` associated domain entitlement to `project.yml`.
4. Set `PASSKEY_RP_ID` to the domain and `PASSKEY_ORIGINS` to its HTTPS origin.

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

Add interest selection and a clearly labeled encounter simulator.
Use the simulator to test matching and blocking rules without collecting location.
Then test discovery on two physical iPhones. A simulated encounter must never
count as proof of actual proximity.
