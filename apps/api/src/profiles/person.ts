import { base64url } from "../crypto/signing";
import { mediaSecret, signMediaPath } from "../media/signed-path";
import {
  type ProfilePhotoVariantName,
  profilePhotoKey,
  profilePhotoVariantNames,
} from "./profile-photos";

const avatarSeedBytes = 16;
const avatarSeedPrefix = "face2face-avatar:";

/** Signed paths to each square variant. Clients show them as circles. */
export type ProfilePhoto = Record<ProfilePhotoVariantName, string>;

export interface Avatar {
  /** Base64url bytes that clients turn into a blob avatar when there is no photo. */
  seed: string;
  photo: ProfilePhoto | null;
}

export interface PersonRow {
  userId: string;
  name: string;
  photoId: string | null;
}

export interface Person {
  userId: string;
  name: string;
  avatar: Avatar;
}

export type PersonViewer = (person: PersonRow) => Promise<Person>;
export type PhotoViewer = (photoId: string) => Promise<ProfilePhoto>;

/** Signs photo paths with the media secret, valid from `now`. */
export function personViewer(env: Env, now: Date): PersonViewer {
  const secret = mediaSecret(env);
  return async ({ userId, name, photoId }) => ({
    userId,
    name,
    avatar: await viewAvatar(secret, userId, photoId, now),
  });
}

/** Signs photo paths with the media secret, valid from `now`. */
export function photoViewer(env: Env, now: Date): PhotoViewer {
  const secret = mediaSecret(env);
  return (photoId) => viewProfilePhoto(secret, photoId, now);
}

export async function viewAvatar(
  secret: string,
  userId: string,
  photoId: string | null,
  now: Date,
): Promise<Avatar> {
  const [seed, photo] = await Promise.all([
    avatarSeed(userId),
    photoId ? viewProfilePhoto(secret, photoId, now) : null,
  ]);
  return { seed, photo };
}

/** The same user always gets the same seed. */
export async function avatarSeed(userId: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`${avatarSeedPrefix}${userId}`),
  );
  return base64url(new Uint8Array(digest).slice(0, avatarSeedBytes));
}

async function viewProfilePhoto(
  secret: string,
  photoId: string,
  now: Date,
): Promise<ProfilePhoto> {
  const [large, thumb] = await Promise.all(
    profilePhotoVariantNames.map((name) =>
      signMediaPath(secret, profilePhotoKey(photoId, name), now),
    ),
  );
  if (!large || !thumb) throw new Error("Missing variant");
  return { large, thumb };
}
