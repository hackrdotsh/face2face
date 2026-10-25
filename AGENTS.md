# face2face

Canonical repository: https://github.com/hackrdotsh/face2face
This is a personal-account repository. No organization-specific skill library applies.

## Workflow

- Keep commits small, with `subsystem(action): Description` subjects.
- Run `pnpm check` and `pnpm build` before handing off changes.
- Run `pnpm fmt` and `nix fmt` before verification.
- After every requested app change, redeploy to the connected target iPhone and
  launch it. Report connection, signing, or lock-screen blockers explicitly.
- Biome, nixfmt, and swift-format are approved formatters for this repository.
- Do not commit secrets, local D1 state, or generated native projects.

## Ownership

- `apps/ios/Face2Face`: iPhone-only SwiftUI app.
- `apps/ios/Face2FaceCore`: portable Swift HTTP/auth client, Keychain storage and tests.
- `apps/web`: React test client for the API. coss ui components and Phosphor icons.
- `apps/api`: Hono Worker, Better Auth, Drizzle schema/migrations, Durable Objects.
- `docs`: architecture, privacy constraints, and setup decisions.

Keep database code on the server. Decode HTTP responses into Codable Swift models;
store signed bearer tokens in Keychain, never UserDefaults. Generate Worker bindings with Wrangler.
Generate the Xcode project from apps/ios/project.yml. Do not hand-edit generated projects.
Linux can test the Swift core, not SwiftUI, Security.framework, signing, or iPhone behavior.
StreetPass discovery is built but not validated on hardware. A reciprocal match
must go through `recordEncounter`, so the `connection` table stays the only lasting
record. Never broadcast account IDs or return a peer's identity in a discovery
response. Do not claim a client-reported encounter proves physical proximity or
expose location without explicit consent.
