---

name: control-town
description: Build, preview, screenshot and deploy the native town landing screen.
---

# Town verification

For agents verifying the native landing screen. Runtime commands:
`node scripts/control-town.mjs --help`.
- `doctor`: connected phones and booted simulators.
- `push-doctor [path-to.app]`: inspect the built app's signed APNs entitlement. Does not contact Apple or expose tokens.
- `preview`: build and open the offline Debug town on the booted simulator.
- `screenshot <path> [device-udid]`: capture visual evidence.
- `deploy <device-udid> [-town-preview]`: build, install, launch. Prefer Minun.

The CLI reads the bundle ID from the built app, including local signing overrides.
Physical deployment requires a team that can sign the configured entitlements.
Preview mode creates no credentials.

Feature map: [Town](references/features/town.md).
