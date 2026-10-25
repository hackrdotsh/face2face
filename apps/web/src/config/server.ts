import { readStored, writeStored } from "@/lib/storage";

const storageKey = "face2face.serverURL";

export const defaultServerURL: string =
  import.meta.env.VITE_API_URL ?? "http://localhost:8080";

export function loadServerURL(): string {
  return readStored(storageKey) ?? defaultServerURL;
}

export function saveServerURL(url: string): void {
  writeStored(storageKey, url === defaultServerURL ? null : url);
}

/** Returns the URL's origin, or null when it is not an http(s) URL without a path. */
export function normalizeServerURL(input: string): string | null {
  try {
    const url = new URL(input.trim());
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    if (url.username || url.password || url.search || url.hash) return null;
    if (url.pathname !== "/") return null;
    return url.origin;
  } catch {
    return null;
  }
}
