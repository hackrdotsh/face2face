import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../app-env";
import { createDatabase, type Database } from "../db/client";
import {
  addUserInterest,
  countInterestsCreatedSince,
  countUserInterests,
  createInterest,
  findInterestByName,
  interestNameProblem,
  listInterestChoices,
  normalizeInterestName,
  replaceUserInterests,
} from "../interests/interest-store";
import { requireOnboarded, requireSession } from "../middleware/session";

const maxInterestsPerPerson = 10;
const maxCreatedPerDay = 5;
const day = 24 * 60 * 60 * 1000;

const replaceRequest = z.object({
  interestIds: z
    .array(z.string().min(1))
    .max(maxInterestsPerPerson)
    .refine((ids) => new Set(ids).size === ids.length),
});

const addRequest = z.object({ name: z.string().max(200) });

async function interestList(db: Database, userId: string) {
  return {
    maxSelected: maxInterestsPerPerson,
    interests: await listInterestChoices(db, userId),
  };
}

/** The signed-in person's interests, chosen from the `interest` list. */
export const interestRoutes = new Hono<AppEnv>()
  .use(requireSession, requireOnboarded)
  .get("/", async (context) =>
    context.json(
      await interestList(createDatabase(context.env), context.var.user.id),
    ),
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
    return context.json(await interestList(db, userId));
  })
  /**
   * Selects the interest with this name, creating it when none exists.
   * Names match after `normalizeInterestName`.
   */
  .post("/", async (context) => {
    const request = addRequest.safeParse(
      await context.req.json().catch(() => undefined),
    );
    if (!request.success) {
      return context.json({ error: "invalid_request" }, 400);
    }
    const name = normalizeInterestName(request.data.name);
    const problem = interestNameProblem(name);
    if (problem) {
      return context.json(
        { error: "invalid_fields", fields: { name: problem } },
        400,
      );
    }
    const db = createDatabase(context.env);
    const userId = context.var.user.id;
    const now = new Date();
    const existing = await findInterestByName(db, name);
    if ((await countUserInterests(db, userId)) >= maxInterestsPerPerson) {
      const choices = await listInterestChoices(db, userId);
      const alreadySelected = choices.some(
        (choice) => choice.id === existing?.id && choice.selected,
      );
      if (!alreadySelected) {
        return context.json({ error: "too_many_interests" }, 409);
      }
    }
    let interestId = existing?.id;
    if (!interestId) {
      const created = await countInterestsCreatedSince(
        db,
        userId,
        new Date(now.getTime() - day),
      );
      if (created >= maxCreatedPerDay) {
        context.header("Retry-After", String(day / 1000));
        return context.json({ error: "rate_limited" }, 429);
      }
      interestId = await createInterest(db, userId, name, now);
    }
    await addUserInterest(db, userId, interestId, now);
    return context.json({ interestId, ...(await interestList(db, userId)) });
  });
