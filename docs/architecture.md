# Architecture and next steps

## Current boundaries

The iPhone SwiftUI app lives in `apps/ios/Face2Face`. Its dependency-free Swift
package, `Face2FaceCore`, owns URL validation, Codable response models, HTTP
requests, and session storage. The app owns presentation and form state on the
main actor. No backend or database code is bundled into the app.

The app calls the Hono Worker in `apps/api`. Better Auth owns credentials and
sessions in D1 through Drizzle. Its bearer plugin requires signed tokens. The
Swift client stores the `set-auth-token` response header in Keychain and sends
it as an Authorization header. It never treats the unsigned JSON token as the
credential. Keychain entries are scoped to each normalized API URL, and the HTTP
transport does not follow redirects with credentials.

`GET /health` checks the Worker response, not database readiness. `/api/auth/*`
handles authentication. `GET /api/me` returns the authenticated person's ID, name,
email, avatar, status message, and whether onboarding is complete. `GET /api/coordinator` calls that person's SQLite-backed Durable Object.
Neither protected route accepts a user ID from the caller.

Swift core tests run on Linux and Mac. Keychain and SwiftUI need Apple's SDKs;
the macOS CI job builds the simulator target. Physical-device behavior still
requires Xcode and an iPhone. Generated projects and local build output are ignored.

## 3D scenery

`MeadowScene` chooses the RealityKit forest on iOS 18+ when the saved **3D scenery**
appearance preference is on. iOS 17, an explicit opt-out, or an asset-generation
failure uses `MeadowCanvasScene`. Login, onboarding, and profile share this wrapper.
The same preference controls the matching 3D town, with `TownCanvasScene` as its fallback.

The camera is orthographic and virtual, not AR: there is no camera permission,
tracking session, downloaded model, or new dependency. Pine meshes are generated
once and shared by a finite repeating grid. The three decorative blobs use the
existing `BlobAvatar` silhouette, gradients, pill eyes, and idle timing;
`BlobVolume` supplies portable, tested mesh geometry. Pines use the original
four-tier shape with four green color bands, getting lighter toward the tip.
Decorative greetings retain the first crossing at four seconds and the 16-second
spacing, with a turn, hop, wave bubble, and expanding ring. The main blob faces up
the path while walking and turns sideways only to greet. Fireflies belong to
the scrolling terrain tiles, with only small local drift, rather than the camera.
Greeting bubbles copy the camera's orientation after each pose update instead of
using `BillboardComponent`: RealityKit's billboard hierarchy tracking crashed on
repeated profile-sheet presentation and teardown.
For deterministic Debug screenshots, `-forest-preview-time 4` freezes a greeting.

A view-owned task updates forest transforms approximately 30 times per second;
the town uses a matching SwiftUI animation timeline. Both pause when inactive or
with Reduce Motion; paused frames retain their pose. Light/dark changes repaint the scene
without rebuilding geometry. Long-running battery usage and frame pacing still
need measurement on hardware. Decorative crossings never record encounters.

`Town3DWorld` builds the market stalls, noticeboard, fountain, planted beds, surrounding
trees, and blob residents as RealityKit geometry. `TownProjection` keeps the orthographic camera
and the accessible 400 × 640 interaction map aligned. Camera gestures are disabled;
stall and public-friend actions stay in SwiftUI, including large-text navigation.
`TownPlazaLayout` shares destination and resident coordinates with those controls;
the 2D fallback retains its original village layout.
`Town3DGeometry` generates the curved canopy panels, scalloped trim, turned stone
basin, and water streams; the stalls and fountain do not download external assets.
Only the existing public-friend filter supplies identified visitors. Clearing that
list replaces their 3D shapes with anonymous decorative residents; no scene data is
stored or interpreted as real location. Profile revalidation, chats, notifications,
and all authorization continue through the existing models and routes.

## Accounts and onboarding

Better Auth owns sign-in. A person can use any of these methods:
1. An emailed 6-digit code. The first code sign-in creates the account.
2. An email and password. A new password account gets no session until the person
   enters the code from the verification email. A password sign-in with an
   unverified email sends a new code.
