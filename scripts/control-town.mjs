#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const env = {
  ...process.env,
  DEVELOPER_DIR:
    process.env.DEVELOPER_DIR || "/Applications/Xcode.app/Contents/Developer",
};
const derived = resolve(tmpdir(), "opencode/town-control");
const [command, ...args] = process.argv.slice(2);
function run(bin, args, capture = false) {
  const result = spawnSync(bin, args, {
    cwd: root,
    env,
    encoding: "utf8",
    stdio: capture ? "pipe" : "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      `${bin} failed (${result.status}). ${result.stderr || "See output above. No later steps were run."}`,
    );
  }
  return result.stdout;
}
function build(destination, simulator) {
  run("xcodegen", [
    "generate",
    "--spec",
    "apps/ios/project.yml",
    "--project",
    "apps/ios",
  ]);
  run("xcodebuild", [
    "-project",
    "apps/ios/Face2Face.xcodeproj",
    "-scheme",
    "Face2Face",
    "-configuration",
    "Debug",
    "-destination",
    destination,
    "-derivedDataPath",
    derived,
    ...(simulator
      ? ["CODE_SIGNING_ALLOWED=NO"]
      : ["-allowProvisioningUpdates"]),
    "build",
  ]);
  const app = `${derived}/Build/Products/Debug-${simulator ? "iphonesimulator" : "iphoneos"}/Face2Face.app`;
  const bundle = run(
    "/usr/libexec/PlistBuddy",
    ["-c", "Print :CFBundleIdentifier", `${app}/Info.plist`],
    true,
  ).trim();
  return { app, bundle };
}
function simulator() {
  const data = JSON.parse(
    run("xcrun", ["simctl", "list", "devices", "booted", "--json"], true),
  );
  const device = Object.values(data.devices)
    .flat()
    .find((device) => device.state === "Booted");
  if (!device) throw new Error("Boot an iPhone simulator in Xcode first.");
  return device.udid;
}

try {
  switch (command) {
    case "doctor":
      run("xcrun", ["devicectl", "list", "devices"]);
      run("xcrun", ["simctl", "list", "devices", "booted"]);
      break;
    case "preview": {
      const device = simulator();
      const { app, bundle } = build(
        `platform=iOS Simulator,id=${device}`,
        true,
      );
      run("xcrun", ["simctl", "install", device, app]);
      run("xcrun", [
        "simctl",
        "launch",
        "--terminate-running-process",
        device,
        bundle,
        "-town-preview",
        ...args,
      ]);
      break;
    }
    case "screenshot": {
      if (!args[0])
        throw new Error(
          "Usage: node scripts/control-town.mjs screenshot <path> [device-udid]",
        );
      const path = resolve(args[0]);
      mkdirSync(resolve(path, ".."), { recursive: true });
      run(
        "xcrun",
        args[1]
          ? [
              "devicectl",
              "device",
              "capture",
              "screenshot",
              "--device",
              args[1],
              "--destination",
              path,
            ]
          : ["simctl", "io", simulator(), "screenshot", path],
      );
      break;
    }
    case "deploy": {
      if (!args[0])
        throw new Error(
          "Pass the target UDID explicitly. Prefer Minun; ask before using another phone.",
        );
      const { app, bundle } = build(`id=${args[0]}`, false);
      run("xcrun", [
        "devicectl",
        "device",
        "install",
        "app",
        "--device",
        args[0],
        app,
      ]);
      run("xcrun", [
        "devicectl",
        "device",
        "process",
        "launch",
        "--terminate-existing",
        "--device",
        args[0],
        bundle,
        "--",
        ...args.slice(1),
      ]);
      break;
    }
    default:
      console.log(`Town verification (macOS + Xcode + XcodeGen):
  doctor                              List physical devices and booted simulators
  preview [-town-destination forums]   Build, install and open an offline Debug preview
  screenshot <path> [device-udid]      Capture the booted simulator or specified phone
  deploy <device-udid> [app-arguments] Build, install and launch on an explicit phone

Preview never creates an account, saves a bearer token or contacts the API.
Use preview -town-chat preview-private for anonymous profile-sharing consent;
add -chat-sharing-preview-state peer-agreed or peer-later for mutual consent.
Use preview -connection-celebration-preview private or public for celebration art review.
Use -start-signed-out to test login without restoring or deleting saved credentials.
Omit -town-preview when verifying a real sign-in. Builds fail fast before install.`);
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
