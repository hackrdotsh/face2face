import { z } from "zod";
import type { ConnectionView } from "../connections/view";
import type { ConnectionSide } from "../db/schema";

export const imageVariantNames = ["original", "preview", "thumb"] as const;
export type ImageVariantName = (typeof imageVariantNames)[number];

export const maxMessageLength = 4000;
const maxClientIdLength = 64;

/** What the Worker has checked before it lets someone into a chat. */
export interface ChatAccess {
  connectionId: string;
  side: ConnectionSide;
  lowUserId: string;
  highUserId: string;
}

export interface VariantSize {
  width: number;
  height: number;
}

export type StoredImageVariants = Record<ImageVariantName, VariantSize>;

export interface ImageVariantView extends VariantSize {
  /** A signed path relative to the API base URL. It expires; reload the message for a fresh one. */
  path: string;
}

export interface ChatImage {
  id: string;
  variants: Record<ImageVariantName, ImageVariantView>;
}

/** One message as a participant sees it. Never names either person. */
export interface ChatMessage {
  id: string;
  /** Set only on the viewer's own messages, so a client can match its pending sends. */
  clientId: string | null;
  from: "you" | "them";
  text: string | null;
  image: ChatImage | null;
  createdAt: string;
}

export interface ChatSummary {
  id: string;
  connection: ConnectionView;
  lastMessage: ChatMessage | null;
  unreadCount: number;
}

export interface MessagePage {
  messages: ChatMessage[];
  hasMore: boolean;
}

/** Sent live to the other person's notification sockets. Not stored. */
export interface ChatActivity {
  chatId: string;
  messageId: string;
  createdAt: string;
}

export const typingStates = ["started", "stopped"] as const;
export type TypingState = (typeof typingStates)[number];

const sendFrame = z
  .object({
    type: z.literal("send"),
    clientId: z.string().min(1).max(maxClientIdLength),
    text: z.string().max(maxMessageLength).optional(),
    imageId: z.string().min(1).optional(),
  })
  .refine((frame) => Boolean(frame.text?.trim()) || Boolean(frame.imageId));

export const clientFrame = z.discriminatedUnion("type", [
  sendFrame,
  z.object({ type: z.literal("typing"), state: z.enum(typingStates) }),
  z.object({ type: z.literal("read"), messageId: z.string().min(1) }),
]);

export type ClientFrame = z.infer<typeof clientFrame>;
export type SendFrame = z.infer<typeof sendFrame>;

export type ChatError =
  | "invalid_frame"
  | "chat_closed"
  | "image_not_found"
  | "message_not_found";

export type ServerFrame =
  | { type: "ready" }
  | { type: "pong" }
  | { type: "ack"; clientId: string; message: ChatMessage }
  | { type: "message"; message: ChatMessage }
  | { type: "typing"; state: TypingState }
  | { type: "error"; error: ChatError; clientId?: string }
  | { type: "closed" };
