import {
  type ImageVariantName,
  imageVariantNames,
  type StoredImageVariants,
  type VariantSize,
} from "./chat-types";
import { chatImageKey } from "./media-path";

export const maxImageUploadBytes = 15 * 1024 * 1024;
const outputFormat = "image/webp";

/** Every variant is re-encoded, which drops EXIF, GPS, and other metadata. */
const variantSettings: Record<
  ImageVariantName,
  { maxEdge: number; quality: number }
> = {
  original: { maxEdge: 2048, quality: 85 },
  preview: { maxEdge: 1024, quality: 80 },
  thumb: { maxEdge: 256, quality: 75 },
};

const acceptedInputFormats = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/avif",
  "image/heic",
  "image/heif",
]);

interface EncodedVariant extends VariantSize {
  name: ImageVariantName;
  bytes: ArrayBuffer;
}

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
    imageVariantNames.map((name) => encodeVariant(env.IMAGES, upload, name)),
  );
  await Promise.all(
    encoded.map((variant) =>
      env.MEDIA.put(
        chatImageKey(connectionId, imageId, variant.name),
        variant.bytes,
        { httpMetadata: { contentType: outputFormat } },
      ),
    ),
  );
  return { ok: true, variants: sizesOf(encoded) };
}

async function isAcceptedImage(
  images: ImagesBinding,
  upload: ArrayBuffer,
): Promise<boolean> {
  try {
    const info = await images.info(streamOf(upload));
    return acceptedInputFormats.has(info.format);
  } catch {
    return false;
  }
}

/** Fits the image inside a square of the variant's edge, never enlarging it. */
async function encodeVariant(
  images: ImagesBinding,
  upload: ArrayBuffer,
  name: ImageVariantName,
): Promise<EncodedVariant> {
  const { maxEdge, quality } = variantSettings[name];
  const result = await images
    .input(streamOf(upload))
    .transform({ width: maxEdge, height: maxEdge, fit: "scale-down" })
    .output({ format: outputFormat, quality });
  const bytes = await new Response(result.image()).arrayBuffer();
  const info = await images.info(streamOf(bytes));
  if (!("width" in info)) throw new Error("Encoded variant has no size");
  return { name, bytes, width: info.width, height: info.height };
}

function sizesOf(encoded: EncodedVariant[]): StoredImageVariants {
  const sizes = new Map(
    encoded.map(({ name, width, height }) => [name, { width, height }]),
  );
  const [original, preview, thumb] = imageVariantNames.map((name) =>
    sizes.get(name),
  );
  if (!original || !preview || !thumb) throw new Error("Missing variant");
  return { original, preview, thumb };
}

function streamOf(bytes: ArrayBuffer): ReadableStream<Uint8Array> {
  return new Blob([bytes]).stream();
}
