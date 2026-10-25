import { useCallback, useEffect, useState } from "react";
import {
  createSocketTicket,
  listNotifications,
  notificationSocketURL,
} from "@/api/notifications";
import type { AppNotification, ChatActivity } from "@/api/types";
import { useSession } from "@/session/session";
import { useActivity } from "./use-activity";
import { type SocketState, useReconnectingSocket } from "./use-socket";

type NotificationFrame =
  | { type: "ready" }
  | { type: "pong" }
  | { type: "notification"; notification: AppNotification }
  | { type: "chat_activity"; activity: ChatActivity };

/**
 * The person's notifications. Loads the inbox first, then listens on a socket
 * for new ones and reconnects when it drops. The iPhone app follows the same
 * order when it comes to the foreground. Chat activity arrives on the same
 * socket but is never kept in the inbox.
 */
export function useNotifications() {
  const { client, serverURL } = useSession();
  const activity = useActivity();
  const [notifications, setNotifications] = useState<AppNotification[]>([]);
  const [latestChatActivity, setLatestChatActivity] =
    useState<ChatActivity | null>(null);
  const [socketState, setSocketState] = useState<SocketState>("connecting");

  const reload = useCallback(
    () =>
      activity.run(async () => {
        setNotifications(await listNotifications(client));
      }),
    [activity.run, client],
  );

  const addNotification = useCallback((notification: AppNotification) => {
    setNotifications((current) =>
      current.some((existing) => existing.id === notification.id)
        ? current
        : [notification, ...current],
    );
  }, []);

  useEffect(() => {
    void reload();
  }, [reload]);

  useReconnectingSocket(
    useCallback(async () => {
      const { ticket } = await createSocketTicket(client);
      return notificationSocketURL(serverURL, ticket);
    }, [client, serverURL]),
    {
      onFrame: (frame) => {
        const message = frame as NotificationFrame;
        if (message.type === "notification") {
          addNotification(message.notification);
        }
        if (message.type === "chat_activity") {
          setLatestChatActivity(message.activity);
        }
      },
      onStateChange: setSocketState,
      onReconnect: reload,
    },
  );

  return { notifications, latestChatActivity, socketState, activity, reload };
}

export type NotificationFeed = ReturnType<typeof useNotifications>;
