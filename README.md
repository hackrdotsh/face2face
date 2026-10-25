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

The welcome screen is a scrolling pastel meadow. **Get Started** expands into the
account form, then the controls pop in sequentially after the glass finishes
expanding; closing reverses the sequence before the glass shrinks back to the
welcome pill. Reduce Motion uses
a crossfade instead. The scenery pauses while entering text, in the background,
and when Reduce Motion is enabled. The sliders button opens Settings, including
the API server and a saved System / Light / Dark appearance choice. System is the default.
The town has an account/avatar button at the top right for profile/photo, passkeys, and sign-out.
Settings sits immediately to its left for discovery, appearance, API, and developer tools.
Debug tools live inside Settings rather than separate bottom tabs.
Dark mode adds a night forest with gently glowing fireflies; Reduce Motion freezes their movement.
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
