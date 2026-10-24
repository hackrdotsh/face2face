# face2face

A social app for meeting people with shared interests as you pass them in real life.
This repository is the runnable foundation, not a working proximity detector.

## Start developing

Install Nix with flakes and direnv. From the repository root:

```sh
direnv allow
pnpm install --frozen-lockfile
pnpm setup
pnpm db:migrate
pnpm dev
```

Without a direnv shell hook, run `nix develop` first. `pnpm setup` generates a
local auth secret without overwriting an existing one. The API listens on port
8787; Expo uses port 8081. Press `w` in Expo for its web preview, or run
`pnpm --filter @face2face/mobile web` in a separate terminal.

The starter screen checks the API connection. Backend tests exercise account
creation, persisted sessions, authenticated routes, a Durable Object RPC call,
and sign-out. The mobile auth client is prepared in
`apps/mobile/src/auth-client.ts`; sign-in screens are not implemented.

For a physical phone, copy `apps/mobile/.env.example` to `apps/mobile/.env` and
set `EXPO_PUBLIC_API_URL` to your development machine's reachable LAN address,
such as `http://192.168.1.20:8787`. Restart Metro after changing it. For Android
emulators, the host address is usually `http://10.0.2.2:8787`. Keep the API on a
trusted development network; local HTTP is not suitable for production credentials.

## Commands

### Phone over Tailscale

Connect the development machine and phone to the same tailnet. Stop any running
`pnpm dev` first, then run from the repository root:

```sh
pnpm dev:tailscale
# Or: nix run .#dev-tailscale
```

This discovers the machine's Tailscale IPv4 address, advertises it in Expo's QR
code, and sets the mobile API URL and backend auth origin to that same address.
It does not change `.env` files or cloud configuration. Metro's cache is cleared
so an old `localhost` API URL is not reused. Scan with Expo Go, or open the printed
`exp://` link. If Expo Go requests sign-in, use the same Expo account on the phone
and in the CLI. The installed Expo Go version must support this project's SDK.

Your tailnet policy and host firewall must allow TCP 8081 and 8787 from the phone.
The API binds only to the Tailscale address in this mode; Metro still listens on
all interfaces. Do not expose either dev server through a public tunnel or port
forward. No public tunnel or firewall rule is created by the command.

`nix run .#tailscale` remains an alias for the same command.

Run commands from the repository root after installing dependencies.

| Task                                       | pnpm                     | Nix app                |
| ------------------------------------------ | ------------------------ | ---------------------- |
| Start API and Expo                         | `pnpm dev`               | `nix run .#dev`        |
| Start API                                  | `pnpm dev:api`           | `nix run .#api`        |
| Start Expo                                 | `pnpm dev:mobile`        | `nix run .#mobile`     |
| Build web export and Worker                | `pnpm build`             | `nix run .#build`      |
| Test API with local D1 and Durable Objects | `pnpm test`              | `nix run .#test`       |
| Check TypeScript                           | `pnpm typecheck`         | `nix run .#typecheck`  |
| Lint                                       | `pnpm lint`              | `nix run .#lint`       |
| Format                                     | `pnpm fmt` and `nix fmt` | `nix run .#fmt`        |
| Check formatting                           | `pnpm fmt:check`         | `nix run .#fmt-check`  |
| Check formatting, types, tests             | `pnpm check`             | `nix run .#check`      |
| Apply local migrations                     | `pnpm db:migrate`        | `nix run .#db-migrate` |

Nix apps forward arguments. For example, `nix run .#test -- -t 'requires a session'`.
`pnpm db:generate` creates a Drizzle migration after schema changes.
`pnpm types` regenerates bindings after Wrangler configuration changes.

`nix build` builds the web export, Worker bundle, and migrations in an isolated
Nix build. Outputs are under `result/share/face2face/`. `nix run .` serves the
built web preview at <http://127.0.0.1:8081>, independent of Metro. Start the API
separately to use the connection check. Pass a different port with
`nix run . -- 8082`. This default is a web preview, not an APK or iOS build.

`nix flake check` verifies the build, formatting, types, and API tests. The CI workflow
also runs `pnpm check` outside the build sandbox. If the dependency lockfile changes, update the dependency
hash in `flake.nix` from the mismatch reported by `nix build`.

## Layout and stack

- `apps/mobile`: React Native, Expo SDK 58, Better Auth Expo client and SecureStore.
- `apps/api`: Hono on Workers, Drizzle on D1, Better Auth, SQLite-backed Durable Objects.
- `docs/architecture.md`: boundaries, planned proximity work, and privacy requirements.

Node 24 and pnpm are pinned through `flake.lock` and `packageManager`. Nix outputs
cover Linux and macOS on x86_64 and aarch64. Only the host system is tested during
setup. The shell supports Metro and backend development; it does not install
Xcode, Android SDKs, or accept platform licenses. Native iOS builds need macOS
and Xcode; native Android builds need the Android SDK/JDK, or a configured EAS build.

direnv's built-in `use flake` loads this shell. Nushell needs a pre-prompt hook
that imports `direnv export json` with `load-env`; the maintainer's Nushell
configuration already provides it. Other collaborators should enable direnv's
integration for their own shell. Cached nix-direnv integration is optional.
Each new clone needs `direnv allow`.

## Deployment is manual

No cloud resources are created by setup, tests, or builds. Before deployment:
1. Authenticate with Cloudflare and choose the account.
2. Create a D1 database with `pnpm --filter @face2face/api exec wrangler d1 create face2face`.
3. Set its real `database_id` in `apps/api/wrangler.jsonc`.
4. Replace `BETTER_AUTH_URL` and `WEB_ORIGINS` with the intended HTTPS origins.
5. Set `BETTER_AUTH_SECRET` with `pnpm --filter @face2face/api exec wrangler secret put BETTER_AUTH_SECRET`.
6. Apply remote migrations with `pnpm --filter @face2face/api exec wrangler d1 migrations apply DB --remote`.
7. Deploy with `pnpm --filter @face2face/api exec wrangler deploy`.

The current auth configuration allows email/password registration for development.
Before inviting users, add email verification and account recovery, decide the
registration policy, review abuse controls, and configure separate deployment
environments. Do not expose this development configuration as a public service.

## Collaboration

Private repository: <https://github.com/hackrdotsh/face2face>.
Invite friends through GitHub **Settings → Collaborators**. No collaborators are
added automatically. Work on branches/bookmarks and open pull requests; CI checks
the build and tests. jj and Git both work with the colocated repository.

No license has been selected. The repository does not grant reuse permission.
