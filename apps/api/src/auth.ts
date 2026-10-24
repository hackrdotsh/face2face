import { expo } from "@better-auth/expo";
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { drizzle } from "drizzle-orm/d1";
import * as schema from "./db/schema";

export function createAuth(env: Env) {
  return betterAuth({
    appName: "face2face",
    baseURL: env.BETTER_AUTH_URL,
    secret: env.BETTER_AUTH_SECRET,
    database: drizzleAdapter(drizzle(env.DB, { schema }), {
      provider: "sqlite",
      schema,
      transaction: false,
    }),
    trustedOrigins: ["face2face://", ...env.WEB_ORIGINS],
    emailAndPassword: { enabled: true, minPasswordLength: 12 },
    plugins: [expo()],
    rateLimit: { enabled: true, storage: "database" },
  });
}
