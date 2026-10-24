# face2face

An iPhone app for meeting people with shared interests as you pass them in real life.
The current build has sign-in with an emailed code, a verified password, or a
passkey, password reset, and profile onboarding. The screens are placeholders.
Proximity discovery is not implemented yet.

## Open on your Mac

Install Xcode, launch it once, and install the iOS platform when prompted. Then:

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

## Run the backend

From the repository root, after the setup commands above:

```sh
nix run .#dev
```

In development, sign-in and verification codes appear in the API log, not in an
inbox. The Hono Worker listens on port 8787. In the iOS simulator, use
`http://localhost:8787` in the app's **API URL** field. For a physical iPhone,
use the Mac's reachable LAN address or run the API over Tailscale:

```sh
nix run .#dev-tailscale
```

The command prints the API URL. Enter it in the app and connect both devices to
the same tailnet. TCP 8787 must be allowed by your tailnet policy and host firewall.
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

Open `http://localhost:8081`. The web app signs in the same way as the iPhone app:
it stores a bearer token per API server and sends it in the `Authorization` header.
It covers every sign-in method, password reset, onboarding, and passkeys. Chrome,
Safari, and Firefox can create passkeys on `localhost`. The right column shows each
request and response, the current session, and a console for sending any request.

The default server is `http://localhost:8787`. Set `VITE_API_URL` to change it,
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

`nix build` produces the Worker bundle and migrations under
`result/share/face2face/`. It does not produce an iPhone binary. There is no default
`nix run .` app: launch the iPhone target through Xcode or `nix run .#ios`.
`nix flake check` tests the backend and portable Swift client. Linux cannot compile
SwiftUI or Security.framework. The macOS CI job builds the iPhone simulator target.

## Backend deployment

No cloud resources are created by development, tests, or builds. Production is the
`production` environment in `apps/api/wrangler.jsonc`. It serves `https://f2f.rocky.systems`
from the `face2face` D1 database. To update it:
1. Authenticate with `pnpm --filter @face2face/api exec wrangler login`.
2. Run `pnpm --filter @face2face/api exec wrangler d1 migrations apply face2face --remote --env production`.
3. Run `pnpm --filter @face2face/api exec wrangler deploy --env production`.

`BETTER_AUTH_SECRET` is already set. Production uses `EMAIL_TRANSPORT` `console` for now, so
sign-in codes appear in the Worker log (`wrangler tail --env production`). To send real email,
verify `f2f.rocky.systems` in Resend, run
`pnpm --filter @face2face/api exec wrangler secret put RESEND_API_KEY --env production`,
and set `EMAIL_TRANSPORT` to `resend` in the production environment.
Configure passkeys as described in [architecture](docs/architecture.md#passkeys).

Before inviting users, decide the registration policy and review abuse controls. Do not treat the hackathon
development configuration as a production-ready public service.

The Swift migration preserves the D1 schema and backend data. The previous
JavaScript client was removed; sign in in the native app to create its session.
See [architecture and privacy constraints](docs/architecture.md).

Private repository: <https://github.com/hackrdotsh/face2face>.
Invite collaborators through GitHub Settings. No license has been selected.
