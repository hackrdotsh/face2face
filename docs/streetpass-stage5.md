# Stage 5: live Walk flow and repeatable encounter reveals

The Walk tab now presents a live encounter flow instead of the full diagnostic form.
The existing Connected, Device, and Pocket controls stay available. Native changes remain
Debug-only, on the separate StreetPass branch.

## What changes

- Start, stop, account readiness, and recovery are visible on the live Walk screen.
- Four independent steps show a started walk, a received Bluetooth token, an accepted
  report, and a new reciprocal server encounter. An upload alone never completes the last step.
- A new reciprocal record reveals the peer's account name with a brief fade and foreground
  success feedback. Reduce Motion removes the fade. Names are still self-reported.
- Diagnostics, server history, and the shareable report are one navigation step below Walk.
  Navigating there does not create a second controller or stop the active walk.
- Reports include the number of new encounters in this walk and time from Start to the first
  foreground reveal. This duration includes network/polling delay; it is not radio-only latency.
  These numeric measurements survive Stop, while per-walk names are cleared.

No interests, friend request action, location, push notification, background lease renewal,
or signed-walk restoration is added. Those boundaries and Stage 4's five-minute permit,
background upload budgets, credential handling, and hardware limitations still apply.

## Old history cannot trigger a new reveal

Start loads encounter history before requesting a fresh server session or starting the radio.
If that history request fails, Start fails without activating the radio.

A per-walk tracker compares records against both that baseline and the new lease's server
timestamp. An unchanged historical encounter never becomes this walk's new encounter,
including when an observation receipt references a previously recorded account pair.
An existing pair can be revealed again after a genuinely newer server record during the new
walk. Each pair triggers feedback only once per walk, even across polling, token rotation,
reordered responses, or updated account names. Storage is capped at 50 pairs per walk.

The live reveal is populated only after a foreground history fetch and the existing account/API
credential check. Background uploads do not fetch or display account names. The tracker uses
server timestamps, not agreement with the phone's clock. Server records remain untrusted
client-reported observations; this presentation adds no physical-proximity attestation.

## Stage 6: remaining hackathon gate

One stage remains for this StreetPass hackathon slice: run on two physical iPhones, record
the outcomes, and fix failures observed there. Software verification cannot substitute for it.
1. Install the same signed Debug revision on both phones and use different accounts against
   the same reachable API. Apply migrations first. Stop other radio experiments.
2. Open Walk on both, refresh accounts, and Start with both screens open.
3. Bring the phones together. Record each step on both screens, time to the new name, and
   save both diagnostic reports. Confirm an accepted one-sided report alone is insufficient.
4. Stop both and Start again with the same accounts. Confirm old history produces no reveal
   before the next exchange, then confirm one reveal per pair after a new reciprocal record.
5. Open diagnostics and return during a running walk. Confirm the same session is still active.
6. Repeat the Stage 4 matrix for background, locked phones, expired tokens, interrupted network,
   Stop, account switching, and process death. Keep each run inside its current safe deadline.
7. Record actual results below. Use a foreground demo if that is the validated mode; describe
   locked/background trials according to their measured outcomes.
8. Merge/integrate the discovery contract with teammates only after the agreed hardware gates.
   Profiles, shared interests, and friend requests remain separate team work.

| Gate                                            | Phone A | Phone B | Result  |
| ----------------------------------------------- | ------- | ------- | ------- |
| Foreground exchange and reciprocal name         | Pending | Pending | Pending |
| Second run ignores old history before exchange  | Pending | Pending | Pending |
| Second run reveals updated pair exactly once    | Pending | Pending | Pending |
| Diagnostics/back keeps one live session         | Pending | Pending | Pending |
| One-sided report does not create a fresh reveal | Pending | Pending | Pending |
| Background/locked Stage 4 matrix                | Pending | Pending | Pending |
| Stop, expiry, account change, process death     | Pending | Pending | Pending |

Record device/iOS versions, revision, network, timings, and report counters. Do not label
successful compilation, previews, simulated observations, or API tests as a passed radio gate.
