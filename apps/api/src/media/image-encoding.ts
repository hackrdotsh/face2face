export const maxImageUploadBytes = 15 * 1024 * 1024;
export const encodedImageFormat = "image/webp";

const acceptedInputFormats = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/avif",
  "image/heic",
  "image/heif",
]);

export interface VariantSettings {
  maxEdge: number;
  quality: number;
  /** `scale-down` keeps the shape. `cover` crops the center to a square. */
  fit: "scale-down" | "cover";
}

export interface EncodedImage {
  bytes: ArrayBuffer;
  width: number;
  height: number;
}

export async function isAcceptedImage(
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

/** Re-encodes into a square of the variant's edge, which drops EXIF, GPS, and other metadata. */
export async function encodeImage(
  images: ImagesBinding,
  upload: ArrayBuffer,
  { maxEdge, quality, fit }: VariantSettings,
): Promise<EncodedImage> {
  const result = await images
    .input(streamOf(upload))
    .transform({ width: maxEdge, height: maxEdge, fit })
    .output({ format: encodedImageFormat, quality });
  const bytes = await new Response(result.image()).arrayBuffer();
  const info = await images.info(streamOf(bytes));
  if (!("width" in info)) throw new Error("Encoded image has no size");
  return { bytes, width: info.width, height: info.height };
}

function streamOf(bytes: ArrayBuffer): ReadableStream<Uint8Array> {
  return new Blob([bytes]).stream();
}
