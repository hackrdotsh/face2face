# Stage 2: authenticated encounter handoff

Stage 2 connects the foreground Bluetooth experiment to the API. It is available in the
Debug app's **Connected test** tab. The independent **Device test** tab remains the Stage 1,
account-free hardware control.

Both physical-device gates are pending. Passing API tests or displaying this screen in
the simulator does not validate Bluetooth discovery, physical proximity, or background operation.

## Local setup and two-phone test

1. From the StreetPass workspace, run **pnpm run setup**, then **pnpm db:migrate**.
   Migration 0001 adds the discovery and encounter tables; no remote database is changed.
2. Start the API with **pnpm dev:tailscale**, or use a reachable LAN API address.
   Both iPhones need the same API and working network access.
3. Generate/open the Xcode project with **pnpm ios**. Run the Debug configuration on both phones.
4. On each phone's **Account** tab, enter that API URL and sign into a different test account.
5. Open **Connected test** and tap **Refresh account and encounters**. Confirm the account name.
6. Read the sharing explanation and tap **Start connected discovery** on both phones.
7. Keep both screens visible and phones unlocked. Bring the devices together.
8. Each phone should show submitted reports. Names appear under recent server encounters only
   after both active sessions report the exchange.
9. Leave the phones running for more than two minutes to exercise rotation. The displayed session
   code should change, while a given peer remains one server encounter.
10. Stop discovery. Scanning and advertising stop immediately; the screen separately reports
    whether server revocation succeeded. Retry server revocation if the network failed.

The simulator can refresh an authenticated account's API history but cannot start Bluetooth.
Use the automated API contract tests to exercise synthetic reciprocal reports without hardware.
The Stage 1 and Connected test screens use compatible radio packets: an account-free Stage 1
token is not registered with the API and cannot produce a Stage 2 named encounter.

## Test the API without phones

Start the local migrated API, then run **pnpm test:streetpass** in a second terminal.
For a different local port, use **pnpm test:streetpass http://127.0.0.1:8791**.
The script checks real HTTP authentication, reciprocal reporting, retries, rotation, and
revocation. It creates two local throwaway accounts, stops their discovery sessions, and
signs them out afterward. It accepts only loopback base URLs and never prints credentials.
The reports are synthetic; a passing result says nothing about Bluetooth or proximity.

## HTTP contract

All endpoints require the existing signed bearer credential. Caller-supplied user IDs,
timestamps, and observation sources are rejected.

| Endpoint                     | Request JSON                        | Response                                     |
| ---------------------------- | ----------------------------------- | -------------------------------------------- |
| POST /api/discovery/start    | Empty object                        | Discovery lease                              |
| POST /api/discovery/rotate   | sessionId                           | Updated lease                                |
| POST /api/discovery/stop     | sessionId                           | stopped: true                                |
| POST /api/encounters/observe | sessionId, peerToken, observationId | pending or recorded, plus optional encounter |
| GET /api/encounters          | None                                | encounters array                             |

A lease contains sessionId, token, expiresAt, sessionExpiresAt, and serverTime.
Timestamps are integer Unix milliseconds. Tokens and session IDs are UUID strings.
Discovery locators are distinct from account bearer credentials.

A named encounter contains id, peer (id and name), firstSeenAt, lastSeenAt, and the fixed
source **client_reported_bluetooth**. It contains no radio token, email, GPS coordinates,
distance, or device identifier. No friendship or request is created.

## Consent, lifetime, and deduplication

- Start explicitly opts the account into name disclosure after reciprocal reports.
- One discovery session can be active per account. Start atomically replaces its previous session.
- Sessions last at most 30 minutes and cannot outlive their originating auth session.
- Radio tokens last at most five minutes. The app rotates after approximately two minutes.
- Previously issued tokens overlap until their original expiry for in-flight exchanges.
- Tokens are stored as SHA-256 hashes on the server and held only in memory on the phone.
- The v1 Bluetooth packet remains 17 bytes: a version byte plus the UUID's 16 bytes.
- Reciprocal reports must reference the same two active discovery sessions within two minutes.
  The server uses receipt time; it never trusts a client-reported time.
- There is one canonical encounter record per account pair. Further reciprocal observations
  refresh lastSeenAt rather than creating duplicate people, including across token rotation.
- Names become visible after reciprocity; previous named encounters remain available after Stop.
- History returns the most recent 50 encounter records from the last 24 hours.
- Expired sessions, tokens, observations, encounter history, and quota rows are cleaned up in
  bounded batches on Start/history requests. Cleanup is opportunistic, not a scheduled purge
  guarantee during periods of inactivity. Account deletion cascades to associated records.

Reciprocity is an application rule, not proof of proximity or verified identity. A malicious
client can submit fabricated observations or relay tokens. Names are account claims.
Interest matching, blocking/reporting UI, friend requests, and messaging belong to other slices.

## Retry and lifecycle behavior

The client captures the signed-in credential for each run, preventing an account switch from
changing the identity of queued reports. The snapshot is memory-only; persistent signed
credentials remain in the server-scoped Keychain entry.

The upload outbox is memory-only and capped at 100 distinct tokens per session. Retries keep
the same observationId, use backoff, and stop after five attempts. Rate-limited uploads wait
60 seconds. Invalid/expired reports are discarded and counted. Stop clears unsent reports;
they are not uploaded later without consent. There is no durable offline delivery guarantee.

The backend remembers accepted observation IDs within active sessions. Reusing an ID for a
different token returns 409. Repeating an accepted ID can return its receipt after token
expiry without advancing encounter timestamps. New expired/unknown tokens return 410.

An independent expiry watchdog stops the radio before a token's safe deadline even when a
network request stalls. Lifetimes are calculated relative to serverTime, with a ten-second
request-latency margin measured from request start, so waiting for a response does not extend
token lifetime. The final token is not repeatedly rotated when session expiry is near.

Stop, closing the test, or backgrounding immediately stops the radio and requests revocation.
If a canceled Start completes late, its issued session is revoked. Failed network revocation
is shown separately and can be retried; authentication failure is labeled unconfirmed.
Previously published locators naturally expire within five minutes. No background execution
or state restoration is implemented.

## Validation and remaining hardware work

Automated API tests cover authentication, one-sided privacy, reciprocal and concurrent reports,
rotation overlap, idempotent retries, account/session ownership, Stop/sign-out revocation,
expiry, malformed requests, and rate limits. Portable Swift tests cover Codable decoding,
wire compatibility, lease validation, clock offset, stable retry IDs, bounded queues, and
credential capture across account switches.

Before the hardware gate passes, record two-phone detection timings, both upload directions,
permission recovery, token rotation, Stop, and an interrupted-network retry. Then run the
separate Stage 1 worksheet as the radio baseline. Foreground success does not establish
locked-screen or passive pocket discovery.

## Independent background experiment

[Stage 3 Pocket test](streetpass-stage3.md) measures anonymous background radio and
state restoration separately. This authenticated Connected test still stops on backgrounding;
its token lifetimes and credential protections are unchanged.
