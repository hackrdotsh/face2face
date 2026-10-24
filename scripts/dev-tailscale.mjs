import { spawn, spawnSync } from "node:child_process";
import { createServer, isIP } from "node:net";
import { fileURLToPath } from "node:url";

export function tailscaleURLs(output) {
  const address = output.trim();
  const [first, second] = address.split(".").map(Number);
  if (isIP(address) !== 4 || first !== 100 || second < 64 || second > 127) {
    throw new Error("Tailscale did not return a valid tailnet IPv4 address.");
  }
  return {
    address,
    api: `http://${address}:8787`,
    web: `http://${address}:8081`,
    expo: `exp://${address}:8081`,
  };
}

async function checkPort(host, port) {
  const server = createServer();
  await new Promise((resolve, reject) => {
    server.once("error", () =>
      reject(
        new Error(
          `Port ${port} is unavailable. Stop the existing dev server first.`,
        ),
      ),
    );
    server.listen(port, host, () => server.close(resolve));
  });
}

async function main() {
  if (process.argv.includes("--help")) {
    process.stdout.write(
      "Start Expo and the API on this machine's Tailscale address.\nUsage: pnpm dev:tailscale\n",
    );
    return;
  }
  if (process.argv.length > 2)
    throw new Error("Unknown argument. Use pnpm dev:tailscale --help.");

  const result = spawnSync("tailscale", ["ip", "--4"], { encoding: "utf8" });
  if (result.error || result.status !== 0) {
    throw new Error(
      "Cannot read the Tailscale address. Install Tailscale and connect this machine first.",
    );
  }
  const urls = tailscaleURLs(result.stdout);
  await checkPort("0.0.0.0", 8081);
  await checkPort(urls.address, 8787);

  const cwd = fileURLToPath(new URL("../", import.meta.url));
  const env = {
    ...process.env,
    EXPO_PUBLIC_API_URL: urls.api,
    EXPO_PACKAGER_PROXY_URL: urls.web,
    REACT_NATIVE_PACKAGER_HOSTNAME: urls.address,
  };
  process.stdout.write(
    `Expo Go: ${urls.expo}\nBrowser: ${urls.web}\nAPI: ${urls.api}\nConnect your phone to the same tailnet.\n`,
  );

  const children = new Set();
  let stopping = false;
  const signalChild = (child, signal) => {
    if (child.pid && child.exitCode === null && child.signalCode === null) {
      try {
        process.kill(-child.pid, signal);
      } catch (error) {
        if (
          !(error instanceof Error) ||
          !("code" in error) ||
          error.code !== "ESRCH"
        )
          throw error;
      }
    }
  };
  const stop = (signal, exitCode) => {
    if (stopping) return;
    stopping = true;
    process.exitCode = exitCode;
    for (const child of children) signalChild(child, signal);
    setTimeout(() => {
      for (const child of children) signalChild(child, "SIGKILL");
    }, 5000).unref();
  };
  const start = (args, interactive) => {
    const child = spawn("pnpm", args, {
      cwd,
      env,
      detached: true,
      stdio: [interactive ? "inherit" : "ignore", "inherit", "inherit"],
    });
    children.add(child);
    child.once("error", (error) => {
      process.stderr.write(`${error.message}\n`);
      children.delete(child);
      stop("SIGTERM", 1);
    });
    child.once("exit", (code) => {
      children.delete(child);
      stop("SIGTERM", code ?? 1);
    });
  };
  process.once("SIGINT", () => stop("SIGINT", 130));
  process.once("SIGTERM", () => stop("SIGTERM", 143));
  start(
    [
      "--filter",
      "@face2face/api",
      "exec",
      "wrangler",
      "dev",
      "--ip",
      urls.address,
      "--var",
      `BETTER_AUTH_URL:${urls.api}`,
      "--var",
      `DEV_WEB_ORIGIN:${urls.web}`,
    ],
    false,
  );
  start(
    [
      "--filter",
      "@face2face/mobile",
      "exec",
      "expo",
      "start",
      "--go",
      "--clear",
    ],
    true,
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(
      `${error instanceof Error ? error.message : "Failed to start Tailscale development."}\n`,
    );
    process.exitCode = 1;
  });
}
