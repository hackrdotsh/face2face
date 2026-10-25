import type { TokenStore } from "@/api/client";
import { readStored, writeStored } from "@/lib/storage";

/** Keeps one bearer token per API server, so switching servers never sends a token to the wrong one. */
export function browserTokenStore(serverURL: () => string): TokenStore {
  const key = () => `face2face.token:${serverURL()}`;
  return {
    get: () => readStored(key()),
    set: (token) => writeStored(key(), token),
  };
}
