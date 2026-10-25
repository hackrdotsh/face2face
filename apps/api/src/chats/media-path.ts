import { isSignatureValid, signPayload } from "../crypto/signing";
import { type ImageVariantName, imageVariantNames } from "./chat-types";

const mediaPurpose = "chat-media";
const signingWindowMs = 60 * 60 * 1000;

export function mediaSecret(env: Env): string {
  if (!env.BETTER_AUTH_SECRET) throw new Error("BETTER_AUTH_SECRET is not set");
  return env.BETTER_AUTH_SECRET;
}

export function chatImageKey(
  connectionId: string,
  imageId: string,
  variant: ImageVariantName,
): string {
  return `chats/${connectionId}/${imageId}/${variant}`;
}

/**
 * Signs a path to one image variant. The expiry is rounded to the end of the
 * next signing window, so repeat loads within a window get the same path and
 * hit the client's cache. A path stays valid for one to two windows.
 */
export async function signMediaPath(
  secret: string,
  key: string,
  now: Date,
): Promise<string> {
  const expires =
    Math.ceil(now.getTime() / signingWindowMs) * signingWindowMs +
    signingWindowMs;
  const signature = await signPayload(
    secret,
    mediaPurpose,
    `${key}.${expires}`,
  );
  return `/media/${key}?expires=${expires}&signature=${signature}`;
}

export interface MediaRequest {
  key: string;
  expires: number;
  signature: string;
}

/** Returns the R2 key when the signature matches and has not expired. */
export async function readMediaRequest(
  secret: string,
  request: MediaRequest,
  now: Date,
): Promise<string | null> {
  if (!Number.isSafeInteger(request.expires)) return null;
  if (request.expires <= now.getTime()) return null;
  const isValid = await isSignatureValid(
    secret,
    mediaPurpose,
    `${request.key}.${request.expires}`,
    request.signature,
  );
  return isValid ? request.key : null;
}

export function isImageVariantName(value: string): value is ImageVariantName {
  return (imageVariantNames as readonly string[]).includes(value);
}
