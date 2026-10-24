import { Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import { cors } from "hono/cors";
import { HTTPException } from "hono/http-exception";
import { secureHeaders } from "hono/secure-headers";
import { createAuth } from "./auth";
import { webOrigins } from "./origins";

export { UserCoordinator } from "./user-coordinator";

const app = new Hono<{ Bindings: Env }>();

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
    allowMethods: ["GET", "POST", "OPTIONS"],
  })(context, next),
);
app.use("/api/*", bodyLimit({ maxSize: 16 * 1024 }));

app.get("/health", (context) =>
  context.json({ status: "ok", service: "face2face-api" }),
);
app.on(["GET", "POST"], "/api/auth/*", (context) =>
  createAuth(context.env).handler(context.req.raw),
);
app.get("/api/me", async (context) => {
  const session = await createAuth(context.env).api.getSession({
    headers: context.req.raw.headers,
  });
  if (!session) return context.json({ error: "unauthorized" }, 401);
  return context.json({
    user: { id: session.user.id, name: session.user.name },
  });
});
app.get("/api/coordinator", async (context) => {
  const session = await createAuth(context.env).api.getSession({
    headers: context.req.raw.headers,
  });
  if (!session) return context.json({ error: "unauthorized" }, 401);
  const coordinator = context.env.USER_COORDINATORS.getByName(session.user.id);
  return context.json(await coordinator.status());
});
app.notFound((context) => context.json({ error: "not_found" }, 404));
app.onError((error, context) => {
  if (error instanceof HTTPException) return error.getResponse();
  console.error(JSON.stringify({ event: "request_failed", name: error.name }));
  return context.json({ error: "internal_error" }, 500);
});

export default app;
