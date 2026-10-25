import { type Context, Hono } from "hono";
import type { AppEnv } from "../app-env";
import { chatImageKey, isImageVariantName } from "../chats/media-path";
import { mediaSecret, readMediaRequest } from "../media/signed-path";
import {
  isProfilePhotoVariantName,
  profilePhotoKey,
} from "../profiles/profile-photos";

/** Answers with the R2 object when the request's signature covers its key. */
async function serveSignedMedia(context: Context<AppEnv>, key: string) {
  const now = new Date();
  const expires = Number(context.req.query("expires"));
  const signedKey = await readMediaRequest(
    mediaSecret(context.env),
    { key, expires, signature: context.req.query("signature") ?? "" },
    now,
  );
  if (!signedKey) return context.json({ error: "forbidden" }, 403);
  const object = await context.env.MEDIA.get(signedKey);
  if (!object) return context.json({ error: "not_found" }, 404);
  const secondsLeft = Math.floor((expires - now.getTime()) / 1000);
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("ETag", object.httpEtag);
  headers.set("Cache-Control", `private, max-age=${secondsLeft}, immutable`);
  return new Response(object.body, { headers });
}

/** Serves chat images and profile photos to anyone holding an unexpired signed path. */
export const mediaRoutes = new Hono<AppEnv>()
  .get("/chats/:connectionId/:imageId/:variant", (context) => {
    const { connectionId, imageId, variant } = context.req.param();
    if (!isImageVariantName(variant)) {
      return context.json({ error: "not_found" }, 404);
    }
    return serveSignedMedia(
      context,
      chatImageKey(connectionId, imageId, variant),
    );
  })
  .get("/profiles/:photoId/:variant", (context) => {
    const { photoId, variant } = context.req.param();
    if (!isProfilePhotoVariantName(variant)) {
      return context.json({ error: "not_found" }, 404);
    }
    return serveSignedMedia(context, profilePhotoKey(photoId, variant));
  });
