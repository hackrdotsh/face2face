import { bodyLimit } from "hono/body-limit";
import { maxImageUploadBytes } from "../media/image-encoding";

export const imageBodyLimit = bodyLimit({
  maxSize: maxImageUploadBytes,
  onError: (context) => context.json({ error: "image_too_large" }, 413),
});

/** The `image` field of a multipart body, or null when it is missing. */
export async function readImageUpload(request: {
  formData(): Promise<FormData>;
}): Promise<File | null> {
  const form = await request.formData().catch(() => null);
  const upload = form?.get("image");
  return upload instanceof File ? upload : null;
}
