#!/usr/bin/env node
// Controlled simulated encounters, isolated from the shared demo database.
process.argv.push("--encounters");
await import("./chat-smoke.mjs");