3. A passkey, after the person adds one while signed in.

Password reset also uses an emailed code. A reset ends every existing session.
The server stores codes as hashes. Codes expire after 10 minutes.

`EMAIL_TRANSPORT` selects how email goes out. `console` writes each message to
the Worker log for development. `resend` sends it through the Resend API with the
`RESEND_API_KEY` secret and the `EMAIL_FROM` address.

### Data

Better Auth owns `user`, `session`, `account`, `verification`, `rate_limit`,
and `passkey`. These tables hold identity and credentials only. Product data is
in separate tables that reference `user.id` and cascade on account deletion.
- `user.name` is the only copy of the person's name. Onboarding writes it.
- `profile` has one row per person. It stores `birth_date` as `YYYY-MM-DD`,
  not an age, because an age changes over time.
- `gender` is a lookup table. `profile.gender_id` references it. A seed
  migration adds Male, Female, and Other. An option with `allows_description`
  accepts free text, which the server stores in `profile.gender_description`.
- `profile.photo_id` names the current profile photo in R2. It is null when the
  person has no photo. Better Auth's `user.image` is not used.
- A field with more than one value gets its own junction table, for example
  `profile_interest(user_id, interest_id)`. Do not store lists in one column.
  The exception is a snapshot written once and never edited, such as
  `connection.shared_interests`.
- `interest` is a lookup table with a unique lowercase `name`. A seed migration
  adds the list. `member_count` is the number of people who chose it. Triggers
  on `profile_interest` keep it current, including when an account is deleted.
  Interests are saved through `/api/interests`, including the optional onboarding
  step. Onboarding, the native account page and Forums share the same picker.
  New interests open a forum when they reach three members; existing seeded forums
  remain available. Creating an interest selects it and is limited to five per day.

### Onboarding fields

`apps/api/src/onboarding/fields.ts` is the list of onboarding fields. Each entry
declares a key, a type (`text`, `date`, `singleChoice`, or `image`), a label, whether it
is required, its validation, and how it reads and writes the database.
- `GET /api/onboarding` returns every field with its current value.
- `PATCH /api/onboarding` validates the submitted values with Zod and saves them
  in one D1 batch. It saves nothing if any value is invalid.
- Onboarding is complete when every required field has a value. The server
  calculates this from the current field list on each request.
- `requireOnboarded` returns 403 `onboarding_required` until onboarding is
  complete. Put it on every product route.

The iPhone app renders fields from the server description, so a new field of a
known type needs no app release. To add a field:
1. Add a column to `profile`, or a new table for a list or lookup.
2. Run `pnpm db:generate`. Use `drizzle-kit generate --custom` for seed data.
3. Add an entry to `onboardingFields`.

If the new field is required, existing accounts return to onboarding and see
only that field. A field type that the app does not know makes the app ask the
person to update it.

An `image` field is optional and has the profile photo as its value. Upload the
photo to `PUT /api/profile/photo`. `PATCH /api/onboarding` refuses a value for it.

### Profile photos and avatars

A person can add one profile photo. A person without a photo gets a blob
avatar. Forum members and public connections see it. The person API shape is
`{ userId, name, avatar }`, and `avatar` is `{ seed, photo }`.
- `PUT /api/profile/photo` takes multipart field `image`, up to 15 MB. It
  returns `{ avatar }`. Errors are `413 image_too_large` and
  `415 unsupported_image`. It needs a session, but not finished onboarding.
- `DELETE /api/profile/photo` removes the photo and returns `{ avatar }`.
- The client crops the photo to the square around a circle before upload. The
  server crops the center again to a square, so the result is always square.
  It makes two WebP variants: `large` is 1024 px and `thumb` is 256 px.
  Re-encoding removes EXIF, GPS, and other metadata.
- Each variant goes to R2 at `profiles/<photoId>/<variant>`. The key has no
  user ID. A new photo or a removal deletes the files of the old photo.
- `photo` holds signed paths with the same rules as chat images. Clients show
  each variant as a circle.
- `seed` is the first 16 bytes of SHA-256 of `face2face-avatar:<userId>`, as
  base64url. It does not change and does not contain the user ID.

