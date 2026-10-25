const encoder = new TextEncoder();

/**
 * HMAC-SHA256 of the payload, base64url encoded. The purpose is mixed into
 * the key, so a signature made for one purpose never verifies for another.
 */
export async function signPayload(
  secret: string,
  purpose: string,
  payload: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(`${purpose}:${secret}`),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(payload),
  );
  return base64url(new Uint8Array(signature));
}

export async function isSignatureValid(
  secret: string,
  purpose: string,
  payload: string,
  signature: string,
): Promise<boolean> {
  const expected = await signPayload(secret, purpose, payload);
  return constantTimeEqual(signature, expected);
}

export function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

export function fromBase64url(text: string): Uint8Array {
  const binary = atob(text.replaceAll("-", "+").replaceAll("_", "/"));
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function constantTimeEqual(first: string, second: string): boolean {
  if (first.length !== second.length) return false;
  let difference = 0;
  for (let index = 0; index < first.length; index++) {
    difference |= first.charCodeAt(index) ^ second.charCodeAt(index);
  }
  return difference === 0;
}
