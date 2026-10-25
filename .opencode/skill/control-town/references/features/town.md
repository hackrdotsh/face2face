# Town feature map

| Feature              | Entry                                         | Expected behavior                                                                |
| -------------------- | --------------------------------------------- | -------------------------------------------------------------------------------- |
| Landing              | Finish onboarding, or Settings → Preview town | Three destinations around a tree-lined market plaza; 2D fallback has a shoreline |
| Recently encountered | Upper-left venue, `town-encounters`           | Pending `/api/connections` only; no hidden identity                              |
| Connections          | Middle-right café, `town-connections`         | Private/public connections; identity only when server reveals it                 |
| Forums               | Lower-left board, `town-forums`               | `/api/forums` for the signed-in person's interests                               |
| Account              | Top-right avatar, `townAccount`               | Profile/photo, discovery, passkey and sign-out page                              |
| Settings             | Left of account, `appSettings`                | Appearance, API and developer tools                                              |
| Discovery status     | Header beacon, `townDiscovery`                | Quick on/off toggle for the same discovery preference on the profile page        |
| Notifications        | Header bell, `townNotifications`              | Themed `/api/notifications` inbox; refresh on opening, foreground and pull-down  |
| Preview              | `node scripts/control-town.mjs preview`       | No API requests; destination sheets identify preview mode                        |
| Reduced motion       | iOS Accessibility → Motion                    | No resident, water or sign animation                                             |
| Large text           | Accessibility text sizes                      | Scenery followed by full-size destination buttons                                |

## 3D scenery

On iOS 18+, **Settings → 3D scenery** enables the shared RealityKit forest and town.
The town has market stalls, a fountain, planted beds, surrounding trees, and blob residents. Its
SwiftUI hit targets retain the same map coordinates and identifiers. iOS 17, an
explicit opt-out, or an asset-generation failure uses the 2D town.

`Town3DTests.swift` checks scene structure, projection alignment and removal of
public-friend meshes, plus perimeter trees and clear entrances. Town/PublicFriends UI tests exercise the 3D renderer; the
Town suite also checks the 2D fallback. Capture light and dark previews. The 3D
camera is fixed and never represents a real person's location.

Stalls use curved striped canopies, exposed counters and timber frames. The fountain
has a recessed water surface and four modeled streams. Native tests check canopy
clearance from the camera and water below the basin rim; inspect both day and night
previews for missing surfaces, clipping, and obscured destination labels.

## Evidence commands

```sh
node scripts/control-town.mjs doctor
node scripts/control-town.mjs preview
node scripts/control-town.mjs screenshot "$TMPDIR/opencode/town.png"
```

For a destination sheet, append `-town-destination forums`, `connections` or
`encounters` to `preview`. Use real sign-in to verify loading, retry, empty and
populated states. Preview does not exercise authentication.

Preview account actions and developer tools are disabled so the preview makes no authenticated requests.
Debug Settings has `exitTownPreview` (Return to sign in), outside the disabled
preview tools. `deploy <udid> -start-signed-out` opens the real login without
restoring a token; it does not delete Keychain data, accounts or onboarding.
Omit `-town-preview` for real-account testing. Use a new email address to exercise
onboarding, rather than deleting an existing person's data. UI coverage:
`FreshSignInUITests.swift`.

UI tests: `apps/ios/Face2FaceUITests/TownUITests.swift`. They check tap targets,
settings access, sheet dismissal, large text and preview states. Decorative NPCs never represent
real nearby people. Water animation requires Reduce Motion off and app foreground.
In the 2D fallback, the waterfront continues below the fitted map through the bottom safe area; no
grass band should appear above or behind the home indicator.

Notifications UI tests: `apps/ios/Face2FaceUITests/NotificationsUITests.swift`.
`preview -town-notifications` opens the inbox with labelled sample data. Append
`-notifications-preview-state empty` or `error` to check those states. Signed-in
sessions load the API, never samples. The town and inbox share the unread count;
opening marks it seen, rows swipe to delete, and Clear All removes the inbox.
Connection APNs alerts and foreground arrivals are handled by `PushNotifications`;
delivery requires suitable signing/entitlements and backend APNs configuration.
Event notices open the corresponding event; connection notices open the
corresponding town lists. Chat-message push delivery is not added here.

## Public friend visitors

