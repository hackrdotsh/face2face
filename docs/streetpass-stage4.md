# Stage 4: five-minute authenticated Walk experiment

The Debug app's **Walk test** combines server-issued Bluetooth locators with a bounded,
explicitly started background walk. The existing Connected test stays foreground-only;
Pocket test remains the independent anonymous restoration experiment.

Implementation and software checks are complete. Two-phone detection, locked-screen
exchange, upload timing, and system interruption behavior remain **unvalidated**.
A submitted report is a client claim, not proof of physical proximity or verified identity.
No friend request or location disclosure is added.

## Two-phone procedure

1. Apply the local API migrations and make the API reachable from both iPhones using the
   Stage 2 setup. Install the same Debug revision on both physical phones.
2. Sign in to different accounts on **Account**, with the same API selected on both.
3. Open **Walk test**, refresh, and tap **Start five-minute walk** while unlocked.
   Grant Bluetooth access. Keep other radio tests stopped.
4. First test with both screens open. Bring the phones together, inspect radio state and
   submitted reports, and confirm both account names appear after reciprocal server reports.
5. Stop both and start fresh runs. Repeat with one app backgrounded, both apps backgrounded,
   one phone locked, then both phones locked. Keep the walk within the displayed safe deadline.
6. Reopen both apps. Compare queued/submitted/discarded counts, background pass counts,
   event timestamps, and server encounters under **Diagnostics and encounter history**.
   Use **Share Walk test report** on both.
   The report contains counters and truncated diagnostic codes, not names or credentials.
7. Repeat the failure cases below with fresh sessions. Record device models, iOS versions,
   revision, network reachability, delays, and outcomes. A build or simulator screenshot
   cannot mark a hardware case passed.

If foreground discovery has not passed, first use the Stage 1 radio control and Stage 2
connected control to separate radio failures from API failures. Anonymous Pocket packets
are not server locators and cannot create named encounters.

## Consent, locator expiry, and suspension

Start captures a five-minute consent window. The authenticated permit ends at the earlier
of that original window and the current locator's safe expiry. Locator validity includes
request latency and a ten-second margin before server expiry. Both wall time and uptime
are checked; backward, reset, or invalid clock values refuse access.

Rotation happens only while the app is active. Rotation never extends the original walk.
There is no background renewal, so a walk backgrounded immediately after Start usually
has less than five minutes of usable locator time. The displayed remaining time is the
current safe permit, not a promise of execution. An in-flight connection retains its
original locator validity even when the active locator rotates.

Every resumed radio operation checks the permit. Foreground timers help update status;
expiry does not rely on a timer firing during suspension. As with Pocket test, a suspended
app may leave the common service UUID registered until its next wake, but an expired
permit cannot serve another token. Advertisements do not contain account IDs or names.

Leaving the Walk tab keeps its app-owned controller alive. Starting another radio test
preempts it. Stop ends radio work immediately, clears the memory queue, and attempts
server revocation. Revocation may remain pending if offline or denied execution; the UI
offers retry. A failed request does not claim the server session was revoked.
Published locators still expire within their original five-minute server lifetime.

## Bounded background uploads

Foreground history polling and retry timers pause when the app leaves the foreground.
A completed Bluetooth exchange can request one finite background execution grant:
- At most six seconds per grant, ended on completion, cancellation, or system expiration.
- At most three ready observation reports per pass.
- At least ten seconds between pass attempts.
- No background history fetch, renewal, polling loop, or timer-driven retry.

Backgrounding can also finish ready reports under the same budget. iOS may deny execution.
A later Bluetooth exchange can retry ready work; otherwise it waits until foreground.
There is no guarantee of a timely reciprocal report while locked. Both sessions still
need valid server locators and reciprocal observations within the existing two-minute
server window before names become available.

The queue keeps stable observation IDs across cancellation and ordinary retries.
It is bounded, memory-only, and lost at Stop or process death. Success counters mean
accepted reports; they do not imply a reciprocal named encounter. The server contract,
replay limits, and encounter retention from Stage 2 are unchanged.

## Credentials and account changes

Start reads the signed bearer credential while unlocked, then captures it only in memory
for that run. Background uploads use this snapshot, with no Keychain read while locked.
Persistent Keychain access remains WhenUnlockedThisDeviceOnly. No bearer token, locator,
peer list, or signed-in walk checkpoint is written to UserDefaults.

Walk mode has no Core Bluetooth restoration identifiers. Process death loses the signed
walk and queue; reopening requires a fresh explicit Start. Pocket's anonymous restoration
does not restore or authorize a named walk.

Account names and encounter history are hidden on backgrounding or leaving the tab.
Before foreground work and before displaying fetched history, the controller checks
the current account credential and API origin against its captured run. A mismatch stops
the old walk. Sign-out also revokes its server session under the existing API contract.
Changing the selected account does not reassign queued reports to that account.

## Hardware worksheet

All rows are pending. Use fresh runs and save both reports for each trial.

| Scenario                                    | Expected check                                        | Result  |
| ------------------------------------------- | ----------------------------------------------------- | ------- |
| Both foreground                             | Two exchange directions, reciprocal names, timing     | Pending |
| One backgrounded                            | Event-driven upload counters; compare both reports    | Pending |
| Both backgrounded                           | Radio callbacks and reciprocal upload timing          | Pending |
| One / both locked                           | No locked Keychain access; measure actual results     | Pending |
| Offline then foreground                     | Stable retry IDs; names require reciprocal acceptance | Pending |
| Upload timeout / denied grant               | Work canceled within budget; queue retained           | Pending |
| Original consent expires after rotation     | No exchange beyond original five minutes              | Pending |
| Locator expires while suspended             | Refuse token on next callback; radio stops            | Pending |
| Stop while upload is active                 | Radio stops; truthful revocation status               | Pending |
| Account or API changes during history fetch | Old names hidden; old run stops                       | Pending |
| Another test starts                         | Walk preempted; no overlapping radio owners           | Pending |
| Process killed / force-quit then reopened   | No signed walk or queue restored                      | Pending |

## Build boundary

All native Walk UI, controller, and background execution code are Debug-only. Release
still omits Bluetooth permission and background modes. The portable permit and policy
types are covered by Swift core tests, alongside credential snapshot/account-switch tests.
Use this slice to measure a short hackathon walk before designing longer-lived discovery.

[Stage 5](streetpass-stage5.md) adds the live Walk screen, fresh-encounter feedback,
and the remaining Stage 6 two-phone acceptance worksheet. The limits above are unchanged.
