import type { APIClient } from "./client";
import type { AppNotification, SocketTicket } from "./types";

export async function listNotifications(client: APIClient) {
  const { notifications } = await client.send<{
    notifications: AppNotification[];
  }>({ path: "api/notifications", authenticated: true });
  return notifications;
}

export function createSocketTicket(client: APIClient) {
  return client.send<SocketTicket>({
    path: "api/notifications/ticket",
    body: {},
    authenticated: true,
  });
}

/** The WebSocket URL for a ticket, on the same host as the API. */
export function notificationSocketURL(serverURL: string, ticket: string) {
  const url = new URL("api/notifications/socket", `${serverURL}/`);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.searchParams.set("ticket", ticket);
  return url.toString();
}
