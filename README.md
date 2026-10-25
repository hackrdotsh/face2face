# face2face

An iPhone app for meeting people with shared interests as you pass them in real life.
The current build has sign-in with an emailed code, a verified password, or a
passkey, password reset, and profile onboarding. The login screen uses the animated
meadow and glass form; profile onboarding shares this style and is server-driven,
with one field per step.
An opt-in [StreetPass discovery](docs/architecture.md#streetpass-discovery) mode stays
enabled until you turn it off and
turns a reciprocal Bluetooth match into an anonymous chance to connect. It is not
validated on hardware yet, and a match does not prove that two people were near.
New server-confirmed discovery matches trigger the system's short success haptic
throughout the foreground app, subject to device support and system settings.
Repeated receipts and session resets do not trigger feedback. Background matches
do not buzz or replay a haptic when you reopen the app. Connection notification
alerts are supported through APNs when permission, signing, and backend push
configuration are in place; they are separate from the foreground match haptic.

**Recently encountered** now lets you accept, decline, or block anonymous chances
and open a chat after mutual acceptance. The **Forums** board supports interest
selection, event creation/editing/cancellation, RSVPs, and attendee lists.
The notification bell shares its unread count with the inbox; opening marks it
seen, rows can be swiped away, and Clear All clears the inbox across devices.
Notification taps and widget links share a presentation queue so an open campfire
or profile sheet is dismissed before the requested destination opens.

On iOS 18 and later, the welcome, onboarding, and profile backgrounds are a 3D forest
with layered pines and rounded versions of the blob avatars. The town is a matching
3D market plaza with stalls, a fountain, planted beds, surrounding pines, and blob residents.
**Settings → 3D scenery** switches both scenes back to 2D; iOS 17 uses 2D automatically.
**Get Started** expands into the
account form, then the controls pop in sequentially after the glass finishes
expanding; closing reverses the sequence before the glass shrinks back to the
welcome pill. Reduce Motion uses
a crossfade instead. The scenery pauses while entering text, in the background,
and when Reduce Motion is enabled. The sliders button opens Settings, including
the API server and a saved System / Light / Dark appearance choice. System is the default.
The town has an account/avatar button at the top right for your blob profile, discovery, passkeys, and sign-out.
Native profiles are blob-only: no photo picker is offered, and existing uploaded
photos are left untouched on the server. Blobs squish, sway, hop, blink and glance;
tap your profile blob for a happy jump. Reduce Motion freezes decorative movement.
Settings sits immediately to its left for appearance, API, and developer tools.
Debug tools live inside Settings rather than separate bottom tabs.
Dark mode adds a night forest with gently glowing fireflies; Reduce Motion freezes their movement.
**Settings → Blob companion → Blob in Dynamic Island** brings your seeded blob along
for a one-hour Live Activity, independently of Bluetooth discovery. Supported iPhones
show it in the Dynamic Island; all supported iPhones get a Lock Screen layout.
Tap the in-app preview to make it bounce. Breathing, blinking, bobbing, and ripple
animations pause in the background and respect Reduce Motion. iOS controls Live
Activity rendering; the Island does not run a continuous animation loop.
**Anonymous signal graph** is a separate opt-in under Blob companion. It only uses
observations from discovery you have already enabled; it never starts scanning on
its own. Quantized bars represent a short, aggregate Bluetooth signal history, not
metres, direction, verified proximity, microphone audio, or a particular person.
The graph never logs, persists, or uploads raw RSSI, or links samples to devices/accounts. The Island uses
short, coalesced update animations; iOS controls delivery, especially in the background.
Signal bars expire after 12 seconds without a fresh sample. A stale signal does
not end the one-hour companion.
The hand-wave button on the expanded Island or Lock Screen makes your blob react
with a short update animation, without enabling discovery or extending the session.
Dismissal, sign-out, and API/account changes stop the companion. After an hour it
shows a resting state if iOS has suspended the app, and is removed when the app runs
again. It never restarts without another explicit toggle.

Open **Around the campfire** in town to see your accepted connections as blobs.
The fire is symbolic, not live attendance, location, or online status. Private
connections use anonymous names and decorative blobs even if an unexpected response
contains identity-shaped fields. Only mutually public friends get names and their
own seeded avatars. Larger circles have readable pages, not silently omitted friends.

Enable **Settings → Around the campfire → Friends in campfire widget**, then add
**face2face → Around the campfire** from the widget gallery. Small, medium, and large
Home Screen widgets have campfire artwork and next/previous pages (4, 6, and 10
friends per page). Lock Screen layouts show a saved count, not identities.
The app writes a minimal, opt-in App Group snapshot: drawing slots, display names
when public, blob seeds, and a timestamp. No account/connection IDs, credentials,
photos, interests, or discovery observations are shared. It expires after 15
minutes without an authenticated refresh; sign-out, API/account changes, disabled
sharing, or refresh failures replace it with a redacted state and request a widget
reload. Widget refreshes remain subject to iOS scheduling, not instant server revocation.
Tapping a widget opens Connections with normal authentication required.

The camera follows one walker, with occasional oncoming walkers and a brief wave
as they pass. These are decorative animations: no encounters are detected or recorded.

## Open on your Mac

Install Xcode 26 or newer, launch it once, and install the iOS platform when prompted. Then:

```sh
gh repo clone hackrdotsh/face2face
cd face2face
direnv allow
pnpm install --frozen-lockfile
pnpm setup
pnpm db:migrate
nix run .#ios
```

`nix run .#ios` uses XcodeGen to generate `apps/ios/Face2Face.xcodeproj` and opens it.
Select the **Face2Face** scheme and your iPhone. In **Signing & Capabilities**, select
your Apple development team and change the bundle identifier if needed. Run with
Xcode. This is an iPhone-only SwiftUI app targeting iOS 17 or later.

Without Nix, install XcodeGen with `brew install xcodegen`, then run:

```sh
cd apps/ios
xcodegen generate
open Face2Face.xcodeproj
```

Do not commit the generated Xcode project. `apps/ios/project.yml` is its source.
The generated project embeds the **Face2FaceWidgets** extension in the app. Use the
same development team for both targets; keep the extension bundle ID prefixed by
the app bundle ID if you customize them. Live Activities require no push setup.
Connection alerts do require the app's Push Notifications entitlement and backend
APNs configuration; see [architecture](docs/architecture.md). This is independent
of the Live Activity and campfire widget capabilities.
Both targets also need the **group.systems.rocky.face2face** App Group for campfire
sharing. Keep that group identical in both entitlements files if you customize it.
To preserve local signing across project generation, create the ignored
`apps/ios/signing.local.yml`:

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: YOUR_TEAM_ID
```

No third-party Swift packages, CocoaPods, or JavaScript runtime are used by the app.

The **Face2Face** scheme includes UI tests for account switching, keyboard input,
connection settings, and accessibility text sizes. Run them with **Product → Test**
on an iPhone simulator. Layout tests do not contact the API or use saved sessions.

## Run the backend

From the repository root, after the setup commands above:

```sh
nix run .#dev
```

In development, sign-in and verification codes appear in the API log, not in an
inbox. The Hono Worker listens on port 8080. In the iOS simulator, use
`http://localhost:8080` in the app's **API URL** field. For a physical iPhone,
use the Mac's reachable LAN address or run the API over Tailscale:

```sh
nix run .#dev-tailscale
```

The command prints the API URL. Enter it in the app and connect both devices to
the same tailnet. TCP 8080 must be allowed by your tailnet policy and host firewall.
The command binds the API to the Tailscale address. It creates no public tunnel
or firewall rules. `nix run .#tailscale` and `pnpm dev:tailscale` are equivalent.

Debug builds allow HTTP for local development. Release builds reject HTTP and
retain Apple's default transport security. Use an HTTPS API before distribution.
Sessions are stored in Keychain, scoped to the selected API server. Changing the
server does not send its saved token to another server.

## Test the backend in a browser

`apps/web` is a React test client for the API. It needs no Apple developer
account. Start the API, then the web app in a second terminal:

```sh
nix run .#dev
nix run .#web
```

Open `http://localhost:3000`. The web app signs in the same way as the iPhone app:
it stores a bearer token per API server and sends it in the `Authorization` header.
It covers every sign-in method, password reset, onboarding, and passkeys. Chrome,
Safari, and Firefox can create passkeys on `localhost`. The right column shows each
request and response, the current session, and a console for sending any request.

The **Simulator** tab seeds test people, signs in as any of them, and simulates
two people passing each other. Seeded people use the password
`face2face-seed-password`. The signed-in person's connections and live
notifications appear on the left. To act as both people at once, open a second
browser profile or a private window, because tabs share the saved session.

The default server is `http://localhost:8080`. Set `VITE_API_URL` to change it,
or enter another URL in the header. The API only accepts browser requests from the
origins in `WEB_ORIGINS` and passkeys from `PASSKEY_ORIGINS`. Production allows
no browser origins yet.

## Commands

| Task                                | Command                   |
| ----------------------------------- | ------------------------- |
| Start local API                     | `nix run .#dev`           |
| Start API over Tailscale            | `nix run .#dev-tailscale` |
| Start the web test client           | `nix run .#web`           |
| Generate and open Xcode project     | `nix run .#ios`           |
| Generate Xcode project only         | `nix run .#ios-project`   |
| Build for the iOS simulator on Mac  | `nix run .#ios-build`     |
| Test Swift API/auth client          | `nix run .#swift-test`    |
| Run all portable tests              | `nix run .#test`          |
| Format Swift, TypeScript, and Nix   | `nix run .#fmt`           |
| Check formatting and portable tests | `nix run .#check`         |
| Build Worker bundle                 | `nix run .#build`         |
| Generate a Drizzle migration        | `pnpm db:generate`        |
| Apply local D1 migrations           | `nix run .#db-migrate`    |
| Regenerate Worker bindings          | `pnpm types`              |

Run these commands from the repository root. `pnpm check` and `pnpm build` are the
underlying checks and Worker build. Nix provides Node 24, pnpm, Swift, SwiftPM,
swift-format, and backend tools. On Mac it also provides XcodeGen. Xcode and Apple
SDKs must be installed separately. direnv's `use flake` loads the environment;
each clone needs `direnv allow` and a shell with direnv integration enabled.

There is no default `nix run .` app: launch the iPhone target through Xcode or `nix run .#ios`.
`nix flake check` tests the portable Swift client and flake formatting. Linux cannot compile
SwiftUI or Security.framework. The macOS CI job builds the iPhone simulator target.

## Backend deployment

No cloud resources are created by development, tests, or builds. Production is the
`production` environment in `apps/api/wrangler.jsonc`. It serves `https://f2f.rocky.systems`
from the `face2face` D1 database. To update it:
1. Authenticate with `pnpm --filter @face2face/api exec wrangler login`.
2. Run `pnpm --filter @face2face/api exec wrangler d1 migrations apply face2face --remote --env production`.
3. Run `pnpm --filter @face2face/api exec wrangler deploy --env production`.

Production uses Resend to send sign-in and verification codes from
`face2face <no-reply@f2f.rocky.systems>`. The sending domain is verified in Resend.
Both `BETTER_AUTH_SECRET` and `RESEND_API_KEY` are required Cloudflare secrets.
Local development still uses the console transport, so codes appear in the local API log.
Configure passkeys as described in [architecture](docs/architecture.md#passkeys).

Before inviting users, decide the registration policy and review abuse controls. Do not treat the hackathon
development configuration as a production-ready public service.

The Swift migration preserves the D1 schema and backend data. The previous
JavaScript client was removed; sign in in the native app to create its session.
See [architecture and privacy constraints](docs/architecture.md).

Private repository: <https://github.com/hackrdotsh/face2face>.
Invite collaborators through GitHub Settings. No license has been selected.
