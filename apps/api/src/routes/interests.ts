import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../app-env";
import { createDatabase } from "../db/client";
import {
  listInterestChoices,
  replaceUserInterests,
} from "../interests/interest-store";
import { requireOnboarded, requireSession } from "../middleware/session";

const maxInterestsPerPerson = 10;

const replaceRequest = z.object({
  interestIds: z
    .array(z.string().min(1))
    .max(maxInterestsPerPerson)
    .refine((ids) => new Set(ids).size === ids.length),
});

/** The signed-in person's interests, chosen from the `interest` list. */
export const interestRoutes = new Hono<AppEnv>()
  .use(requireSession, requireOnboarded)
  .get("/", async (context) =>
    context.json({
      maxSelected: maxInterestsPerPerson,
      interests: await listInterestChoices(
        createDatabase(context.env),
        context.var.user.id,
      ),
    }),
  )
  .put("/", async (context) => {
    const request = replaceRequest.safeParse(
      await context.req.json().catch(() => undefined),
    );
    if (!request.success) {
      return context.json({ error: "invalid_request" }, 400);
    }
    const db = createDatabase(context.env);
    const userId = context.var.user.id;
    const known = new Set(
      (await listInterestChoices(db, userId)).map((choice) => choice.id),
    );
    if (!request.data.interestIds.every((id) => known.has(id))) {
      return context.json({ error: "unknown_interest" }, 400);
    }
    await replaceUserInterests(
      db,
      userId,
      request.data.interestIds,
      new Date(),
    );
    return context.json({
      maxSelected: maxInterestsPerPerson,
      interests: await listInterestChoices(db, userId),
    });
  });
