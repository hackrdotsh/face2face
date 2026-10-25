import { createMiddleware } from "hono/factory";
import type { AppEnv } from "../app-env";
import { createAuth } from "../auth";
import { createDatabase } from "../db/client";
import { onboardingFields } from "../onboarding/fields";
import { getOnboardingState } from "../onboarding/onboarding";
import { photoViewer } from "../profiles/person";

export const requireSession = createMiddleware<AppEnv>(
  async (context, next) => {
    const session = await createAuth(
      context.env,
      context.executionCtx,
    ).api.getSession({ headers: context.req.raw.headers });
    if (!session) return context.json({ error: "unauthorized" }, 401);
    context.set("user", session.user);
    context.set("authSession", session.session);
    await next();
  },
);

export const requireOnboarded = createMiddleware<AppEnv>(
  async (context, next) => {
    const now = new Date();
    const state = await getOnboardingState(
      createDatabase(context.env),
      photoViewer(context.env, now),
      onboardingFields,
      context.var.user.id,
      now,
    );
    if (!state.complete) {
      return context.json({ error: "onboarding_required" }, 403);
    }
    await next();
  },
);
