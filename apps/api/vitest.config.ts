import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        bindings: {
          DEV_WEB_ORIGIN: "http://100.100.20.30:8081",
          BETTER_AUTH_SECRET: "test-only-secret-not-for-production-123456789",
        },
      },
    }),
  ],
  test: { testTimeout: 15000 },
});
