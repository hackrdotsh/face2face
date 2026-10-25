import { Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import { cors } from "hono/cors";
import { HTTPException } from "hono/http-exception";
import { secureHeaders } from "hono/secure-headers";
import type { AppEnv } from "./app-env";
import { createAuth } from "./auth";
import { createDatabase } from "./db/client";
import { mediaSecret } from "./media/signed-path";
import { requireOnboarded, requireSession } from "./middleware/session";
import { onboardingFields } from "./onboarding/fields";
import { getOnboardingState } from "./onboarding/onboarding";
import { webOrigins } from "./origins";
import { photoViewer, viewAvatar } from "./profiles/person";
import { findPhotoId } from "./profiles/photo-store";
import { chatRoutes } from "./routes/chats";
import { connectionRoutes } from "./routes/connections";
import { devRoutes } from "./routes/dev";
import { discoveryRoutes } from "./routes/discovery";
import { forumRoutes, postRoutes } from "./routes/forums";
import { interestRoutes } from "./routes/interests";
import { mediaRoutes } from "./routes/media";
import { notificationRoutes } from "./routes/notifications";
import { onboardingRoutes } from "./routes/onboarding";
import { profileRoutes } from "./routes/profile";

export { ChatRoom } from "./chats/chat-room";
export { UserCoordinator } from "./user-coordinator";

const app = new Hono<AppEnv>();

const pageHeaders = secureHeaders();
const mediaHeaders = secureHeaders({
  crossOriginResourcePolicy: "cross-origin",
});
const jsonBodyLimit = bodyLimit({ maxSize: 16 * 1024 });
const imageUploadPath = /^\/api\/(chats\/[^/]+\/images|profile\/photo)$/;

app.use("*", (context, next) =>
  context.req.path.startsWith("/media/")
    ? mediaHeaders(context, next)
    : pageHeaders(context, next),
);
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
    allowMethods: ["GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"],
  })(context, next),
);
app.use("/api/*", (context, next) =>
  imageUploadPath.test(context.req.path)
    ? next()
    : jsonBodyLimit(context, next),
);

app.get("/health", (context) =>
  context.json({ status: "ok", service: "face2face-api" }),
);
app.on(["GET", "POST"], "/api/auth/*", (context) =>
  createAuth(context.env, context.executionCtx).handler(context.req.raw),
);
app.get("/api/me", requireSession, async (context) => {
  const { id, name, email } = context.var.user;
  const db = createDatabase(context.env);
  const now = new Date();
  const [onboarding, photoId] = await Promise.all([
    getOnboardingState(
      db,
      photoViewer(context.env, now),
      onboardingFields,
      id,
      now,
    ),
    findPhotoId(db, id),
  ]);
  const avatar = await viewAvatar(mediaSecret(context.env), id, photoId, now);
  return context.json({
    user: { id, name, email, avatar },
    onboardingComplete: onboarding.complete,
  });
});
app.route("/api/onboarding", onboardingRoutes);
app.route("/api/profile", profileRoutes);
app.route("/api/interests", interestRoutes);
app.route("/api/connections", connectionRoutes);
app.route("/api/discovery", discoveryRoutes);
app.route("/api/notifications", notificationRoutes);
app.route("/api/chats", chatRoutes);
app.route("/api/forums", forumRoutes);
app.route("/api/posts", postRoutes);
app.route("/media", mediaRoutes);
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