The web client and `Face2FaceCore` both draw the blob from the seed bytes `b`.
Coordinates are in a unit square:
1. The point count is `6 + b[0] % 3`. The hue is `(b[1] * 256 + b[2]) % 360`.
2. Point `i` has radius `0.34 + b[4 + i] / 255 * 0.1` and angle
   `b[3] / 255 * step + i * step - pi / 2`, where `step` is `2 * pi / count`.
   The points go around the center `(0.5, 0.5)`.
3. A closed Catmull-Rom spline joins the points. Each segment becomes a cubic
   Bezier curve.
4. The fill is a diagonal gradient from HSL `(hue, 80%, 82%)` to
   `(hue + 40, 70%, 68%)`.
5. The eyes are two pills, 0.06 wide and 0.12 high, in HSL `(hue, 40%, 20%)`.
   `b[12]` sets their distance from the center, `b[13]` sets their height, and
   `b[14]` moves both to the side.

`docs/fixtures/blob-avatar.json` holds the expected output for some seeds. The
web and Swift tests both check it. Change the drawing in both clients and the
fixture together.

### Status messages

A person can set one line of text, up to 80 Unicode code points. Only public
connections see it, on the public profile and in a speech bubble above the
person in the plaza. Each bubble shows for 4 seconds after a gap of 8 to 20
seconds, timed by `TownStatusBubble`. With Reduce Motion it stays shown.
- `PUT /api/profile/status` takes `{ "statusMessage": string | null }`. The
  server collapses whitespace to single spaces and trims it. Empty text clears
  it. It returns `{ statusMessage }`, or `400 status_too_long`. It needs
  finished onboarding.

### Passkeys

Passkey challenges travel in a signed cookie. The iPhone transport ignores
cookies, so `Face2FaceCore` returns that one cookie with the matching verify
request. `PASSKEY_RP_ID` and `PASSKEY_ORIGINS` configure the relying party.
The local default is `localhost`, which an iPhone does not accept. Native passkeys
use the production relying party, `f2f.rocky.systems`:
- The Worker serves `/.well-known/apple-app-site-association` without authentication,
  using the production `APPLE_APP_ID` to identify the signed app.
- `Face2Face.entitlements`, wired through `project.yml`, declares
  `webcredentials:f2f.rocky.systems`.
- `PASSKEY_RP_ID` and `PASSKEY_ORIGINS` match that domain and its HTTPS origin.

When changing the signing team or bundle identifier, update `APPLE_APP_ID` to the
signed application's identifier (`<Application Identifier Prefix>.<Bundle Identifier>`).
Associated Domains must be enabled for the app ID and provisioning profile. Deploy
the association file before installing the app; Apple's association CDN may cache
the file, so newly published associations can take time to appear on devices.

The web test client lets the browser keep the challenge cookie. It sends cookies
only on passkey requests and uses the bearer token for everything else. The cookie
is `SameSite=Lax`, so this works only when the web app and the API share a site,
such as `localhost:3000` and `localhost:8080`.

### Web test client

`apps/web` keeps its layers separate so the placeholder screens can be replaced
without touching the logic:
- `src/api`: HTTP client, error mapping, and one function per endpoint.
- `src/session`: the session provider and per-server token storage.
- `src/flows`: hooks that hold each screen's state and actions, matching the
  iPhone app's models.
- `src/onboarding`: turns server-described fields into drafts and values.
- `src/navigation`: hash routes such as `#/passed` and `#/chats/<id>`.
- `src/screens` and `src/devtools`: the UI only. They read hooks and render.
  Signed in, `HomeScreen` shows one page at a time: Passed (pending chances
  only), Chats, Notifications, Interests, and Account.
- `src/components/ui`: coss ui components, added with the shadcn CLI.

## Connections

An encounter between two people opens a 24-hour chance to connect. Each chance
is one `connection` row. A pair stores its user IDs in order (`user_low_id` <
`user_high_id`), so per-person columns are `low_*` and `high_*`. The API
translates them into "you" and never shows low or high to a participant.

