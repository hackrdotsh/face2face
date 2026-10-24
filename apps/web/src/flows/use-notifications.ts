import { useCallback, useEffect, useRef, useState } from "react";
import {
  createSocketTicket,
  listNotifications,
  notificationSocketURL,
} from "@/api/notifications";
import type { AppNotification } from "@/api/types";
import { useSession } from "@/session/session";
import { useActivity } from "./use-activity";

export type SocketState = "connecting" | "live" | "offline";

const reconnectDelaysMs = [1000, 2000, 5000, 10000, 30000];
const keepAliveIntervalMs = 30000;

interface SocketMessage {
  type: "ready" | "notification" | "pong";
  notification?: AppNotification;
}

/**
 * The person's notifications. Loads the inbox first, then listens on a socket
 * for new ones and reconnects when it drops. The iPhone app follows the same
 * order when it comes to the foreground.
 */
export function useNotifications() {
  const { client, serverURL } = useSession();
  const activity = useActivity();
  const [notifications, setNotifications] = useState<AppNotification[]>([]);
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

  useNotificationSocket(
    useCallback(async () => {
      const { ticket } = await createSocketTicket(client);
      return notificationSocketURL(serverURL, ticket);
    }, [client, serverURL]),
    addNotification,
    setSocketState,
    reload,
  );

  return { notifications, socketState, activity, reload };
}

export type NotificationFeed = ReturnType<typeof useNotifications>;

/** Keeps one socket open while mounted, with backoff between reconnects. */
function useNotificationSocket(
  createSocketURL: () => Promise<string>,
  onNotification: (notification: AppNotification) => void,
  onStateChange: (state: SocketState) => void,
  onReconnect: () => void,
) {
  const handlers = useRef({ onNotification, onStateChange, onReconnect });
  handlers.current = { onNotification, onStateChange, onReconnect };

  useEffect(() => {
    let stopped = false;
    let socket: WebSocket | null = null;
    let retryTimer: ReturnType<typeof setTimeout> | undefined;
    let keepAliveTimer: ReturnType<typeof setInterval> | undefined;
    let failures = 0;

    const scheduleReconnect = () => {
      if (stopped) return;
      handlers.current.onStateChange("offline");
      const delay =
        reconnectDelaysMs[Math.min(failures, reconnectDelaysMs.length - 1)];
      failures++;
      retryTimer = setTimeout(connect, delay);
    };

    const connect = async () => {
      handlers.current.onStateChange("connecting");
      let url: string;
      try {
        url = await createSocketURL();
      } catch {
        scheduleReconnect();
        return;
      }
      if (stopped) return;
      socket = new WebSocket(url);
      socket.addEventListener("message", (event) => {
        const message = JSON.parse(String(event.data)) as SocketMessage;
        if (message.type === "ready") {
          // Anything sent while the socket was down is only in the inbox.
          if (failures > 0) handlers.current.onReconnect();
          failures = 0;
          handlers.current.onStateChange("live");
        }
        if (message.notification) {
          handlers.current.onNotification(message.notification);
        }
      });
      socket.addEventListener("close", () => {
        clearInterval(keepAliveTimer);
        scheduleReconnect();
      });
      keepAliveTimer = setInterval(() => {
        if (socket?.readyState === WebSocket.OPEN) socket.send("ping");
      }, keepAliveIntervalMs);
    };

    void connect();
    return () => {
      stopped = true;
      clearTimeout(retryTimer);
      clearInterval(keepAliveTimer);
      socket?.close(1000);
    };
  }, [createSocketURL]);
}
