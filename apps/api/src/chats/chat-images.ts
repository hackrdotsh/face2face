import {
  encodedImageFormat,
  encodeImage,
  isAcceptedImage,
  type VariantSettings,
} from "../media/image-encoding";
import {
  type ImageVariantName,
  imageVariantNames,
  type StoredImageVariants,
} from "./chat-types";
import { chatImageKey } from "./media-path";

/** Each variant fits inside a square of its edge and is never enlarged. */
const variantSettings: Record<ImageVariantName, VariantSettings> = {
  original: { maxEdge: 2048, quality: 85, fit: "scale-down" },
  preview: { maxEdge: 1024, quality: 80, fit: "scale-down" },
  thumb: { maxEdge: 256, quality: 75, fit: "scale-down" },
};

export type StoreImageResult =
  | { ok: true; variants: StoredImageVariants }
  | { ok: false; error: "unsupported_image" };

/** Re-encodes the upload into every variant and writes them to R2. */
export async function storeChatImage(
  env: Env,
  connectionId: string,
  imageId: string,
  upload: ArrayBuffer,
): Promise<StoreImageResult> {
  if (!(await isAcceptedImage(env.IMAGES, upload))) {
    return { ok: false, error: "unsupported_image" };
  }
  const encoded = await Promise.all(
    imageVariantNames.map(async (name) => ({
      name,
      ...(await encodeImage(env.IMAGES, upload, variantSettings[name])),
    })),
  );
  await Promise.all(
    encoded.map((variant) =>
      env.MEDIA.put(
        chatImageKey(connectionId, imageId, variant.name),
        variant.bytes,
        { httpMetadata: { contentType: encodedImageFormat } },
      ),
    ),
  );
  const [original, preview, thumb] = encoded.map(({ width, height }) => ({
    width,
    height,
  }));
  if (!original || !preview || !thumb) throw new Error("Missing variant");
  return { ok: true, variants: { original, preview, thumb } };
}