`recordEncounter` in `apps/api/src/connections/encounter.ts`:
1. Ignores the encounter if either person blocked the other. Nobody is told.
2. Expires the pair's pending chance if its time ran out.
3. Does nothing if the pair already has a pending, private, or public row.
4. Inserts a pending row with the interests both people share, then sends both
   people an `encounter` notification.

A partial unique index allows one pending row per pair. After a chance expires,
the next encounter makes a new row, so the table keeps every chance.

| Status    | How a row gets there                                                                                   |
| --------- | ------------------------------------------------------------------------------------------------------ |
| `pending` | Created by an encounter.                                                                               |
| `expired` | 24 hours passed, or either person declined. A decline looks the same as a timeout to the other person. |
| `private` | Both people accepted.                                                                                  |
| `public`  | Both people agreed to go public after connecting.                                                      |
| `blocked` | One person blocked. The row disappears for the other person, and `block` stops future chances.         |

Expiry is lazy. Reads and actions mark old pending rows as expired. There is no
scheduled job. Updates check that the row has not changed since it was read, so
two people answering at once cannot overwrite each other.

`GET /api/connections` leaves out expired chances, so a chance disappears
from both lists when it times out or either person declines. The rows stay in
the table.

Until a connection is public, a participant sees the shared interests, their own
choices, and `theirAvatar`, the other person's blob seed. They do not see the
other person's ID, name, photo, or decision. The seed is the same one their
public profile uses, so a person who later sees that profile can recognize
them. Expired and blocked rows have no `theirAvatar`. A public connection adds
the other person's name, avatar with photo, age, interests, and status message
in `them`.

Routes, all behind `requireOnboarded`:
- `GET /api/connections`
- `POST /api/connections/:id/decision` with `{ "decision": "accepted" | "declined" }`
- `POST /api/connections/:id/public`
- `POST /api/connections/:id/block`

### Notifications

Each person's `UserCoordinator` Durable Object keeps their inbox, the latest
200 notifications. The inbox is the record. A WebSocket only delivers new
notifications while a client is open. An iPhone app in the background has no
socket, so `notify` also sends an APNs alert for `encounter`, `connected`,
`public`, and `message` to each of the person's registered phones.

A client, web or iPhone:
1. Loads `GET /api/notifications` on launch and when it returns to the foreground.
   The response is `{ notifications, unreadCount }`.
2. Gets a 60-second ticket from `POST /api/notifications/ticket` with its bearer token.
3. Opens `/api/notifications/socket?ticket=…`. Browsers cannot set an
   `Authorization` header on a WebSocket, and a bearer token must not go in a URL.
4. Receives `{"type":"ready"}`, then
   `{"type":"notification","notification":…,"unreadCount":…}` for each new one.
   Sending `ping` returns `{"type":"pong"}`.
5. Reconnects with backoff when the socket closes and reloads the inbox.

Inbox actions:
- `POST /api/notifications/seen` marks everything in the inbox as seen.
  `unreadCount` counts notifications created after that point.
- `DELETE /api/notifications/:id` deletes one notification. `DELETE
  /api/notifications` clears the inbox. Both delete on the server, so every
  device agrees.

Notification kinds are `encounter` (shared interests and expiry), `connected`,
`public`, `message` (`chatId`), `post_updated`, `post_cancelled`, and `post_rsvp`. None identifies the
other person. The post kinds hold only `postId` and `forumId`.

### Push

- The iPhone app asks for notification permission the first time it reaches the
  town. It then sends its APNs token to `PUT /api/notifications/devices/:token`
  with `{ "environment": "sandbox" | "production" }`. Debug builds use the
  sandbox. Sign out calls `DELETE /api/notifications/devices/:token` first.
- The coordinator keeps the newest 10 tokens for each person. It forgets a token
  when APNs answers 410, `BadDeviceToken`, or `DeviceTokenNotForTopic`.
- The alert holds the same text as the inbox card, the unread count as the app
  badge, and `notificationId`, `kind`, and `connectionId`. It never names the
  other person.
