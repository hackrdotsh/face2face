import {
  encodedImageFormat,
  encodeImage,
  isAcceptedImage,
  type VariantSettings,
} from "../media/image-encoding";

export const profilePhotoVariantNames = ["large", "thumb"] as const;
export type ProfilePhotoVariantName = (typeof profilePhotoVariantNames)[number];

/** Each variant is a center-cropped square. Clients mask it to a circle. */
const variantSettings: Record<ProfilePhotoVariantName, VariantSettings> = {
  large: { maxEdge: 1024, quality: 85, fit: "cover" },
  thumb: { maxEdge: 256, quality: 80, fit: "cover" },
};

export function profilePhotoKey(
  photoId: string,
  variant: ProfilePhotoVariantName,
): string {
  return `profiles/${photoId}/${variant}`;
}

export function isProfilePhotoVariantName(
  value: string,
): value is ProfilePhotoVariantName {
  return (profilePhotoVariantNames as readonly string[]).includes(value);
}

/** Re-encodes the upload into every variant and writes them to R2. */
export async function storeProfilePhoto(
  env: Env,
  photoId: string,
  upload: ArrayBuffer,
): Promise<boolean> {
  if (!(await isAcceptedImage(env.IMAGES, upload))) return false;
  await Promise.all(
    profilePhotoVariantNames.map(async (name) => {
      const encoded = await encodeImage(
        env.IMAGES,
        upload,
        variantSettings[name],
      );
      await env.MEDIA.put(profilePhotoKey(photoId, name), encoded.bytes, {
        httpMetadata: { contentType: encodedImageFormat },
      });
    }),
  );
  return true;
}

export async function deleteProfilePhoto(env: Env, photoId: string) {
  await env.MEDIA.delete(
    profilePhotoVariantNames.map((name) => profilePhotoKey(photoId, name)),
  );
}
