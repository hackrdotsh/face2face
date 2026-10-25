#!/usr/bin/env node
// Reuse the isolated Worker/database lifecycle instead of resetting the shared dev server.
process.argv.push("--forums");
await import("./chat-smoke.mjs");