- While the app is open it shows no banner. The bell's count updates instead.
- Push is off until the Worker has `APNS_KEY_ID` and `APNS_PRIVATE_KEY` (the
  .p8 contents) and `APPLE_APP_ID` is set. The team ID and topic come from
  `APPLE_APP_ID`. The build also needs the `aps-environment` entitlement.
- A phone belongs to the account that registered it last. D1's `push_device`
  table maps the SHA-256 hash of each token to its owner. Registering removes the
  token from the previous owner's coordinator, so a phone stops getting an
  account's alerts as soon as someone else signs in on it, even when the old
  session expired without sign out. Unregistering only removes the caller's own
  ownership.

### Simulator

`DEV_TOOLS` is `"true"` locally and `"false"` in production. When it is not
`"true"`, every `/api/dev/*` route returns 404. These routes need no session:
- `POST /api/dev/seed` creates or resets six people with finished profiles and
  overlapping interests. Each uses the password `face2face-seed-password`.
- `POST /api/dev/forums/seed` seeds the people, then replaces the seeded forum
  posts and their RSVPs. Event times are relative to now. One event is in
  progress, one is over, and one is cancelled.
- `POST /api/dev/encounters` with `{ "firstUserId", "secondUserId" }` records a
  simulated encounter. The response says `"simulated": true`.
- `GET /api/dev/users`, `GET /api/dev/connections`, `GET /api/dev/interests`,
  and `GET /api/dev/users/:id/notifications` show raw state.
- `POST /api/dev/connections/:id/expire` ends a pending chance now.
- `POST /api/dev/reset` deletes every connection, block, and forum post.

A simulated encounter is not evidence that two people were near each other.

## Chat

A connection with status `private` or `public` has one chat. The chat ID is
the connection ID. A block closes the chat for both people.

### Parts

- **D1** decides who can chat. The Worker reads the `connection` row on every
  chat request and on every socket upgrade.
- **`ChatRoom`** is a Durable Object, one for each connection. Its SQLite keeps
  messages, uploaded images, and the read position of each side. It holds the
  sockets of both people and relays messages and typing. It trusts the access
  that the Worker gives it. A client cannot call it directly.
- **`UserCoordinator`** gets a `chat_activity` event when a message arrives for
  its person. It sends the event to that person's notification sockets. The
  inbox does not keep it. When the recipient has no socket open in that chat,
  `ChatRoom` also calls `notifyMessage`: the inbox keeps one `message` card per
  chat, replacing the previous one, and a push carries the first line of text
  (or "Sent a photo") with no sender name. Pushes for one chat share an APNs
  collapse ID and thread. Reading the chat removes its card.
- **Images binding** re-encodes each upload. **R2** (`MEDIA`) keeps the result.
  The bucket is not public.

### Privacy

A message says `"from": "you"` or `"from": "them"`. It never holds a user ID,
a name, or a side. `clientId` is set only on the viewer's own messages.
`chat_activity` holds the chat ID, message ID, and time. It holds no text.

### HTTP routes

All except the socket need a session and finished onboarding. A person who is
not in the chat gets 404.
- `GET /api/chats` lists chats with `lastMessage` and `unreadCount`, most
  recent activity first.
- `GET /api/chats/:id` returns one chat in the same shape.
- `GET /api/chats/:id/messages?before=<messageId>&limit=<1-100>` returns
  `{ messages, hasMore }`. Pages go from newest to oldest. Messages in a page
  go from oldest to newest. Send the first message ID as `before` to get the
  page before it.
- `POST /api/chats/:id/ticket` returns a 60-second socket ticket.
- `GET /api/chats/:id/socket?ticket=…` opens the chat socket.
- `POST /api/chats/:id/images` takes multipart field `image`, up to 15 MB.
  It returns `201 { image }`. Errors are `413 image_too_large` and
  `415 unsupported_image`.

### Socket frames

Client to server:
- `{"type":"send","clientId","text"}` or `{"type":"send","clientId","imageId"}`.
  `text` can be up to 4000 characters. The client makes `clientId`, up to 64
  characters. A send with the same `clientId` again returns the first message
  and does not make a copy. Send pending messages again after a reconnect.
