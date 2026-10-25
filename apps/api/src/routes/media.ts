import { Hono } from "hono";
import type { AppEnv } from "../app-env";
import {
  chatImageKey,
  isImageVariantName,
  mediaSecret,
  readMediaRequest,
} from "../chats/media-path";

/** Serves chat images to anyone holding an unexpired signed path. */
export const mediaRoutes = new Hono<AppEnv>().get(
  "/chats/:connectionId/:imageId/:variant",
  async (context) => {
    const { connectionId, imageId, variant } = context.req.param();
    if (!isImageVariantName(variant)) {
      return context.json({ error: "not_found" }, 404);
    }
    const now = new Date();
    const expires = Number(context.req.query("expires"));
    const key = await readMediaRequest(
      mediaSecret(context.env),
      {
        key: chatImageKey(connectionId, imageId, variant),
        expires,
        signature: context.req.query("signature") ?? "",
      },
      now,
    );
    if (!key) return context.json({ error: "forbidden" }, 403);
    const object = await context.env.MEDIA.get(key);
    if (!object) return context.json({ error: "not_found" }, 404);
    const secondsLeft = Math.floor((expires - now.getTime()) / 1000);
    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set("ETag", object.httpEtag);
    headers.set("Cache-Control", `private, max-age=${secondsLeft}, immutable`);
    return new Response(object.body, { headers });
  },
);
