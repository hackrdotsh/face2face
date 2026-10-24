# face2face

An iPhone app for meeting people with shared interests as you pass them in real life.
The current build has API connection checks, account creation, sign-in, session
restoration, and sign-out. Debug builds include two foreground Bluetooth experiments:
an account-free [device test](docs/streetpass-stage1.md), and an authenticated
[connected test](docs/streetpass-stage2.md) using expiring tokens and reciprocal
encounter reports. The connected test reveals account names after both sessions
report an exchange; it creates no friendships. Physical-device discovery remains
unvalidated. A separate [five-minute Pocket experiment](docs/streetpass-stage3.md)
adds anonymous background/restoration diagnostics. The separate
[five-minute Walk experiment](docs/streetpass-stage4.md) adds authenticated background
upload attempts with credentials held in memory. Its [live Walk flow](docs/streetpass-stage5.md)
reveals new reciprocal encounters and keeps technical details in diagnostics. Passive discovery
and locked-screen reliability are not validated or released. The remaining StreetPass
hackathon gate is two-phone validation and fixes from those trials.

## Open on your Mac

Install Xcode, launch it once, and install the iOS platform when prompted. Then:

```sh
gh repo clone hackrdotsh/face2face
cd face2face
direnv allow
pnpm install --frozen-lockfile
pnpm run setup
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

The Hono Worker listens on port 8787. In the iOS simulator, use
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

## Commands

| Task                                | Command                   |
| ----------------------------------- | ------------------------- |
| Start local API                     | `nix run .#dev`           |
| Start API over Tailscale            | `nix run .#dev-tailscale` |
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

No cloud resources are created by development, tests, or builds. To deploy:
1. Authenticate with Cloudflare and choose the account.
2. Run `pnpm --filter @face2face/api exec wrangler d1 create face2face`.
3. Set the returned `database_id` in `apps/api/wrangler.jsonc`.
4. Set `BETTER_AUTH_URL` to the HTTPS API URL and configure `WEB_ORIGINS` if needed.
5. Set the secret with `pnpm --filter @face2face/api exec wrangler secret put BETTER_AUTH_SECRET`.
6. Run `pnpm --filter @face2face/api exec wrangler d1 migrations apply DB --remote`.
7. Run `pnpm --filter @face2face/api exec wrangler deploy`.

Before inviting users, add email verification and account recovery, decide the
registration policy, and review abuse controls. Do not treat the hackathon
development configuration as a production-ready public service.

The Swift migration preserves the D1 schema and backend data. The previous
JavaScript client was removed; sign in in the native app to create its session.
See [architecture and privacy constraints](docs/architecture.md).

Private repository: <https://github.com/hackrdotsh/face2face>.
Invite collaborators through GitHub Settings. No license has been selected.
