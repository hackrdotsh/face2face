import { base64url } from "../crypto/signing";

export type PushEnvironment = "sandbox" | "production";

export interface PushAlert {
  title: string;
  body: string;
  badge: number;
  /** Alerts with the same key replace each other on the phone. */
  group?: string;
  /** Extra keys next to `aps`. They must hold no identity of another person. */
  data: Record<string, string>;
}

export type PushResult = "sent" | "unregistered" | "failed";

export interface PushSender {
  send(
    token: string,
    environment: PushEnvironment,
    alert: PushAlert,
  ): Promise<PushResult>;
}

interface ApnsConfig {
  teamId: string;
  topic: string;
  keyId: string;
  privateKey: string;
}

/** Optional secrets. Push stays off until both are set. */
interface PushSecrets {
  APNS_KEY_ID?: string;
  APNS_PRIVATE_KEY?: string;
}

const hosts: Record<PushEnvironment, string> = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
};

/** APNs rejects a provider token older than an hour and refreshes faster than every 20 minutes. */
const providerTokenLifetimeMs = 45 * 60 * 1000;
const unregisteredReasons = new Set([
  "BadDeviceToken",
  "DeviceTokenNotForTopic",
  "Unregistered",
]);

export function apnsSender(env: Env): PushSender | null {
  const config = apnsConfig(env);
  return config ? new ApnsSender(config) : null;
}

function apnsConfig(env: Env): ApnsConfig | null {
  const { APNS_KEY_ID: keyId, APNS_PRIVATE_KEY: privateKey } = env as Env &
    PushSecrets;
  const [teamId, ...bundle] = env.APPLE_APP_ID.split(".");
  if (!keyId || !privateKey || !teamId || bundle.length === 0) return null;
  return { teamId, topic: bundle.join("."), keyId, privateKey };
}

class ApnsSender implements PushSender {
  private providerToken: { value: string; issuedAt: number } | null = null;

  constructor(private readonly config: ApnsConfig) {}

  async send(
    token: string,
    environment: PushEnvironment,
    alert: PushAlert,
  ): Promise<PushResult> {
    const response = await fetch(`${hosts[environment]}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${await this.currentProviderToken()}`,
        "apns-topic": this.config.topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
        ...(alert.group ? { "apns-collapse-id": alert.group } : {}),
        "content-type": "application/json",
      },
      body: JSON.stringify({
        aps: {
          alert: { title: alert.title, body: alert.body },
          badge: alert.badge,
          sound: "default",
          ...(alert.group ? { "thread-id": alert.group } : {}),
        },
        ...alert.data,
      }),
    });
    if (response.ok) return "sent";
    const reason = await readReason(response);
    if (response.status === 410 || unregisteredReasons.has(reason)) {
      return "unregistered";
    }
    if (reason === "ExpiredProviderToken") this.providerToken = null;
    console.warn(
      JSON.stringify({ event: "apns_failed", status: response.status, reason }),
    );
    return "failed";
  }

  private async currentProviderToken(): Promise<string> {
    const now = Date.now();
    if (
      this.providerToken &&
      now - this.providerToken.issuedAt < providerTokenLifetimeMs
    ) {
      return this.providerToken.value;
    }
    const value = await signProviderToken(this.config, now);
    this.providerToken = { value, issuedAt: now };
    return value;
  }
}

async function readReason(response: Response): Promise<string> {
  try {
    const body: unknown = await response.json();
    if (typeof body === "object" && body !== null && "reason" in body) {
      return String(body.reason);
    }
  } catch {}
  return "";
}

const encoder = new TextEncoder();

/** An ES256 JWT for token-based APNs authentication. */
export async function signProviderToken(
  config: Pick<ApnsConfig, "teamId" | "keyId" | "privateKey">,
  now: number,
): Promise<string> {
  const header = encodeSegment({ alg: "ES256", kid: config.keyId });
  const claims = encodeSegment({
    iss: config.teamId,
    iat: Math.floor(now / 1000),
  });
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemBody(config.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(`${header}.${claims}`),
  );
  return `${header}.${claims}.${base64url(new Uint8Array(signature))}`;
}

function encodeSegment(value: object): string {
  return base64url(encoder.encode(JSON.stringify(value)));
}

/** Accepts the .p8 file contents, with or without PEM armor and line breaks. */
function pemBody(pem: string): Uint8Array<ArrayBuffer> {
  const base64 = pem
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    .replace(/\\n|\s/g, "");
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
}
