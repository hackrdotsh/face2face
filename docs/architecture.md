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
email, and whether onboarding is complete. `GET /api/coordinator` calls that person's SQLite-backed Durable Object.
Neither protected route accepts a user ID from the caller.

Swift core tests run on Linux and Mac. Keychain and SwiftUI need Apple's SDKs;
the macOS CI job builds the simulator target. Physical-device behavior still
requires Xcode and an iPhone. Generated projects and local build output are ignored.

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
- A field with more than one value gets its own junction table, for example
  `profile_interest(user_id, interest_id)`. Do not store lists in one column.
  The exception is a snapshot written once and never edited, such as
  `connection.shared_interests`.
- `interest` is a lookup table with a unique lowercase `name`. A seed migration
  adds the list. `member_count` is the number of people who chose it. Triggers
  on `profile_interest` keep it current, including when an account is deleted.
  Interests are not an onboarding field yet. Only seeded people have them.

### Onboarding fields

`apps/api/src/onboarding/fields.ts` is the list of onboarding fields. Each entry
declares a key, a type (`text`, `date`, or `singleChoice`), a label, whether it
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

### Passkeys

Passkey challenges travel in a signed cookie. The iPhone transport ignores
cookies, so `Face2FaceCore` returns that one cookie with the matching verify
request. `PASSKEY_RP_ID` and `PASSKEY_ORIGINS` configure the relying party.
The local default is `localhost`, which an iPhone does not accept. Before
passkeys work on a device:
1. Choose an HTTPS domain for the relying party.
2. Serve `/.well-known/apple-app-site-association` from it with a
   `webcredentials` entry for the app.
3. Add the `webcredentials:` associated domain entitlement to `project.yml`.
4. Set `PASSKEY_RP_ID` to the domain and `PASSKEY_ORIGINS` to its HTTPS origin.

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

Until a connection is public, a participant sees only the shared interests and
their own choices. They do not see the other person's ID, name, or decision.
A public connection adds the other person's name, age, and interests.

Routes, all behind `requireOnboarded`:
- `GET /api/connections`
- `POST /api/connections/:id/decision` with `{ "decision": "accepted" | "declined" }`
- `POST /api/connections/:id/public`
- `POST /api/connections/:id/block`

### Notifications

Each person's `UserCoordinator` Durable Object keeps their inbox, the latest
200 notifications. The inbox is the record. A WebSocket only delivers new
notifications while a client is open. An iPhone app in the background has no
socket. Background delivery needs APNs later, sent from the same `notify` call.

A client, web or iPhone:
1. Loads `GET /api/notifications` on launch and when it returns to the foreground.
2. Gets a 60-second ticket from `POST /api/notifications/ticket` with its bearer token.
3. Opens `/api/notifications/socket?ticket=…`. Browsers cannot set an
   `Authorization` header on a WebSocket, and a bearer token must not go in a URL.
4. Receives `{"type":"ready"}`, then `{"type":"notification","notification":…}`
   for each new one. Sending `ping` returns `{"type":"pong"}`.
5. Reconnects with backoff when the socket closes and reloads the inbox.

Notification kinds are `encounter` (shared interests and expiry), `connected`,
`public`, `post_updated`, `post_cancelled`, and `post_rsvp`. None identifies the
other person. The post kinds hold only `postId` and `forumId`.

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
  inbox does not keep it. APNs can be added at the same place.
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

Message editing and deletion, read receipts for the other person, push
notifications, and cleanup of images that were uploaded but not sent. There is
no account deletion yet. When it exists, it must delete each chat's
`ChatRoom` storage and its R2 prefix.

## Forums

Each interest has one forum. Migration `0008_seed_forums` makes one for every
interest, with the interest ID as the forum ID. A post in a forum is an event.

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

## Proximity is a separate milestone

No Bluetooth scan, geolocation permission, encounter upload, or matching runs yet.
Choose a discovery approach after testing physical iPhones. Measure background
execution, battery use, permissions, false positives, and force-quit behavior.

Before building the protocol:
- Make discovery opt-in and easy to pause.
- Never broadcast a stable account ID or profile. Evaluate rotating, expiring identifiers.
- Treat client observations as untrusted. Plan for replay and fabricated encounters.
- Do not expose precise locations or a live nearby-person map by default.
- Decide what each person must consent to before revealing identity or messaging.
- Include blocking, reporting, account deletion, retention, and age/safety policy
  in the first real-user release.
- Keep interest matching separate from evidence of physical proximity.

## Suggested next slice

The encounter simulator, connections, notifications, and chat exist. Next:
- Add the Face2FaceCore client for the inbox, chats, tickets, and sockets, then
  the iPhone screens.
- Before deploying chat, create the `face2face-media` R2 bucket and enable
  Images transformations on the account.
- Let people choose interests during onboarding.
- Test discovery on two physical iPhones. A simulated encounter must never
  count as proof of actual proximity.
