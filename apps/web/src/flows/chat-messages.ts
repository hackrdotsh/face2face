import type { ChatMessage } from "@/api/types";

/** A message this person sent that the server has not acknowledged yet. */
export interface PendingMessage {
  clientId: string;
  text: string | null;
  imageId: string | null;
  /** A local object URL shown while the image uploads. */
  localImageURL: string | null;
  status: "uploading" | "sending" | "failed";
}

/** Adds messages by ID, keeping the list oldest first with no duplicates. */
export function mergeMessages(
  current: ChatMessage[],
  incoming: ChatMessage[],
): ChatMessage[] {
  const byId = new Map(current.map((message) => [message.id, message]));
  for (const message of incoming) byId.set(message.id, message);
  return [...byId.values()].sort(
    (first, second) =>
      Date.parse(first.createdAt) - Date.parse(second.createdAt),
  );
}

export function latestFromThem(messages: ChatMessage[]): ChatMessage | null {
  return messages.findLast((message) => message.from === "them") ?? null;
}