- Only `status == "public"` with a disclosed `them` profile and public user ID can
  become `PublicTownFriend`. Private, pending, blocked, expired and unknown statuses
  never create NPCs, even if a response unexpectedly includes identity-shaped data.
- Up to three visitors use seeded 3D blobs (the login walker in 2D), with a photo badge when available and a first-name tag.
  Tap `town-friend-<connectionId>` for the compact profile. Large-text mode uses
  stationary friend buttons below the destinations.
- Opening a profile fetches `/api/connections` again before showing identity. A
  missing/revoked connection shows an unavailable state. Failed refreshes clear
  cached visitors and profiles. Data is held in memory and cleared in the background.
- The roster refreshes on foreground and every 60 seconds while the town is active.
  NPCs do not mean online, physically nearby, or currently in someone else's town.
- The card shows only avatar, name, age and interests disclosed by the public
  connection response. It exposes no contact details or location.

`preview` includes labelled sample public friends. Append `-town-friend-profile`
to open a sample card directly. `-town-friends-preview-state empty`, `error` or
`revoked` exercises those states; `revoked` removes public status on the next fetch.

Tests: `PublicTownFriendsTests.swift` (portable filter), `TownFriendsTests.swift`
(native revalidation/races), and `PublicFriendsUITests.swift` (tap/profile/privacy).

## Messaging

- The café opens `ChatsView`. Only accepted private/public connections are listed.
  `chat-<connectionId>` opens a conversation. Private chats use an anonymous label
  and generic avatar, even if unexpected identity fields appear in a response.
- A revalidated public profile has `publicProfileMessage`. It dismisses the profile
  and opens the same chat. Pending, blocked and expired connections cannot chat.
- `chatDraft`, `chatSend`, `chatAttachPhoto` and `chatBack` are the conversation controls.
  Photos are previewed before sending, resized to 2048 pixels and stripped of
  EXIF/GPS before upload; the server re-encodes them into its signed variants.
- History loads over authenticated HTTP. Sockets use fresh short-lived tickets,
  never bearer tokens in URLs. Sends keep their client IDs across retries.
- Typing expires after eight seconds. Read positions clear server unread counts;
  they are not read receipts shown to the other person. The café reloads on return
  and every 30 seconds while open. No APNs delivery is added.
- Backgrounding closes the socket. Returning revalidates the original credential
  and chat access before reconnecting. Blocking closes and clears the conversation.
  The conversation options menu exposes the existing block action, with confirmation.
  Unconfirmed sends stay in memory only while the conversation is open; leaving
  warns before discarding them. Older messages load with the Earlier messages button.
- `chatShareProfiles` asks for explicit consent in an anonymous chat. Cancel changes
  nothing. Agree sends the viewer's consent to `/api/connections/:id/public`.
  `chatSharingWaiting` keeps identity hidden and removes repeated consent controls.
  Messaging and blocking remain available; acceptance alone never shares profiles.
- The open chat checks connection status every five seconds. A failed consent reply
  triggers a read, not another POST. Backgrounding invalidates in-flight results.
  After mutual consent, `chatProfilesPublic` and `chatViewProfile` appear. The compact
  profile revalidates the public-only list before showing identity. The town also
  reloads that list and reserves one of its three visitor slots for the new friend.
  Neither the profile nor the visitor implies online presence or physical proximity.

`preview -town-chat preview-ava` opens a sample public conversation;
`preview -town-chat preview-private` opens an anonymous one. Preview sends are local,
explicitly labelled, and do not contact the API.
Add `-chat-sharing-preview-state peer-agreed` to simulate a second consent, or
`peer-later` to exercise the five-second refresh. Omit the flag for one-sided waiting.

`node scripts/chat-smoke.mjs` provisions an isolated temporary local D1/R2/DO Worker,
runs the real Swift HTTP/WebSocket clients in both directions (text and photos),
checks retry deduplication, typing, signed image retrieval, unread clearing, mutual
profile sharing, public-friend visibility and block closure, then stops its own
Worker. It never resets the shared dev database.

Tests: `ChatTests.swift`, opt-in `LiveChatTests.swift`, native `ChatModelTests.swift`,
`ProfileSharingTests.swift`, `ProfileSharingUITests.swift`, and `ChatUITests.swift`.
The native photo test uses the API's EXIF/GPS fixture.
The photo-picker UI test uses an existing simulator photo, or skips if the library
is empty. Seed it with `xcrun simctl addmedia booted <test-image>` before running.