- `{"type":"typing","state":"started"}` and `{"type":"typing","state":"stopped"}`.
- `{"type":"read","messageId"}` moves this person's read position forward.
- `ping` returns `{"type":"pong"}`.

Server to client:
- `{"type":"ready"}` when the socket opens. Load the newest page again, because
  messages sent before the socket opened are only on the server.
- `{"type":"ack","clientId","message"}` to the socket that sent the message.
- `{"type":"message","message"}` to every other socket, including the sender's
  other devices.
- `{"type":"typing","state"}` to the other person's sockets only.
- `{"type":"error","error","clientId"?}` for a bad frame or a refused send.
  Errors are `invalid_frame`, `chat_closed`, `image_not_found`, and
  `message_not_found`. The socket stays open.
- `{"type":"closed"}`, then close code `4000`, when the chat ends. Do not
  reconnect after a close code of 4000 or higher.

### Typing

The client decides when its person is typing:
1. On a keystroke, send `started`. Send it again every 3 seconds while typing
   continues.
2. Send `stopped` 5 seconds after the last keystroke, on send, or when the draft
   is empty.
3. Show the other person as typing for 8 seconds after each `started`, unless
   `stopped` or a message from them comes first.

The server stores nothing for typing. It sends `stopped` when the person sends
a message, and when their last typing socket closes.

### Images

1. The client uploads the file. The server checks the real format with the
   Images binding. JPEG, PNG, WebP, AVIF, and HEIC are accepted. SVG and other
   files are refused.
2. The server makes three WebP variants. Each fits inside a square and is never
   made larger: `original` is 2048 px, `preview` is 1024 px, and `thumb` is
   256 px. Re-encoding removes EXIF, GPS, and other metadata.
3. Each variant goes to R2 at `chats/<chatId>/<imageId>/<variant>`.
4. The room records the image for the uploader's side. Only the uploader can
   send it.
5. The client sends `{"type":"send","clientId","imageId"}`.

Each variant has `width`, `height`, and `path`. Use the size to lay out the
message before the image loads. `path` is a signed path on the API host,
for example `/media/chats/…/preview?expires=…&signature=…`. A path works for
one to two hours and stays the same within each hour, so a client can cache
it. Load the message again to get a new path.

The local test for metadata uses Miniflare, which encodes with sharp. HEIC input
is not tested locally.

### Not built

Message editing and deletion, read receipts for the other person, and cleanup of images that were uploaded but not sent. There is
no account deletion yet. When it exists, it must delete each chat's
`ChatRoom` storage and its R2 prefix. It must also delete the profile photo
files in R2.

## Forums

An interest has at most one forum, using its interest ID. Migration
`0008_seed_forums` opened the seeded forums. Migration `0011_interest_creation`
opens newly created interests at three members; an opened forum stays open if its
member count later drops. The matching Worker and migration must be deployed
together. A post in a forum is an event.

### Data

- `forum` links to one `interest`.
- `post` has a required `title` and `starts_at`, and an optional `description`,
  `location` (free text), and `ends_at`. `ends_at`, when set, must be on or
  after `starts_at`. Deleting a post sets `deleted_at` and keeps
  the row.
- `post_attendee` has one row for each person who RSVPs. Database triggers keep
  `post.attendee_count` in step with these rows.

### Rules

- A person can read and post in a forum only while that interest is on their
  profile. Other forums and their posts return 404. RSVPs stay when a person
  removes the interest.
- Forum members see the names and photos of authors and attendees.
- Only the author can edit or cancel a post. A cancelled post cannot change.
- An event is over when `ends_at` passes. With no `ends_at`, it is over when
  `starts_at` passes.
- An RSVP to a cancelled or finished event is refused. Leaving is always
  allowed.
- An edit sends `post_updated` and a cancellation sends `post_cancelled` to
  each attendee except the author. A new RSVP sends `post_rsvp` to the author,
  unless the author is the attendee. New posts send no notification.

### HTTP routes

All need a session and finished onboarding.
- `GET /api/forums` lists the person's forums with `upcomingPostCount`.
- `GET /api/posts?after=<postId>&limit=<1-50>` returns `{ posts, hasMore }`
  from all of the person's forums. It includes only events that are not over
  and not cancelled, soonest `startsAt` first. Send the last post ID of a page
  as `after` to get the next page.
