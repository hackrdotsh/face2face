# Stage 1: two-iPhone Bluetooth experiment

This is a Debug-only foreground experiment, not a released friend-discovery feature.
It exchanges anonymous test tokens without an account, API, GPS, or internet connection.
It does not resolve people, persist encounters, or prove physical proximity.
Physical-device validation is still pending.

## Run on two iPhones

1. Open the owned StreetPass workspace, not the team's main checkout.
2. Run **pnpm ios:project** (or **nix run .#ios-project**) to generate the Xcode project.
3. Open **apps/ios/Face2Face.xcodeproj** in Xcode. Select Face2Face and the Debug configuration.
4. Select your signing team, connect an iPhone with Developer Mode enabled, and run the app.
   Use the same project and configuration on the second phone.
5. Open the **Device test** tab on both phones. No API configuration or login is needed.
6. Tap **Start discovery** on both and grant Bluetooth permission when prompted.
7. Confirm both screens show scanning and advertising active. Bring the phones together.
8. Each phone should list the other phone's session code under **Received peer tokens**.
   Compare codes across the two screens; codes are truncated diagnostic labels, not identities.
9. Use **Share test report** on each phone to save the event log and elapsed times.
10. Tap **Stop discovery** on both before the next trial. Start creates fresh tokens and clears results.

Keep both phones unlocked and the Device test screen visible. Switching tabs, leaving the
screen, or backgrounding the app stops the experiment. Returning does not restart it.
If Bluetooth is turned off during an active session, the service waits and resumes when
Bluetooth becomes available. Permission recovery may require returning from Settings and
starting a fresh session if iOS terminated the app.

The simulator can inspect the screen, but Start is disabled because it cannot validate BLE.
Release builds omit the test screen, Bluetooth transport, and Bluetooth permission description.
Do not hand-edit or commit the generated Xcode project.

## Protocol

- Service UUID: C5D1A704-9D2E-4B29-A541-2C3138E64001
- Characteristic UUID: C5D1A704-9D2E-4B29-A541-2C3138E64002
- Characteristic: dynamic read and write with response.
- Packet: exactly 17 bytes: version 0x01, followed by a random UUID's 16 bytes.
- A new local token is generated for every explicit Start.
- Advertisements contain only the common service UUID, never the token or a profile.
- The central reads the peer token, validates the packet, then writes its own token.
- The peripheral accepts a write only after that central read within the last eight seconds.
- The central records success after receiving the write acknowledgment. The peripheral records
  the received token after validating the write and responding successfully.
- The central disconnects after the handshake. No bonding or pairing flow is implemented.
- Each phone is both central and peripheral. Simultaneous incoming/outgoing exchanges are
  deduplicated by the full peer token, never by its displayed short code.
- A central rechecks a successful peer after 15 seconds so a peer's new session can be noticed
  without restarting both devices. This cooldown is not the fresh-session detection target.

Opaque test tokens are exchanged without application-level authentication or encryption.
A malicious device can emulate this protocol, replay a token, or fabricate observations.
Read-before-write is a handshake ordering check, not an authentication mechanism.
These tokens must never be used as bearer credentials or proof of identity or proximity.

## Lifecycle and limits

Managers are created only after Start. Core Bluetooth delegates run on the main queue;
the observable service is isolated to the main actor. Stop removes the service, stops
scanning/advertising, cancels the outgoing connection, and detaches old delegates.
Results remain visible until the next Start, and are held only in memory.

There is one outgoing handshake at a time, with an eight-second deadline and up to three
attempts per continuously observed peripheral. Retries use backoff with jitter. A failed
peer cannot monopolize all future attempts. Stop/Start resets its attempt budget.
A two-second disconnect watchdog prevents a missing disconnect callback from stalling the queue.

Candidate peripherals and incoming read handshakes are limited to 32. Stale candidates expire
after 20 seconds without an advertisement. Encounter storage is limited to 100 peer tokens
per session; the event log retains the most recent 60 entries. Names, RSSI, device addresses,
account data, and complete tokens are excluded from reports. Reports contain truncated session
codes; sharing is an explicit user action.

## Physical acceptance worksheet

Record phone models, iOS versions, app revision, Bluetooth permission state, and run conditions.
The elapsed number is measured from that phone's Start, not an inferred crossing timestamp.

| Trial | Both phones received peer token? | A elapsed | B elapsed | Duplicates or issue |
| ----- | -------------------------------- | --------- | --------- | ------------------- |
| 1     | Pending                          | Pending   | Pending   | Pending             |
| 2     | Pending                          | Pending   | Pending   | Pending             |
| 3     | Pending                          | Pending   | Pending   | Pending             |
| 4     | Pending                          | Pending   | Pending   | Pending             |
| 5     | Pending                          | Pending   | Pending   | Pending             |
| 6     | Pending                          | Pending   | Pending   | Pending             |
| 7     | Pending                          | Pending   | Pending   | Pending             |
| 8     | Pending                          | Pending   | Pending   | Pending             |
| 9     | Pending                          | Pending   | Pending   | Pending             |
| 10    | Pending                          | Pending   | Pending   | Pending             |

For each trial, Stop both devices, position them apart, Start both, and bring them together.
Record actual timings and success rate. The target is ten successful fresh-session exchanges,
each within ten seconds. It is a target to measure, not a validated guarantee.

Also verify:
- Leave both devices active together for one minute: one encounter per peer token on each.
- Stop one phone: its scan and advertisement stop; no new results are recorded there.
- Start it again: its new code eventually appears on the other phone (allow the 15-second recheck).
- Stop and immediately Start both: stale callbacks do not contaminate the new sessions.
- Toggle Bluetooth off/on: clear availability state and automatic recovery while session requested.
- Deny Bluetooth permission: clear guidance without a crash.
- Interrupt a handshake by moving apart or stopping the peer: bounded retries and recovery.
- Background, lock, or switch away from the test: Stage 1 stops, with no claim of passive discovery.
- Unrelated Bluetooth advertisements produce no encounter.
- Repeat with the API stopped and network unavailable: the experiment still works.

Do not mark the hardware gate passed from simulator screenshots or portable tests.

## Integration boundary and later stages

DiscoveryToken, DiscoverySession, and DiscoveryEncounter are portable Swift core types.
The native BluetoothDiscoveryService owns radio behavior; its observable session supplies
diagnostic results. Neither layer modifies authentication, accounts, or the database.

The separate [Stage 2 connected test](streetpass-stage2.md) uses expiring server-issued
tokens and authenticated encounter submission. This Stage 1 screen intentionally keeps its
account-free test tokens as the independent radio baseline. Profiles, interest matching,
requests, and friendships are separate.
Background discovery, state restoration, notifications, and real-device battery/range
measurements require a later implementation and hardware gate.

Small commits remain on codex/streetpass-discovery until integration is requested.
