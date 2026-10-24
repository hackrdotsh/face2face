import { Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import { cors } from "hono/cors";
import { HTTPException } from "hono/http-exception";
import { secureHeaders } from "hono/secure-headers";
import type { AppEnv } from "./app-env";
import { createAuth } from "./auth";
import { createDatabase } from "./db/client";
import { requireOnboarded, requireSession } from "./middleware/session";
import { onboardingFields } from "./onboarding/fields";
import { getOnboardingState } from "./onboarding/onboarding";
import { webOrigins } from "./origins";
import { connectionRoutes } from "./routes/connections";
import { devRoutes } from "./routes/dev";
import { interestRoutes } from "./routes/interests";
import { notificationRoutes } from "./routes/notifications";
import { onboardingRoutes } from "./routes/onboarding";

export { UserCoordinator } from "./user-coordinator";

const app = new Hono<AppEnv>();

app.use("*", secureHeaders());
app.use("/api/*", async (context, next) => {
  context.header("Cache-Control", "no-store");
  await next();
});
app.use("*", (context, next) =>
  cors({
    origin: webOrigins(context.env),
    credentials: true,
    allowHeaders: ["Content-Type", "Authorization"],
    exposeHeaders: ["set-auth-token"],
    allowMethods: ["GET", "POST", "PATCH", "PUT", "OPTIONS"],
  })(context, next),
);
app.use("/api/*", bodyLimit({ maxSize: 16 * 1024 }));

app.get("/health", (context) =>
  context.json({ status: "ok", service: "face2face-api" }),
);
app.on(["GET", "POST"], "/api/auth/*", (context) =>
  createAuth(context.env, context.executionCtx).handler(context.req.raw),
);
app.get("/api/me", requireSession, async (context) => {
  const { id, name, email } = context.var.user;
  const onboarding = await getOnboardingState(
    createDatabase(context.env),
    onboardingFields,
    id,
    new Date(),
  );
  return context.json({
    user: { id, name, email },
    onboardingComplete: onboarding.complete,
  });
});
app.route("/api/onboarding", onboardingRoutes);
app.route("/api/interests", interestRoutes);
app.route("/api/connections", connectionRoutes);
app.route("/api/notifications", notificationRoutes);
app.route("/api/dev", devRoutes);
app.get(
  "/api/coordinator",
  requireSession,
  requireOnboarded,
  async (context) => {
    const coordinator = context.env.USER_COORDINATORS.getByName(
      context.var.user.id,
    );
    return context.json(await coordinator.status());
  },
);
app.notFound((context) => context.json({ error: "not_found" }, 404));
app.onError((error, context) => {
  if (error instanceof HTTPException) return error.getResponse();
  console.error(JSON.stringify({ event: "request_failed", name: error.name }));
  return context.json({ error: "internal_error" }, 500);
});

export default app;
