# Stage 3: five-minute anonymous Pocket experiment

This Debug-only experiment measures Core Bluetooth behavior when a phone is backgrounded
or locked. It is independent of the Stage 2 account/API flow. No account, name, auth
credential, server locator, GPS coordinate, or network upload is involved.

The feature is implemented, but every two-phone background/restoration hardware gate is
pending. API tests, simulator rendering, and successful builds do not validate radio behavior.

## Test procedure

1. Build the Debug app on two physical iPhones. Open **Pocket test** on both.
2. Tap **Start five-minute Pocket test** on both and grant Bluetooth access.
3. Confirm scanning is requested and advertising is registered. Note each truncated code.
4. For the foreground baseline, bring the phones together with both screens visible.
5. Stop both and start a fresh trial. Background one app before bringing the phones together.
6. Repeat with both apps backgrounded, then with one and both phones locked/screens off.
7. Reopen the app within the five-minute window. Inspect received tokens and event timestamps.
   Save **Share Pocket test report** on both phones.
8. Stop both apps. Repeat as fresh sessions so iOS duplicate coalescing does not mask a trial.
9. Leave a trial untouched for more than five minutes. Bring phones together/reopen and confirm
   no expired session exchanges tokens; the UI should show expiry on the next wake.
10. Use the original **Device test** as the foreground control and **Connected test** for
    authenticated/API integration. Do not mix those modes when measuring named encounters.

Pocket consent lasts five minutes and can survive leaving its tab or backgrounding.
An On badge marks a requested Pocket test. Starting another radio test preempts it and
clears its saved consent, so two managers cannot independently run different tests at once.
Stop clears consent before tearing down radio work. No test runs on an initial fresh launch.

## Lifecycle and state restoration

Only Pocket mode initializes Core Bluetooth managers with stable restoration identifiers:
- sh.hackr.face2face.pocket.central.v1
- sh.hackr.face2face.pocket.peripheral.v1

On a later launch, the app prepares these managers only if a valid consent checkpoint exists.
Preparing managers does not itself request scanning or advertising. Actual
centralManager/willRestoreState or peripheralManager/willRestoreState callbacks must
arrive to resume the radio. If iOS supplies no restoration state, the saved test is stopped
and a new explicit Start is required. Another active radio test takes priority over restoration.

A restored run uses a fresh, anonymous in-memory token. Old connections are canceled and
the GATT service is rebuilt after managers become ready. Peer tokens and counts are not
persisted across process death. The restoration counter counts actual manager callbacks,
not app foregrounding or recreated managers.

The checkpoint in UserDefaults contains only a run UUID, start date, and start uptime.
There are no radio tokens, account IDs, peer records, or bearer credentials in it.
Expiry checks use elapsed wall time and uptime; invalid clocks or reset uptime fail closed.
A checkpoint never grants more than the original five-minute window.

## Suspension and timing

Foreground retry polling is canceled when Pocket enters the background. Background work
is driven by Bluetooth callbacks, not a promise that a general timer keeps running.
Scanning always filters the common Face2Face service UUID; duplicate discovery reports are
disabled in background mode. iOS may coalesce discoveries, slow scanning/advertising,
or delay a callback beyond the handshake's deadline.

Every radio-start, connection, token read/write, and recorded result checks consent expiry.
Outgoing callbacks also check the handshake deadline. An expiry timer helps while the app
is awake, but it is not the enforcement mechanism when iOS suspends the process.

If the process is fully suspended at expiry, the common service UUID may remain registered
until iOS wakes the app. That advertisement contains no personal token or profile.
On the next callback/wake, expired consent is refused and the test is stopped before
another token can be served. The diagnostic state describes registered requests, not
measured radio airtime or proof that a passerby was detected.

## Hardware worksheet

Record device models, iOS versions, app revision, permission state, timestamps, and codes.
Use one fresh five-minute session per trial. Keep other discovery test modes stopped.

| Scenario                          | Phone A                | Phone B    | Both received tokens?        | Delay   | Outcome |
| --------------------------------- | ---------------------- | ---------- | ---------------------------- | ------- | ------- |
| Foreground baseline               | Open                   | Open       | Pending                      | Pending | Pending |
| One app backgrounded              | Background             | Open       | Pending                      | Pending | Pending |
| Both backgrounded                 | Background             | Background | Pending                      | Pending | Pending |
| One locked                        | Screen off             | Open       | Pending                      | Pending | Pending |
| Both locked                       | Screen off             | Screen off | Pending                      | Pending | Pending |
| Expired while suspended           | Expired                | Open       | Must refuse                  | Pending | Pending |
| Bluetooth disabled/re-enabled     | Toggle in Settings     | Open       | Pending                      | Pending | Pending |
| OS memory termination/restoration | OS-terminated          | Open       | Pending                      | Pending | Pending |
| User force-quit/reopen            | User-terminated        | Open       | No automatic resume expected | Pending | Pending |
| Another test starts               | Foreground Device test | Pocket     | Pocket must stop             | Pending | Pending |

Do not label an Xcode Stop or simulator termination as a successful OS memory-pressure
restoration. Capture the actual restoration callback count and hardware circumstances.
User force-quit, reboot, and Bluetooth toggles have distinct iOS restoration rules.

## Apple constraints and later integration

Apple describes background scanning/advertising changes and limited event-processing time in
its [Core Bluetooth background guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html).
[Technical Note 3115](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules)
distinguishes system termination from force-quit and Bluetooth power changes. This human-to-human
experiment does not set up accessories through AccessorySetupKit and does not claim recovery
from user force-quit. State restoration is event-dependent and is not guaranteed execution.

Stage 2 named encounters deliberately remain foreground-only. Authenticated background
discovery needs separately validated lease renewal, locked-Keychain handling, upload timing,
revocation, and data retention. This experiment does not weaken Keychain accessibility or
reuse expired server tokens to claim passive named encounters.

Release builds omit the Pocket UI/transport, Bluetooth permission, and background modes.
No location permission, background audio workaround, push setup, or cloud resources are added.
