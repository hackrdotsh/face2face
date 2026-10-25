import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../app-env";
import { createDatabase } from "../db/client";
import { requireSession } from "../middleware/session";
import { onboardingFields } from "../onboarding/fields";
import { getOnboardingState, updateOnboarding } from "../onboarding/onboarding";
import { photoViewer } from "../profiles/person";

const updateRequest = z.object({ values: z.record(z.string(), z.unknown()) });

export const onboardingRoutes = new Hono<AppEnv>()
  .use(requireSession)
  .get("/", async (context) =>
    context.json(
      await getOnboardingState(
        createDatabase(context.env),
        photoViewer(context.env, new Date()),
        onboardingFields,
        context.var.user.id,
        new Date(),
      ),
    ),
  )
  .patch("/", async (context) => {
    const request = updateRequest.safeParse(
      await context.req.json().catch(() => undefined),
    );
    if (!request.success)
      return context.json({ error: "invalid_request" }, 400);
    const result = await updateOnboarding(
      createDatabase(context.env),
      photoViewer(context.env, new Date()),
      onboardingFields,
      context.var.user.id,
      request.data.values,
      new Date(),
    );
    if (!result.ok) {
      return context.json(
        { error: "invalid_fields", fields: result.fieldErrors },
        400,
      );
    }
    return context.json(result.state);
  });
