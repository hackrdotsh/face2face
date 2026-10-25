#!/usr/bin/env node
import { spawn, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, openSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const forums = process.argv.includes("--forums");
const encounters = process.argv.includes("--encounters");
const mode = forums ? "forums" : encounters ? "encounters" : "chat";
const env = {
  ...process.env,
  DEVELOPER_DIR:
    process.env.DEVELOPER_DIR || "/Applications/Xcode.app/Contents/Developer",
};
const tempRoot = resolve(tmpdir(), "opencode");
mkdirSync(tempRoot, { recursive: true });
const directory = mkdtempSync(resolve(tempRoot, `${mode}-smoke-`));
const log = resolve(directory, "worker.log");
const fd = openSync(log, "a", 0o600);
let worker;
try {
  const listener = createServer();
  await new Promise((resolve, reject) => {
    listener.once("error", reject);
    listener.listen(0, "127.0.0.1", resolve);
  });
  const port = listener.address().port;
  await new Promise((resolve) => listener.close(resolve));
  const base = `http://127.0.0.1:${port}`;
  const common = ["--filter", "@face2face/api", "exec", "wrangler"];
  const migrated = spawnSync(
    "pnpm",
    [
      ...common,
      "d1",
      "migrations",
      "apply",
      "DB",
      "--local",
      "--persist-to",
      directory,
    ],
    {
      cwd: root,
      env,
      stdio: ["ignore", fd, fd],
    },
  );
  if (migrated.status !== 0)
    throw new Error(`Isolated database setup failed. See ${log}`);
  worker = spawn(
    "pnpm",
    [
      ...common,
      "dev",
      "--ip",
      "127.0.0.1",
      "--port",
      String(port),
      "--persist-to",
      directory,
      "--var",
      `BETTER_AUTH_URL:${base}`,
    ],
    { cwd: root, env, detached: true, stdio: ["ignore", fd, fd] },
  );
  let ready = false;
  for (let attempt = 0; attempt < 100; attempt++) {
    try {
      const response = await fetch(`${base}/health`, {
        signal: AbortSignal.timeout(500),
      });
      if (response.ok) {
        ready = true;
        break;
      }
    } catch {}
    await delay(200);
  }
  if (!ready) throw new Error(`Worker did not start. See ${log}`);
  console.log(
    `Testing real Swift ${mode} clients against isolated Worker ${base}`,
  );
  const test = spawnSync(
    "xcrun",
    [
      "swift",
      "test",
      "--package-path",
      "apps/ios/Face2FaceCore",
      "--filter",
      forums
        ? "liveForumRoundTrip"
        : encounters
          ? "liveEncounterRoundTrip"
          : "liveChatRoundTrip",
    ],
    {
      cwd: root,
      env: {
        ...env,
        [forums
          ? "F2F_FORUM_SMOKE_URL"
          : encounters
            ? "F2F_ENCOUNTER_SMOKE_URL"
            : "F2F_CHAT_SMOKE_URL"]: base,
      },
      stdio: "inherit",
    },
  );
  if (test.status !== 0)
    throw new Error(`Live ${mode} verification failed. Worker log: ${log}`);
  console.log(
    forums
      ? "Verified: interest membership, event create/edit/cancel, RSVP idempotency, attendees, notifications and access denial."
      : encounters
        ? "Verified: anonymous chances, decline closure, one-sided acceptance without chat, mutual acceptance with chat and outsider denial."
        : "Verified: two-way text/photos, signed media, idempotent retry, typing, unread clearing, mutual profile sharing, public friends, receive cancellation and block closure.",
  );
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  if (worker?.pid) {
    try {
      process.kill(-worker.pid, "SIGTERM");
    } catch {}
  }
}
