# Town feature map

| Feature              | Entry                                   | Expected behavior                                                               |
| -------------------- | --------------------------------------- | ------------------------------------------------------------------------------- |
| Landing              | Finish onboarding, or Debug map button  | Three spaced destinations; shoreline below town                                 |
| Recently encountered | Upper-left venue, `town-encounters`     | Pending `/api/connections` only; no hidden identity                             |
| Connections          | Middle-right café, `town-connections`   | Private/public connections; identity only when server reveals it                |
| Forums               | Lower-left board, `town-forums`         | `/api/forums` for the signed-in person's interests                              |
| Account              | Header avatar, `townAccount`            | Existing profile, passkey and discovery controls                                |
| Notifications        | Header bell, `townNotifications`        | Themed `/api/notifications` inbox; refresh on opening, foreground and pull-down |
| Preview              | `node scripts/control-town.mjs preview` | No API requests; destination sheets identify preview mode                       |
| Reduced motion       | iOS Accessibility → Motion              | No resident, water or sign animation                                            |
| Large text           | Accessibility text sizes                | Scenery followed by full-size destination buttons                               |

## Evidence commands

```sh
node scripts/control-town.mjs doctor
node scripts/control-town.mjs preview
node scripts/control-town.mjs screenshot "$TMPDIR/opencode/town.png"
```

For a destination sheet, append `-town-destination forums`, `connections` or
`encounters` to `preview`. Use real sign-in to verify loading, retry, empty and
populated states. Preview does not exercise authentication.

UI tests: `apps/ios/Face2FaceUITests/TownUITests.swift`. They check tap targets,
sheet dismissal, large text and preview states. Decorative NPCs never represent
real nearby people. Water animation requires Reduce Motion off and app foreground.

Notifications UI tests: `apps/ios/Face2FaceUITests/NotificationsUITests.swift`.
`preview -town-notifications` opens the inbox with labelled sample data. Append
`-notifications-preview-state empty` or `error` to check those states. Signed-in
sessions load the API, never samples. This page has no unread tracking, live socket,
or APNs delivery. Event notices open the forums list; connection notices open the
corresponding town lists.
