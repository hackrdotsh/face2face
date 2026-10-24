# Stage 6: two-iPhone validation

Status: **hardware gate pending**. The Mac/API rehearsal has passed; no physical radio trial
has been completed. Keep the foreground demo as a candidate until both phones pass it.

## Readiness observed on 2026-10-24

- The local D1 database is migrated; no pending local migrations.
- The real HTTP smoke test passes initial reciprocity, retry, token rotation, Stop,
  second-walk freshness, and sign-out revocation.
- Xcode lists one previously paired iPhone as unavailable. A second phone is not available.
- A valid development signing identity exists, but no local development profile matches
  the app's bundle identifier.
- A signed Debug build was attempted. Xcode's provisioning request is blocked by
  **PLA Update available**: the Apple Developer account requires acceptance of its updated
  Program License Agreement. The signed build did not succeed.
- No agreement was accepted, phone installed, or physical Bluetooth result inferred.

The local API rehearsal creates throwaway accounts and synthetic observations. It does
not test Core Bluetooth, the native screen's reveal, haptics, locked Keychain access,
background delivery, or physical proximity. Previous unsigned builds do not satisfy signing.

## Clear the setup blockers

1. The account holder must review the agreement in their Apple Developer account and
   decide whether to accept it. The coding agent does not accept legal agreements.
2. Connect both charged phones to the Mac, unlock them, and trust the computer.
   Complete any on-device setup Xcode requires.
3. From the StreetPass workspace run **pnpm ios**. In Xcode choose Face2Face, Debug,
   and the appropriate development team. Keep automatic signing enabled.
4. Resolve the app identifier/profile through that team if Xcode requires it. Do not commit
   generated projects, provisioning profiles, signing credentials, or device identifiers.
5. Run the same branch/revision on both devices. Confirm each phone can open the app.

## Connect both apps to the same API

Use the existing Tailscale flow if configured, or a reachable LAN address. For a LAN trial,
determine the Mac's current IPv4 address, then run this from the StreetPass workspace,
replacing both **<Mac LAN IPv4>** placeholders:

    pnpm --filter @face2face/api exec wrangler dev --ip <Mac LAN IPv4> --port 8787 --var BETTER_AUTH_URL:http://<Mac LAN IPv4>:8787

Use **http://<Mac LAN IPv4>:8787** on each phone's Account tab. Both phones need network
access to that Mac. localhost on an iPhone addresses the phone, not the Mac. Use Debug
only for this HTTP development flow; Release requires HTTPS.

Check connection, then create/sign in to two different test accounts. Stop all radio
experiments before each new trial. Keep the API terminal open throughout the trial.

## Run and record

Follow the [Stage 5 acceptance procedure](streetpass-stage5.md#stage-6-remaining-hackathon-gate)
for foreground/repeated walks, then the [Stage 4 worksheet](streetpass-stage4.md#hardware-worksheet)
for background, locking, expiry, account changes, and interruption.

Save both reports before ending each trial. Record revision, device models, iOS versions,
network mode, each completed step, both report counts, and time to the first foreground reveal.
After Stop, numeric Walk measurements remain, but per-walk names are cleared.

| Trial                              | Phone A result | Phone B result | Time to reveal | Outcome |
| ---------------------------------- | -------------- | -------------- | -------------- | ------- |
| Foreground, first walk             | Pending        | Pending        | Pending        | Pending |
| Same accounts, fresh walk          | Pending        | Pending        | Pending        | Pending |
| One-sided report only              | Pending        | Pending        | Not applicable | Pending |
| Diagnostics and back during walk   | Pending        | Pending        | Not applicable | Pending |
| One app backgrounded               | Pending        | Pending        | Pending        | Pending |
| Both apps backgrounded             | Pending        | Pending        | Pending        | Pending |
| One / both phones locked           | Pending        | Pending        | Pending        | Pending |
| Interrupted network and retry      | Pending        | Pending        | Pending        | Pending |
| Stop / expiry / account switch     | Pending        | Pending        | Not applicable | Pending |
| Process death and explicit restart | Pending        | Pending        | Not applicable | Pending |

Do not mark this stage complete until actual device results are recorded and failures
necessary for the selected demo mode are resolved. If only the foreground trial passes,
present that mode and describe the background limitation accurately.
