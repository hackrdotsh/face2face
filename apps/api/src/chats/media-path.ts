import { type ImageVariantName, imageVariantNames } from "./chat-types";

export function chatImageKey(
  connectionId: string,
  imageId: string,
  variant: ImageVariantName,
): string {
  return `chats/${connectionId}/${imageId}/${variant}`;
}

export function isImageVariantName(value: string): value is ImageVariantName {
  return (imageVariantNames as readonly string[]).includes(value);
}
