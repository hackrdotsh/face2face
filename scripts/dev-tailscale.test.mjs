import assert from "node:assert/strict";
import { test } from "node:test";
import { tailscaleURLs } from "./dev-tailscale.mjs";

test("uses the Tailscale address for the iPhone API", () => {
  assert.deepEqual(tailscaleURLs("100.100.20.30\n"), {
    address: "100.100.20.30",
    api: "http://100.100.20.30:8080",
  });
});

test("rejects loopback, LAN, IPv6, malformed and multiple addresses", () => {
  for (const value of [
    "",
    "127.0.0.1",
    "192.168.1.10",
    "100.63.1.1",
    "100.128.1.1",
    "100.999.1.1",
    "::1",
    "100.100.1.1\n100.100.1.2",
  ]) {
    assert.throws(() => tailscaleURLs(value));
  }
});
