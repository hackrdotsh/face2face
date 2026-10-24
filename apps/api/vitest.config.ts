import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

const migrations = await readD1Migrations("./migrations");

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        bindings: {
          DEV_WEB_ORIGIN: "http://100.100.20.30:3000",
          BETTER_AUTH_SECRET: "test-only-secret-not-for-production-123456789",
          TEST_MIGRATIONS: migrations,
        },
      },
    }),
  ],
  test: { testTimeout: 15000, setupFiles: ["./test/apply-migrations.ts"] },
});
