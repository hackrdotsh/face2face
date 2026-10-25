import type { APIClient } from "./client";
import type {
  ChatImage,
  ChatSummary,
  MessagePage,
  SocketTicket,
} from "./types";

export async function listChats(client: APIClient) {
  const { chats } = await client.send<{ chats: ChatSummary[] }>({
    path: "api/chats",
    authenticated: true,
  });
  return chats;
}

export function listMessages(
  client: APIClient,
  chatId: string,
  before?: string,
) {
  return client.send<MessagePage>({
    path: `${chatPath(chatId)}/messages`,
    query: before ? { before } : undefined,
    authenticated: true,
  });
}

export function createChatTicket(client: APIClient, chatId: string) {
  return client.send<SocketTicket>({
    path: `${chatPath(chatId)}/ticket`,
    body: {},
    authenticated: true,
  });
}

/** Uploads an image for a later `send`. The server strips metadata and resizes it. */
export async function uploadChatImage(
  client: APIClient,
  chatId: string,
  file: File,
) {
  const form = new FormData();
  form.append("image", file);
  const { image } = await client.send<{ image: ChatImage }>({
    path: `${chatPath(chatId)}/images`,
    body: form,
    authenticated: true,
  });
  return image;
}

export function chatSocketURL(
  serverURL: string,
  chatId: string,
  ticket: string,
) {
  const url = new URL(`${chatPath(chatId)}/socket`, `${serverURL}/`);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.searchParams.set("ticket", ticket);
  return url.toString();
}

/** Turns a signed media path into a URL on the API server. */
export function mediaURL(serverURL: string, path: string) {
  return new URL(path, `${serverURL}/`).toString();
}

function chatPath(chatId: string) {
  return `api/chats/${encodeURIComponent(chatId)}`;
}
