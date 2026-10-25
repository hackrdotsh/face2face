import { Hono } from "hono";
import type { AppEnv } from "../app-env";
import { createDatabase } from "../db/client";
import { mediaSecret } from "../media/signed-path";
import { imageBodyLimit, readImageUpload } from "../middleware/image-upload";
import { requireSession } from "../middleware/session";
import { type Avatar, viewAvatar } from "../profiles/person";
import { savePhotoId } from "../profiles/photo-store";
import {
  deleteProfilePhoto,
  storeProfilePhoto,
} from "../profiles/profile-photos";

/** Saves the new photo, or none, and deletes the files of the old one. */
async function replacePhoto(
  env: Env,
  userId: string,
  photoId: string | null,
): Promise<Avatar> {
  const now = new Date();
  const previous = await savePhotoId(createDatabase(env), userId, photoId, now);
  if (previous) await deleteProfilePhoto(env, previous);
  return viewAvatar(mediaSecret(env), userId, photoId, now);
}

/** Open during onboarding, so the photo can be one of its steps. */
export const profileRoutes = new Hono<AppEnv>()
  .put("/photo", imageBodyLimit, requireSession, async (context) => {
    const upload = await readImageUpload(context.req);
    if (!upload) return context.json({ error: "invalid_request" }, 400);
    const photoId = crypto.randomUUID();
    const isStored = await storeProfilePhoto(
      context.env,
      photoId,
      await upload.arrayBuffer(),
    );
    if (!isStored) return context.json({ error: "unsupported_image" }, 415);
    return context.json({
      avatar: await replacePhoto(context.env, context.var.user.id, photoId),
    });
  })
  .delete("/photo", requireSession, async (context) =>
    context.json({
      avatar: await replacePhoto(context.env, context.var.user.id, null),
    }),
  );
