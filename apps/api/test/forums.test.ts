import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { isPast } from "../src/forums/forums";
import { bearerHeaders, callAPI, postJSON, requireAuthToken } from "./helpers";

const ava = "seed-ava";
const ben = "seed-ben";
const eli = "seed-eli";

interface Person {
  userId: string;
  name: string;
}

interface PostView {
  id: string;
  forumId: string;
  title: string;
  description: string | null;
  location: string | null;
  startsAt: string;
  endsAt: string | null;
  author: Person;
  attendeeCount: number;
  attendeePreview: Person[];
  attending: boolean;
  isAuthor: boolean;
  edited: boolean;
  past: boolean;
  cancelled: boolean;
}

type Headers = Record<string, string>;

beforeEach(async () => {
  await env.DB.prepare("DELETE FROM rate_limit").run();
  await postJSON("/api/dev/reset", {});
  await postJSON("/api/dev/seed", {});
});

async function signInAs(userId: string): Promise<Headers> {
  const response = await postJSON("/api/auth/sign-in/email", {
    email: `${userId.replace("seed-", "")}@seed.face2face.test`,
    password: "face2face-seed-password",
  });
  return bearerHeaders(requireAuthToken(response));
}

function send(headers: Headers, method: string, path: string, body?: unknown) {
  return callAPI(path, {
    method,
    headers: { ...headers, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

async function createPost(
  headers: Headers,
  forumId: string,
  body: Record<string, unknown>,
) {
  const response = await send(headers, "POST", `/api/forums/${forumId}/posts`, {
    startsAt: "2030-01-01T09:00:00Z",
    ...body,
  });
  expect(response.status).toBe(201);
  return (await response.json<{ post: PostView }>()).post;
}

async function readPost(headers: Headers, postId: string) {
  const response = await callAPI(`/api/posts/${postId}`, { headers });
  expect(response.status).toBe(200);
  return (await response.json<{ post: PostView }>()).post;
}

async function inbox(userId: string) {
  const response = await callAPI(`/api/dev/users/${userId}/notifications`);
  return (await response.json<{ notifications: Record<string, unknown>[] }>())
    .notifications;
}

async function inboxFor(userId: string, postId: string) {
  return (await inbox(userId))
    .filter((notification) => notification.postId === postId)
    .map((notification) => notification.kind);
}

describe("event timing", () => {
  const now = new Date("2026-10-24T12:00:00Z");
  const before = new Date("2026-10-24T11:00:00Z");
  const after = new Date("2026-10-24T13:00:00Z");

  it("ends at the end time, or at the start time without one", () => {
    expect(isPast({ startsAt: before, endsAt: after }, now)).toBe(false);
    expect(isPast({ startsAt: before, endsAt: before }, now)).toBe(true);
    expect(isPast({ startsAt: before, endsAt: null }, now)).toBe(true);
    expect(isPast({ startsAt: after, endsAt: null }, now)).toBe(false);
  });
});

describe("forums API", () => {
  it("lists only the forums of the person's interests", async () => {
    const response = await callAPI("/api/forums", {
      headers: await signInAs(ava),
    });
    const { forums } = await response.json<{
      forums: { id: string; interestName: string }[];
    }>();
    expect(forums.map((forum) => forum.id)).toEqual([
      "climbing",
      "coffee",
      "film",
      "hiking",
      "photography",
    ]);
  });

  it("hides forums and posts from people outside the interest", async () => {
    const avaHeaders = await signInAs(ava);
    const eliHeaders = await signInAs(eli);
    const post = await createPost(avaHeaders, "coffee", { title: "Espresso" });

    expect(
      (await callAPI("/api/forums/coffee/posts", { headers: eliHeaders }))
        .status,
    ).toBe(404);
    expect(
      (
        await send(eliHeaders, "POST", "/api/forums/coffee/posts", {
          title: "Nope",
          startsAt: "2030-01-01T09:00:00Z",
        })
      ).status,
    ).toBe(404);
    expect(
      (await callAPI(`/api/posts/${post.id}`, { headers: eliHeaders })).status,
    ).toBe(404);
    expect(
      (await send(eliHeaders, "PUT", `/api/posts/${post.id}/rsvp`)).status,
    ).toBe(404);
  });

  it("creates a post with optional fields cleared to null", async () => {
    const post = await createPost(await signInAs(ava), "coffee", {
      title: "  Latte art  ",
      description: "",
      location: "Main St café",
      startsAt: "2030-01-01T10:00:00Z",
    });
    expect(post).toMatchObject({
      forumId: "coffee",
      title: "Latte art",
      description: null,
      location: "Main St café",
      startsAt: "2030-01-01T10:00:00.000Z",
      endsAt: null,
      author: { userId: ava, name: "Ava" },
      attendeeCount: 0,
      isAuthor: true,
      edited: false,
      past: false,
      cancelled: false,
    });
  });

  it("rejects bad posts", async () => {
    const headers = await signInAs(ava);
    const path = "/api/forums/coffee/posts";
    expect((await send(headers, "POST", path, {})).status).toBe(400);
    expect(
      (await send(headers, "POST", path, { title: "Someday" })).status,
    ).toBe(400);
    const startsAt = "2030-01-01T09:00:00Z";
    for (const title of ["  ", "x".repeat(121)]) {
      expect(
        (await send(headers, "POST", path, { title, startsAt })).status,
      ).toBe(400);
    }
    const backwards = await send(headers, "POST", path, {
      title: "Backwards",
      startsAt: "2030-01-01T12:00:00Z",
      endsAt: "2030-01-01T10:00:00Z",
    });
    expect(backwards.status).toBe(400);
    expect(await backwards.json()).toEqual({ error: "invalid_times" });
  });

  it("pages the feed newest first and leaves out cancelled posts", async () => {
    const headers = await signInAs(ava);
    const ids: string[] = [];
    for (const title of ["one", "two", "three"]) {
      ids.push((await createPost(headers, "coffee", { title })).id);
    }
    expect((await send(headers, "DELETE", `/api/posts/${ids[1]}`)).status).toBe(
      200,
    );

    const first = await callAPI("/api/forums/coffee/posts?limit=1", {
      headers,
    });
    const page = await first.json<{ posts: PostView[]; hasMore: boolean }>();
    expect(page.posts.map((post) => post.title)).toEqual(["three"]);
    expect(page.hasMore).toBe(true);

    const second = await callAPI(
      `/api/forums/coffee/posts?limit=5&before=${ids[2]}`,
      { headers },
    );
    const rest = await second.json<{ posts: PostView[]; hasMore: boolean }>();
    expect(rest.posts.map((post) => post.title)).toEqual(["one"]);
    expect(rest.hasMore).toBe(false);
  });
});

describe("RSVPs", () => {
  it("counts attendees, shows a preview, and tells the author", async () => {
    const avaHeaders = await signInAs(ava);
    const benHeaders = await signInAs(ben);
    const post = await createPost(avaHeaders, "coffee", { title: "Cupping" });

    const attend = await send(benHeaders, "PUT", `/api/posts/${post.id}/rsvp`);
    expect(attend.status).toBe(200);
    const attended = (await attend.json<{ post: PostView }>()).post;
    expect(attended).toMatchObject({ attending: true, attendeeCount: 1 });
    expect(attended.attendeePreview.map((person) => person.name)).toEqual([
      "Ben",
    ]);

    await send(benHeaders, "PUT", `/api/posts/${post.id}/rsvp`);
    await send(avaHeaders, "PUT", `/api/posts/${post.id}/rsvp`);
    const both = await readPost(avaHeaders, post.id);
    expect(both.attendeeCount).toBe(2);
    expect(both.attendeePreview.map((person) => person.name)).toEqual([
      "Ben",
      "Ava",
    ]);
    expect(await inboxFor(ava, post.id)).toEqual(["post_rsvp"]);

    const attendees = await callAPI(`/api/posts/${post.id}/attendees`, {
      headers: benHeaders,
    });
    expect(
      (await attendees.json<{ attendees: Person[] }>()).attendees.map(
        (person) => person.userId,
      ),
    ).toEqual([ben, ava]);

    const leave = await send(
      benHeaders,
      "DELETE",
      `/api/posts/${post.id}/rsvp`,
    );
    expect((await leave.json<{ post: PostView }>()).post).toMatchObject({
      attending: false,
      attendeeCount: 1,
    });
  });

  it("refuses RSVPs to past and cancelled events", async () => {
    const avaHeaders = await signInAs(ava);
    const benHeaders = await signInAs(ben);
    const past = await createPost(avaHeaders, "coffee", {
      title: "Yesterday",
      startsAt: "2020-01-01T10:00:00Z",
    });
    expect(past.past).toBe(true);
    const late = await send(benHeaders, "PUT", `/api/posts/${past.id}/rsvp`);
    expect(late.status).toBe(409);
    expect(await late.json()).toEqual({ error: "event_over" });

    const gone = await createPost(avaHeaders, "coffee", { title: "Gone" });
    await send(avaHeaders, "DELETE", `/api/posts/${gone.id}`);
    const cancelled = await send(
      benHeaders,
      "PUT",
      `/api/posts/${gone.id}/rsvp`,
    );
    expect(cancelled.status).toBe(409);
    expect(await cancelled.json()).toEqual({ error: "post_cancelled" });
  });
});

describe("editing and cancelling", () => {
  it("lets only the author edit, and tells attendees", async () => {
    const avaHeaders = await signInAs(ava);
    const benHeaders = await signInAs(ben);
    const post = await createPost(avaHeaders, "hiking", {
      title: "Ridge walk",
      startsAt: "2030-06-01T08:00:00Z",
    });
    await send(benHeaders, "PUT", `/api/posts/${post.id}/rsvp`);

    const stranger = await send(benHeaders, "PATCH", `/api/posts/${post.id}`, {
      title: "Mine now",
    });
    expect(stranger.status).toBe(403);

    expect(
      (await send(avaHeaders, "PATCH", `/api/posts/${post.id}`, {})).status,
    ).toBe(400);
    const backwards = await send(avaHeaders, "PATCH", `/api/posts/${post.id}`, {
      endsAt: "2030-06-01T07:00:00Z",
    });
    expect(backwards.status).toBe(400);

    const edit = await send(avaHeaders, "PATCH", `/api/posts/${post.id}`, {
      location: "North trailhead",
      description: "Bring water",
    });
    expect(edit.status).toBe(200);
    expect((await edit.json<{ post: PostView }>()).post).toMatchObject({
      title: "Ridge walk",
      location: "North trailhead",
      description: "Bring water",
      edited: true,
    });
    expect(await inboxFor(ben, post.id)).toEqual(["post_updated"]);
    expect(await inboxFor(ava, post.id)).toEqual(["post_rsvp"]);
  });

  it("soft-deletes, keeps the post readable, and tells attendees", async () => {
    const avaHeaders = await signInAs(ava);
    const benHeaders = await signInAs(ben);
    const post = await createPost(avaHeaders, "hiking", { title: "Summit" });
    await send(benHeaders, "PUT", `/api/posts/${post.id}/rsvp`);

    expect(
      (await send(benHeaders, "DELETE", `/api/posts/${post.id}`)).status,
    ).toBe(403);
    expect(
      (await send(avaHeaders, "DELETE", `/api/posts/${post.id}`)).status,
    ).toBe(200);

    const cancelled = await readPost(benHeaders, post.id);
    expect(cancelled).toMatchObject({ cancelled: true, attendeeCount: 1 });
    expect(await inboxFor(ben, post.id)).toEqual(["post_cancelled"]);

    const again = await send(avaHeaders, "PATCH", `/api/posts/${post.id}`, {
      title: "Back on",
    });
    expect(again.status).toBe(409);
    expect(await again.json()).toEqual({ error: "post_cancelled" });
  });
});

describe("upcoming posts across forums", () => {
  async function upcoming(headers: Headers, query = "") {
    const response = await callAPI(`/api/posts${query}`, { headers });
    expect(response.status).toBe(200);
    return response.json<{ posts: PostView[]; hasMore: boolean }>();
  }

  it("lists upcoming posts from the person's forums, soonest first", async () => {
    const avaHeaders = await signInAs(ava);
    const benHeaders = await signInAs(ben);
    const eliHeaders = await signInAs(eli);
    await createPost(benHeaders, "coffee", {
      title: "Coffee in March",
      startsAt: "2030-03-01T09:00:00Z",
    });
    await createPost(avaHeaders, "hiking", {
      title: "Hike in January",
      startsAt: "2030-01-01T09:00:00Z",
    });
    await createPost(benHeaders, "hiking", {
      title: "Long over",
      startsAt: "2020-01-01T09:00:00Z",
    });
    await createPost(benHeaders, "coffee", {
      title: "Still going",
      startsAt: "2020-01-01T09:00:00Z",
      endsAt: "2099-01-01T09:00:00Z",
    });
    const cancelled = await createPost(benHeaders, "coffee", {
      title: "Called off",
      startsAt: "2030-02-01T09:00:00Z",
    });
    await send(benHeaders, "DELETE", `/api/posts/${cancelled.id}`);
    await createPost(eliHeaders, "board-games", {
      title: "Not Ava's forum",
      startsAt: "2030-01-15T09:00:00Z",
    });

    const page = await upcoming(avaHeaders);
    expect(page.posts.map((post) => post.title)).toEqual([
      "Still going",
      "Hike in January",
      "Coffee in March",
    ]);
    expect(page.hasMore).toBe(false);
  });

  it("pages with the last post ID", async () => {
    const headers = await signInAs(ava);
    for (const [title, month] of [
      ["first", "01"],
      ["second", "02"],
      ["third", "03"],
    ]) {
      await createPost(headers, "coffee", {
        title,
        startsAt: `2030-${month}-01T09:00:00Z`,
      });
    }

    const first = await upcoming(headers, "?limit=2");
    expect(first.posts.map((post) => post.title)).toEqual(["first", "second"]);
    expect(first.hasMore).toBe(true);

    const rest = await upcoming(
      headers,
      `?limit=2&after=${first.posts[1]?.id}`,
    );
    expect(rest.posts.map((post) => post.title)).toEqual(["third"]);
    expect(rest.hasMore).toBe(false);

    expect((await callAPI("/api/posts?limit=0", { headers })).status).toBe(400);
  });
});

describe("seeded forum data", () => {
  it("fills forums and can run again", async () => {
    for (let run = 0; run < 2; run++) {
      const response = await postJSON("/api/dev/forums/seed", {});
      expect(response.status).toBe(200);
    }
    const headers = await signInAs(ava);
    const response = await callAPI("/api/posts?limit=50", { headers });
    const { posts } = await response.json<{ posts: PostView[] }>();
    const titles = posts.map((post) => post.title);
    expect(titles[0]).toBe("Drop-in bouldering");
    expect(titles).toContain("Latte art throwdown");
    expect(titles).not.toContain("Cupping session");
    expect(titles).not.toContain("Catan and pizza night");

    const latteArt = posts.find((post) => post.title === "Latte art throwdown");
    expect(latteArt).toMatchObject({ attendeeCount: 2, attending: true });
  });
});
