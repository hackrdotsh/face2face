import { type Context, Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../app-env";
import { createDatabase } from "../db/client";
import {
  postDescriptionMaxLength,
  postLocationMaxLength,
  postTitleMaxLength,
} from "../db/schema";
import {
  findForumFor,
  listAttendees,
  listForumPosts,
  listForumsFor,
  listUpcomingPosts,
} from "../forums/forum-store";
import {
  attendPost,
  cancelPost,
  createPost,
  editPost,
  getPostView,
  leavePost,
  type PostActionResult,
  timesInOrder,
  viewPostRows,
} from "../forums/forums";
import { requireOnboarded, requireSession } from "../middleware/session";
import { coordinatorNotifier } from "../notifications/notification";

const defaultPageSize = 20;
const maxPageSize = 50;

const limit = z.coerce
  .number()
  .int()
  .min(1)
  .max(maxPageSize)
  .default(defaultPageSize);

const newestFirstQuery = z.object({
  before: z.string().min(1).optional(),
  limit,
});

const soonestFirstQuery = z.object({
  after: z.string().min(1).optional(),
  limit,
});

/** A blank string clears the field. */
function optionalText(maxLength: number) {
  return z
    .string()
    .trim()
    .max(maxLength)
    .nullable()
    .transform((value) => (value ? value : null));
}

const time = z.iso
  .datetime({ offset: true })
  .transform((value) => new Date(value));

const postFields = {
  title: z.string().trim().min(1).max(postTitleMaxLength),
  description: optionalText(postDescriptionMaxLength),
  location: optionalText(postLocationMaxLength),
  startsAt: time,
  endsAt: time.nullable(),
};

const createRequest = z.object({
  title: postFields.title,
  description: postFields.description.default(null),
  location: postFields.location.default(null),
  startsAt: postFields.startsAt,
  endsAt: postFields.endsAt.default(null),
});

const editRequest = z
  .object(postFields)
  .partial()
  .refine((changes) => Object.keys(changes).length > 0);

async function readJSON(context: Context<AppEnv>) {
  return context.req.json().catch(() => undefined);
}

function respond(context: Context<AppEnv>, result: PostActionResult) {
  if (result.ok) return context.json({ post: result.post });
  switch (result.error) {
    case "not_found":
      return context.json({ error: "not_found" }, 404);
    case "not_author":
      return context.json({ error: "not_author" }, 403);
    case "invalid_times":
      return context.json({ error: "invalid_times" }, 400);
    default:
      return context.json({ error: result.error }, 409);
  }
}

/** Forums of the signed-in person's interests. Other forums answer 404. */
export const forumRoutes = new Hono<AppEnv>()
  .use(requireSession, requireOnboarded)
  .get("/", async (context) =>
    context.json({
      forums: await listForumsFor(
        createDatabase(context.env),
        context.var.user.id,
        new Date(),
      ),
    }),
  )
  .get("/:id/posts", async (context) => {
    const query = newestFirstQuery.safeParse(context.req.query());
    if (!query.success) return context.json({ error: "invalid_request" }, 400);
    const db = createDatabase(context.env);
    const userId = context.var.user.id;
    const forumId = context.req.param("id");
    if (!(await findForumFor(db, forumId, userId))) {
      return context.json({ error: "not_found" }, 404);
    }
    const page = await listForumPosts(
      db,
      forumId,
      userId,
      query.data.before,
      query.data.limit,
    );
    return context.json({
      posts: await viewPostRows(db, page.rows, userId, new Date()),
      hasMore: page.hasMore,
    });
  })
  .post("/:id/posts", async (context) => {
    const request = createRequest.safeParse(await readJSON(context));
    if (!request.success) {
      return context.json({ error: "invalid_request" }, 400);
    }
    if (!timesInOrder(request.data)) {
      return context.json({ error: "invalid_times" }, 400);
    }
    const db = createDatabase(context.env);
    const userId = context.var.user.id;
    const forumId = context.req.param("id");
    if (!(await findForumFor(db, forumId, userId))) {
      return context.json({ error: "not_found" }, 404);
    }
    const post = await createPost(
      db,
      forumId,
      userId,
      request.data,
      new Date(),
    );
    return context.json({ post }, 201);
  });

/**
 * Posts in the signed-in person's forums. `GET /` lists the upcoming ones
 * across all of them. Other posts answer 404.
 */
export const postRoutes = new Hono<AppEnv>()
  .use(requireSession, requireOnboarded)
  .get("/", async (context) => {
    const query = soonestFirstQuery.safeParse(context.req.query());
    if (!query.success) return context.json({ error: "invalid_request" }, 400);
    const db = createDatabase(context.env);
    const userId = context.var.user.id;
    const now = new Date();
    const page = await listUpcomingPosts(
      db,
      userId,
      query.data.after,
      query.data.limit,
      now,
    );
    return context.json({
      posts: await viewPostRows(db, page.rows, userId, now),
      hasMore: page.hasMore,
    });
  })
  .get("/:id", async (context) => {
    const post = await getPostView(
      createDatabase(context.env),
      context.req.param("id"),
      context.var.user.id,
      new Date(),
    );
    if (!post) return context.json({ error: "not_found" }, 404);
    return context.json({ post });
  })
  .patch("/:id", async (context) => {
    const request = editRequest.safeParse(await readJSON(context));
    if (!request.success) {
      return context.json({ error: "invalid_request" }, 400);
    }
    return respond(
      context,
      await editPost(
        createDatabase(context.env),
        coordinatorNotifier(context.env),
        context.req.param("id"),
        context.var.user.id,
        request.data,
        new Date(),
      ),
    );
  })
  .delete("/:id", async (context) =>
    respond(
      context,
      await cancelPost(
        createDatabase(context.env),
        coordinatorNotifier(context.env),
        context.req.param("id"),
        context.var.user.id,
        new Date(),
      ),
    ),
  )
  .get("/:id/attendees", async (context) => {
    const db = createDatabase(context.env);
    const postId = context.req.param("id");
    const post = await getPostView(db, postId, context.var.user.id, new Date());
    if (!post) return context.json({ error: "not_found" }, 404);
    return context.json({ attendees: await listAttendees(db, postId) });
  })
  .put("/:id/rsvp", async (context) =>
    respond(
      context,
      await attendPost(
        createDatabase(context.env),
        coordinatorNotifier(context.env),
        context.req.param("id"),
        context.var.user.id,
        new Date(),
      ),
    ),
  )
  .delete("/:id/rsvp", async (context) =>
    respond(
      context,
      await leavePost(
        createDatabase(context.env),
        context.req.param("id"),
        context.var.user.id,
        new Date(),
      ),
    ),
  );
