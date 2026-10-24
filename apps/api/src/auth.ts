import { passkey } from "@better-auth/passkey";
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { bearer, emailOTP } from "better-auth/plugins";
import { createDatabase } from "./db/client";
import * as schema from "./db/schema";
import { createOTPEmail } from "./email/otp-email";
import { createEmailSender } from "./email/send-email";
import { webOrigins } from "./origins";

const otpExpiresInSeconds = 10 * 60;

export function createAuth(
  env: Env,
  executionContext?: Pick<ExecutionContext, "waitUntil">,
) {
  const sendEmail = createEmailSender(env);
  return betterAuth({
    appName: "face2face",
    baseURL: env.BETTER_AUTH_URL,
    secret: env.BETTER_AUTH_SECRET,
    database: drizzleAdapter(createDatabase(env), {
      provider: "sqlite",
      schema,
      transaction: false,
    }),
    trustedOrigins: ["face2face://", ...webOrigins(env)],
    emailAndPassword: {
      enabled: true,
      minPasswordLength: 12,
      requireEmailVerification: true,
      revokeSessionsOnPasswordReset: true,
    },
    emailVerification: {
      autoSignInAfterVerification: true,
      sendOnSignIn: true,
    },
    plugins: [
      bearer({ requireSignature: true }),
      emailOTP({
        expiresIn: otpExpiresInSeconds,
        sendVerificationOnSignUp: true,
        overrideDefaultEmailVerification: true,
        storeOTP: "hashed",
        sendVerificationOTP: ({ email, otp, type }) =>
          sendEmail(createOTPEmail(email, otp, type, otpExpiresInSeconds / 60)),
      }),
      passkey({
        rpID: env.PASSKEY_RP_ID,
        rpName: "face2face",
        origin: env.PASSKEY_ORIGINS,
      }),
    ],
    rateLimit: { enabled: true, storage: "database" },
    advanced: executionContext && {
      backgroundTasks: { handler: (task) => executionContext.waitUntil(task) },
    },
  });
}
