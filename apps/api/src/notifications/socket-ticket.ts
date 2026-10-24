const ticketLifetimeMs = 60 * 1000;
const encoder = new TextEncoder();

export function socketTicketSecret(env: Env): string {
  if (!env.BETTER_AUTH_SECRET) throw new Error("BETTER_AUTH_SECRET is not set");
  return env.BETTER_AUTH_SECRET;
}

interface TicketClaims {
  userId: string;
  expiresAt: number;
}

/**
 * A short-lived signed credential for opening the notification socket.
 * Browsers cannot send an Authorization header on a WebSocket, and a bearer
 * token in a URL would end up in logs.
 */
export async function createSocketTicket(
  secret: string,
  userId: string,
  now: Date,
): Promise<{ ticket: string; expiresAt: string }> {
  const claims: TicketClaims = {
    userId,
    expiresAt: now.getTime() + ticketLifetimeMs,
  };
  const payload = base64url(encoder.encode(JSON.stringify(claims)));
  const signature = await sign(secret, payload);
  return {
    ticket: `${payload}.${signature}`,
    expiresAt: new Date(claims.expiresAt).toISOString(),
  };
}

/** Returns the user ID the ticket was issued to, or null if it is forged or expired. */
export async function readSocketTicket(
  secret: string,
  ticket: string,
  now: Date,
): Promise<string | null> {
  const [payload, signature] = ticket.split(".");
  if (!payload || !signature) return null;
  const expected = await sign(secret, payload);
  if (!constantTimeEqual(signature, expected)) return null;
  const claims = parseClaims(payload);
  if (!claims || claims.expiresAt <= now.getTime()) return null;
  return claims.userId;
}

async function sign(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(`socket-ticket:${secret}`),
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

function parseClaims(payload: string): TicketClaims | null {
  try {
    const claims: unknown = JSON.parse(
      new TextDecoder().decode(fromBase64url(payload)),
    );
    if (
      typeof claims === "object" &&
      claims !== null &&
      "userId" in claims &&
      "expiresAt" in claims &&
      typeof claims.userId === "string" &&
      typeof claims.expiresAt === "number"
    ) {
      return { userId: claims.userId, expiresAt: claims.expiresAt };
    }
    return null;
  } catch {
    return null;
  }
}

function constantTimeEqual(first: string, second: string): boolean {
  if (first.length !== second.length) return false;
  let difference = 0;
  for (let index = 0; index < first.length; index++) {
    difference |= first.charCodeAt(index) ^ second.charCodeAt(index);
  }
  return difference === 0;
}

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

function fromBase64url(text: string): Uint8Array {
  const binary = atob(text.replaceAll("-", "+").replaceAll("_", "/"));
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}
