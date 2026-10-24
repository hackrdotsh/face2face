import { createMiddleware } from "hono/factory";
import type { AppEnv } from "../app-env";
import { createAuth } from "../auth";
import { createDatabase } from "../db/client";
import { onboardingFields } from "../onboarding/fields";
import { getOnboardingState } from "../onboarding/onboarding";

export const requireSession = createMiddleware<AppEnv>(
  async (context, next) => {
    const session = await createAuth(
      context.env,
      context.executionCtx,
    ).api.getSession({ headers: context.req.raw.headers });
    if (!session) return context.json({ error: "unauthorized" }, 401);
    context.set("user", session.user);
    await next();
  },
);

export const requireOnboarded = createMiddleware<AppEnv>(
  async (context, next) => {
    const state = await getOnboardingState(
      createDatabase(context.env),
      onboardingFields,
      context.var.user.id,
      new Date(),
    );
    if (!state.complete) {
      return context.json({ error: "onboarding_required" }, 403);
    }
    await next();
  },
);
