# face2face

Canonical repository: https://github.com/hackrdotsh/face2face
This is a personal-account repository. No organization-specific skill library applies.

## Workflow

- Use jj. Keep commits small, with `subsystem(action): Description` subjects.
- Use an owned jj workspace. Integrate completed changes into `main`.
- Run `pnpm check` and `pnpm build` before handing off changes.
- Run `pnpm fmt` and `nix fmt` before verification.
- Biome and nixfmt are approved formatters for this repository.
- Do not commit secrets, local D1 state, or generated native projects.

## Ownership

- `apps/mobile`: Expo app and native authentication client.
- `apps/api`: Hono Worker, Better Auth, Drizzle schema/migrations, Durable Objects.
- `docs`: architecture, privacy constraints, and setup decisions.

Keep auth/database code out of the mobile bundle. Infer API types from Hono;
validate external responses at runtime. Generate Worker bindings with Wrangler.
Proximity discovery remains unimplemented. Do not claim a client-reported
encounter proves physical proximity or expose location without explicit consent.