## Forums and interests

- The poster board opens `ForumsView`: Upcoming events across selected interests,
  plus Your forums. `forumInterests` opens the interest picker; `forumCreate` opens
  a new event. Empty accounts must choose interests before posting or joining forums.
- The board reuses the account page's `InterestsSection`, `InterestsModel`, catalog
  ranking and name rules. Picks save serially through the same `/api/interests`
  client. `interestSearch` searches or adds names; `forumInterestsDone` returns to
  the board. Removing an interest hides its forum but keeps existing RSVPs.
- New interests wait for three members before a forum opens. The board uses the
  server's actual forum list, not a client-side member-count guess. Existing seeded
  forums remain available. Users can create up to five new interests per day.
- `forum-post-<id>` opens an event. `forumRSVP` joins/leaves, `forumAttendees` lists
  attendee names/photos. Hosts and attendees are visible to forum members; this is
  separate from the mutual-public-connection gate used for friend NPCs.
- Only `isAuthor` posts expose Edit/Cancel. `forumEventTitle`, `forumEventDescription`,
  `forumEventLocation`, `forumEventStarts`, `forumEventEnds`, and `forumEventSave`
  control editing. Optional values encode null so fields can be cleared.
- New RSVPs are disabled for cancelled/past events. Existing attendees can still
  leave. Server refusals reload the event; membership loss clears cached details.
- `forumLoadMore` uses `after` for Upcoming and `before` for a forum feed. Opening,
  returning to the foreground, pull-to-refresh and successful mutations refresh data.
- Notifications for events open their exact post, including cancellation state.

`preview -town-destination forums` uses an in-memory, labelled sample board.
`-forums-preview-state empty`, `waiting` or `error` exercises those states. Preview edits reset
when the board closes and never change a real account.

`node scripts/forums-smoke.mjs` uses the existing isolated Worker harness to verify
real Swift interest selection, forum access, create/edit/cancel, idempotent RSVP,
attendees, notifications, unauthorized access and opening a new forum with three
distinct accounts. It does not touch shared local D1.

Tests: portable `ForumsTests.swift`, opt-in `LiveForumsTests.swift`, native
`ForumsModelTests.swift`, `ForumsUITests.swift`, and event routing in
`NotificationsUITests.swift`.

## Recently encountered

- The venue opens `RecentlyEncounteredView`. Cards show only shared interests, a
  generic silhouette, expiry and the viewer's own decision. Names, photos and the
  other person's decision are never rendered, even if unexpected identity data is
  present in a response. This is not proof of physical proximity or a live map.
- `accept-<connectionId>` sends `accepted`; `decline-<connectionId>` asks for
  confirmation, then sends `declined`. Requests identify only the connection and
  decision; the server determines the authenticated side. A saved answer cannot
  be changed. Waiting cards have no repeated answer buttons.
- A decline closes the chance as expired; the card disappears. Block is available
  from `chanceOptions-<connectionId>`. Expired/changed/already-answered refusals
  reload the server state instead of blindly resubmitting a non-idempotent answer.
- Mutual acceptance produces a private connection, never public consent.
  `encounterOpenChat` opens the real conversation; `encountersChats` opens the café
  list. Neither path reveals identity unless the connection is separately public.
- The page refreshes on entry, foreground, pull-down and every five seconds while
  visible, so the first accepter can see when the other person also accepts.
  In-flight reads are invalidated by decisions/backgrounding; failed loads clear
  stale cards. A lost acceptance response is reconciled from a fresh read.

`preview -town-destination encounters` shows labelled sample chances; accepting
the first sample opens a local anonymous chat. `-encounters-preview-state empty`,
`error`, `expired`, `stale`, `peer-accepts` or `lost-response` exercises those cases.
Preview actions never change a real account.

`node scripts/encounters-smoke.mjs` verifies decline, one-sided waiting, repeated
answer rejection, mutual acceptance, anonymous chat access and outsider denial
against an isolated Worker. Encounters in this rehearsal are explicitly simulated.
`node scripts/chat-smoke.mjs` now accepts through the real decision client before
verifying bidirectional text/photos. Neither rehearsal proves Bluetooth discovery.

Tests: `ConnectionsTests.swift`, `LiveEncountersTests.swift`, native
`EncountersModelTests.swift`, and `EncountersUITests.swift`.