- `GET /api/forums/:id/posts?before=<postId>&limit=<1-50>` returns
  `{ posts, hasMore }`, newest first. Cancelled posts are left out. Send the
  last post ID of a page as `before` to get the next page.
- `POST /api/forums/:id/posts` takes `{ title, startsAt, description?,
  location?, endsAt? }` and returns `201 { post }`.
- `GET /api/posts/:id` returns `{ post }`. A cancelled post still loads, with
  `cancelled: true`.
- `PATCH /api/posts/:id` takes any of the create fields. `null` or a blank
  string clears an optional field.
- `DELETE /api/posts/:id` cancels the post.
- `PUT /api/posts/:id/rsvp` and `DELETE /api/posts/:id/rsvp` attend and leave.
  Both return `{ post }`, and both can be sent again safely.
- `GET /api/posts/:id/attendees` returns `{ attendees }` by RSVP time.

A post includes `author`, `attendeeCount`, `attendeePreview` (the first 5
attendees), and the viewer's `attending` and `isAuthor`. It also includes
`edited`, `past`, and `cancelled`. Errors are `400 invalid_request`,
`400 invalid_times`, `403 not_author`, `409 post_cancelled`, and
`409 event_over`.

## StreetPass discovery

Discovery is opt-in and stays enabled until turned off. Radio activity may pause;
continuous and locked-screen operation are not validated on hardware yet.
Phones swap short-lived random tokens over Bluetooth and report what they
heard. When two phones report each other within two minutes, the server calls
`recordEncounter`, so a match becomes a normal pending chance with an
`encounter` notification. Code is in `apps/api/src/discovery` and
`apps/api/src/routes/discovery.ts`.

A match is a client report. It does not prove that two people were near each
other. A receipt never names the other person. A block stops the chance, and
the reporter is not told.

### Leases and tokens

- A lease belongs to one account and one auth session. Starting a lease ends the
  account's previous lease. Signing out deletes it.
- A lease lasts 30 minutes, or until the auth session expires if that is sooner.
  A token lasts 5 minutes. Rotation adds a token, and older tokens stay valid
  until they expire, so a handshake in flight can finish.
- The server stores only SHA-256 hashes of tokens. Advertisements never hold an
  account ID or profile.
- A pair of leases produces at most one encounter. A decline is not undone by
  more reports on the same walk.
- Each account can start 10 leases, rotate 12 times, and send 120 new reports a
  minute. A repeated observation ID does not count against the limit.
- Cleanup is bounded and runs on start. There is no scheduled job.

### Routes

All are `POST`, behind `requireSession` and `requireOnboarded`, and take only
the listed fields. Identifiers are UUIDs.

| Route                    | Body                                      | Response                                                     |
| ------------------------ | ----------------------------------------- | ------------------------------------------------------------ |
| `/api/discovery/start`   | `{}`                                      | Lease                                                        |
| `/api/discovery/rotate`  | `{ sessionId }`                           | Lease with a new token                                       |
| `/api/discovery/stop`    | `{ sessionId }`                           | `{ stopped: true }`, also for an unknown lease               |
| `/api/discovery/observe` | `{ sessionId, peerToken, observationId }` | `{ status: "pending" }` or `{ status: "recorded", matchId }` |

A lease is `{ sessionId, token, expiresAt, sessionExpiresAt, serverTime }`. Times
are epoch milliseconds. Clients use them relative to `serverTime`, not the phone
clock. `matchId` is an opaque hash of the two lease IDs. Both phones get the same
value, and it stays the same for one pair of leases.

The phone picks `observationId` and reuses it on retries. A retry returns the
current receipt, so a phone that got `pending` resends the same report every
5 seconds until the two-minute window closes. That is how the first reporter
learns about the match.

Errors are `400 invalid_request`, `400 self_encounter`, `403 onboarding_required`,
`409 observation_conflict` (an observation ID reused for another token),
`410 discovery_inactive`, `410 invalid_peer_token`, and `429 rate_limited` with
`Retry-After: 60`.

