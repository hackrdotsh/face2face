# Town feature map

| Feature              | Entry                                         | Expected behavior                                                               |
| -------------------- | --------------------------------------------- | ------------------------------------------------------------------------------- |
| Landing              | Finish onboarding, or Settings → Preview town | Three spaced destinations; shoreline below town                                 |
| Recently encountered | Upper-left venue, `town-encounters`           | Pending `/api/connections` only; no hidden identity                             |
| Connections          | Middle-right café, `town-connections`         | Private/public connections; identity only when server reveals it                |
| Forums               | Lower-left board, `town-forums`               | `/api/forums` for the signed-in person's interests                              |
| Account              | Top-right avatar, `townAccount`               | Separate profile/photo, passkey and sign-out page                               |
| Settings             | Left of account, `appSettings`                | Discovery, appearance, API and developer tools                                  |
| Discovery status     | Header badge, `townDiscovery`                 | Status indicator; opens discovery controls in Settings                          |
| Notifications        | Header bell, `townNotifications`              | Themed `/api/notifications` inbox; refresh on opening, foreground and pull-down |
| Preview              | `node scripts/control-town.mjs preview`       | No API requests; destination sheets identify preview mode                       |
| Reduced motion       | iOS Accessibility → Motion                    | No resident, water or sign animation                                            |
| Large text           | Accessibility text sizes                      | Scenery followed by full-size destination buttons                               |

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

UI tests: `apps/ios/Face2FaceUITests/TownUITests.swift`. They check tap targets,
settings access, sheet dismissal, large text and preview states. Decorative NPCs never represent
real nearby people. Water animation requires Reduce Motion off and app foreground.

Notifications UI tests: `apps/ios/Face2FaceUITests/NotificationsUITests.swift`.
`preview -town-notifications` opens the inbox with labelled sample data. Append
`-notifications-preview-state empty` or `error` to check those states. Signed-in
sessions load the API, never samples. This page has no unread tracking, live socket,
or APNs delivery. Event notices open the forums list; connection notices open the
corresponding town lists.

## Public friend visitors

- Only `status == "public"` with a disclosed `them` profile and public user ID can
  become `PublicTownFriend`. Private, pending, blocked, expired and unknown statuses
  never create NPCs, even if a response unexpectedly includes identity-shaped data.
- Up to three visitors use the login walker, with a small avatar and first-name tag.
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
