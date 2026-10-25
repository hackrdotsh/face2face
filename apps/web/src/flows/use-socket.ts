import { useEffect, useRef } from "react";

/** `closed` means the server ended the socket on purpose and it will not reconnect. */
export type SocketState = "connecting" | "live" | "offline" | "closed";

export interface SocketHandlers {
  /** Called with each parsed JSON frame. */
  onFrame: (frame: unknown) => void;
  onStateChange: (state: SocketState) => void;
  /** Called on `ready` after a drop. Anything sent while down is only on the server. */
  onReconnect?: () => void;
}

export interface SocketSender {
  /** Returns false when the socket is not open. */
  send: (data: string) => boolean;
}

const reconnectDelaysMs = [1000, 2000, 5000, 10000, 30000];
const keepAliveIntervalMs = 30000;
const firstApplicationCloseCode = 4000;

/**
 * Keeps one socket open while mounted, with backoff between reconnects. A new
 * ticket is fetched for every attempt, because each one expires in a minute.
 */
export function useReconnectingSocket(
  createSocketURL: () => Promise<string>,
  handlers: SocketHandlers,
): SocketSender {
  const handlersRef = useRef(handlers);
  handlersRef.current = handlers;
  const socketRef = useRef<WebSocket | null>(null);
  const sender = useRef<SocketSender>({
    send: (data) => {
      const socket = socketRef.current;
      if (socket?.readyState !== WebSocket.OPEN) return false;
      socket.send(data);
      return true;
    },
  });

  useEffect(() => {
    let stopped = false;
    let retryTimer: ReturnType<typeof setTimeout> | undefined;
    let keepAliveTimer: ReturnType<typeof setInterval> | undefined;
    let failures = 0;

    const scheduleReconnect = () => {
      if (stopped) return;
      handlersRef.current.onStateChange("offline");
      const delay =
        reconnectDelaysMs[Math.min(failures, reconnectDelaysMs.length - 1)];
      failures++;
      retryTimer = setTimeout(connect, delay);
    };

    const connect = async () => {
      handlersRef.current.onStateChange("connecting");
      let url: string;
      try {
        url = await createSocketURL();
      } catch {
        scheduleReconnect();
        return;
      }
      if (stopped) return;
      const socket = new WebSocket(url);
      socketRef.current = socket;
      socket.addEventListener("message", (event) => {
        const frame = parseFrame(event.data);
        if (isReadyFrame(frame)) {
          if (failures > 0) handlersRef.current.onReconnect?.();
          failures = 0;
          handlersRef.current.onStateChange("live");
        }
        if (frame !== undefined) handlersRef.current.onFrame(frame);
      });
      socket.addEventListener("close", (event) => {
        clearInterval(keepAliveTimer);
        if (socketRef.current === socket) socketRef.current = null;
        if (event.code >= firstApplicationCloseCode) {
          handlersRef.current.onStateChange("closed");
          return;
        }
        scheduleReconnect();
      });
      keepAliveTimer = setInterval(() => {
        if (socket.readyState === WebSocket.OPEN) socket.send("ping");
      }, keepAliveIntervalMs);
    };

    void connect();
    return () => {
      stopped = true;
      clearTimeout(retryTimer);
      clearInterval(keepAliveTimer);
      socketRef.current?.close(1000);
      socketRef.current = null;
    };
  }, [createSocketURL]);

  return sender.current;
}

function parseFrame(data: unknown): unknown {
  try {
    return JSON.parse(String(data));
  } catch {
    return undefined;
  }
}

function isReadyFrame(frame: unknown): boolean {
  return (
    typeof frame === "object" &&
    frame !== null &&
    "type" in frame &&
    frame.type === "ready"
  );
}