### iPhone

- The profile page, opened from the town's avatar or discovery badge, contains the **Discover people nearby** toggle. It
  saves an opt-in for that account and API, and shows the current status and match count.
  There is no fixed consent timeout. Turning it off, signing out, changing the API,
  or losing Bluetooth permission clears the opt-in and stops the radio immediately.
- Tokens still expire after at most five minutes. While foregrounded, the app rotates
  tokens roughly every two minutes and replaces the server lease before its 30-minute
  deadline. A full, drained report buffer also starts a fresh lease; buffers remain bounded.
  Retries retain observation IDs within a lease; pending old-lease reports are discarded
  when a lease is replaced, not sent under a new session.
- A missed renewal stops the radio at the token's safe deadline and shows **Paused**,
  without silently switching off the preference. Returning to the foreground retries.
  Renewal failures retry with a delay; rate limits defer renewal for a minute.
- Only the account/API-bound opt-in is stored in preferences. Tokens, captured bearer
  credentials, peer observations, and authenticated radio state remain memory-only.
  After process death, reopening the app resumes only after confirming the same
  signed-in account. No authenticated Bluetooth restoration or force-quit wakeup is promised.
- Debug builds add Walk, Connected, Pocket, and Device links under **Developer tools**
  in Settings. The Device and Pocket tests are anonymous and never reach the API.
- In the background, Bluetooth callbacks may request token renewal and uploads within
  the existing finite execution budget. There are no timer-driven background renewals.
  Without callbacks or an execution grant, discovery pauses when the token expires.
  A phone that reports
  first sees the match when it returns to the foreground.
- The iPhone's Recently Encountered page shows pending chances and accept/decline
  controls. Mutual acceptance opens private chat. The chat's Share profiles action
  separately records public-profile consent, with confirmation and anonymous waiting.
  Both consents are required before profiles or town visitors become visible.

`pnpm test:streetpass` runs the contract over real HTTP against a local API with
`DEV_TOOLS` set to `"true"`. It signs in as two seed people who are not connected
or blocked and expires their earlier pending chance first. It tests no Bluetooth.

### Two-phone check

1. Run `pnpm db:migrate`, then the API over Tailscale or the LAN, as in the README.
2. Sign in on each iPhone as a different onboarded person, such as two seed
   people after `POST /api/dev/seed`.
3. Turn on discovery on both phones with the screens unlocked, then bring them
   together.
4. Confirm that each phone shows one match, and that the web client shows one
   pending chance for each person with their shared interests and no name.
5. Keep both phones near each other for a minute. The count must stay at one,
   and no second chance may appear.
6. Turn discovery off on one phone. The other phone must not record a new match.
7. Repeat with one phone in the background, then locked, and write down the results.
8. Keep both apps foregrounded beyond five minutes and across a 30-minute lease boundary.
   Verify token/session renewal and new reciprocal matches without touching the toggle.
9. Interrupt networking through token expiry. Confirm the toggle remains on, the status
   becomes Paused, and foreground renewal resumes once networking returns.
10. Turn discovery off during renewal, then relaunch. Confirm it stays off. Repeat with
    sign-out, an account/API change, and revoked Bluetooth permission. Never resume a
    previous account's opt-in for a different account.

## Before real users

- Measure background execution, battery use, permissions, false positives, and
  force-quit behavior on hardware.
- Do not expose precise locations or a live nearby-person map by default.
- Decide what each person must consent to before revealing identity or messaging.
- Include blocking, reporting, account deletion, retention, and age/safety policy
  in the first real-user release.
- Keep interest matching separate from evidence of physical proximity.

## Suggested next slice

The native client has the inbox, chat with photos, public-friend visitors, forums,
event editing/RSVP, interest selection, and mutual profile sharing. Remaining demo gates:
- Rehearse real sign-in and image delivery against production. Local chat tests do
  not verify email delivery or production R2/Images configuration.
- Onboarding interest selection depends on the matching Worker deployment; optional
  interest changes finish saving before the client advances.
- Run the two-phone check above. A simulated or client-reported encounter must
  never count as proof of actual proximity.
