import {
  base64url,
  fromBase64url,
  isSignatureValid,
  signPayload,
} from "../crypto/signing";

const ticketLifetimeMs = 60 * 1000;
const ticketPurpose = "socket-ticket";
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
 * A short-lived signed credential for opening a socket. Browsers cannot send
 * an Authorization header on a WebSocket, and a bearer token in a URL would
 * end up in logs. A ticket proves who the person is, so each socket route
 * still checks what they may open.
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
  const signature = await signPayload(secret, ticketPurpose, payload);
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
  if (!(await isSignatureValid(secret, ticketPurpose, payload, signature))) {
    return null;
  }
  const claims = parseClaims(payload);
  if (!claims || claims.expiresAt <= now.getTime()) return null;
  return claims.userId;
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
