import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  chatSocketURL,
  createChatTicket,
  listMessages,
  uploadChatImage,
} from "@/api/chats";
import type {
  ChatClientFrame,
  ChatMessage,
  ChatServerFrame,
} from "@/api/types";
import { useSession } from "@/session/session";
import {
  latestFromThem,
  mergeMessages,
  type PendingMessage,
} from "./chat-messages";
import { TypingSignal, theirTypingTimeoutMs } from "./typing-signal";
import { useActivity } from "./use-activity";
import { type SocketState, useReconnectingSocket } from "./use-socket";

/**
 * One open conversation. Loads the newest page over HTTP, then sends and
 * receives over the chat socket. Sends wait in `pending` until acknowledged
 * and are sent again after a reconnect, which the server deduplicates by
 * client ID.
 */
export function useChat(chatId: string) {
  const { client, serverURL } = useSession();
  const activity = useActivity();
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [pending, setPending] = useState<PendingMessage[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [draft, setDraft] = useState("");
  const [isTheyTyping, setIsTheyTyping] = useState(false);
  const [socketState, setSocketState] = useState<SocketState>("connecting");
  const pendingRef = useRef(pending);
  pendingRef.current = pending;
  const theirTypingTimer = useRef<ReturnType<typeof setTimeout>>(undefined);

  const refreshLatest = useCallback(async () => {
    const page = await listMessages(client, chatId);
    setMessages((current) => mergeMessages(current, page.messages));
    setHasMore((current) => current || page.hasMore);
  }, [client, chatId]);

  const loadLatest = useCallback(
    () => activity.run(refreshLatest),
    [activity.run, refreshLatest],
  );

  const loadOlder = () =>
    activity.run(async () => {
      const page = await listMessages(client, chatId, messages[0]?.id);
      setMessages((current) => mergeMessages(current, page.messages));
      setHasMore(page.hasMore);
    });

  const socket = useReconnectingSocket(
    useCallback(async () => {
      const { ticket } = await createChatTicket(client, chatId);
      return chatSocketURL(serverURL, chatId, ticket);
    }, [client, serverURL, chatId]),
    {
      onFrame: (frame) => handleFrame(frame as ChatServerFrame),
      onStateChange: setSocketState,
    },
  );

  const sendFrame = useCallback(
    (frame: ChatClientFrame) => socket.send(JSON.stringify(frame)),
    [socket],
  );

  const typing = useMemo(
    () => new TypingSignal((state) => sendFrame({ type: "typing", state })),
    [sendFrame],
  );

  useEffect(() => {
    void loadLatest();
    return () => typing.stop();
  }, [loadLatest, typing]);

  useEffect(() => () => clearTimeout(theirTypingTimer.current), []);

  const newestFromThemId = latestFromThem(messages)?.id;
  useEffect(() => {
    if (!newestFromThemId || socketState !== "live") return;
    sendFrame({ type: "read", messageId: newestFromThemId });
  }, [newestFromThemId, socketState, sendFrame]);

  function handleFrame(frame: ChatServerFrame) {
    switch (frame.type) {
      case "ready":
        // Covers anything sent between the history load and this socket opening.
        refreshLatest().catch(() => {});
        resendPending();
        return;
      case "ack":
        settlePending(frame.clientId);
        setMessages((current) => mergeMessages(current, [frame.message]));
        return;
      case "message":
        if (frame.message.from === "them") showTheyStoppedTyping();
        setMessages((current) => mergeMessages(current, [frame.message]));
        return;
      case "typing":
        if (frame.state === "started") showTheyAreTyping();
        else showTheyStoppedTyping();
        return;
      case "error":
        if (frame.clientId) markFailed(frame.clientId);
        return;
    }
  }

  function showTheyAreTyping() {
    setIsTheyTyping(true);
    clearTimeout(theirTypingTimer.current);
    theirTypingTimer.current = setTimeout(
      () => setIsTheyTyping(false),
      theirTypingTimeoutMs,
    );
  }

  function showTheyStoppedTyping() {
    clearTimeout(theirTypingTimer.current);
    setIsTheyTyping(false);
  }

  function updatePending(clientId: string, changes: Partial<PendingMessage>) {
    setPending((current) =>
      current.map((message) =>
        message.clientId === clientId ? { ...message, ...changes } : message,
      ),
    );
  }

  function settlePending(clientId: string) {
    setPending((current) => {
      const settled = current.find((message) => message.clientId === clientId);
      if (settled?.localImageURL) URL.revokeObjectURL(settled.localImageURL);
      return current.filter((message) => message.clientId !== clientId);
    });
  }

  function markFailed(clientId: string) {
    updatePending(clientId, { status: "failed" });
  }

  function sendPending(message: PendingMessage) {
    sendFrame({
      type: "send",
      clientId: message.clientId,
      text: message.text ?? undefined,
      imageId: message.imageId ?? undefined,
    });
  }

  function resendPending() {
    for (const message of pendingRef.current) {
      if (message.status === "sending") sendPending(message);
    }
  }

  const changeDraft = (text: string) => {
    setDraft(text);
    typing.draftChanged(text);
  };

  const sendText = () => {
    const text = draft.trim();
    if (!text) return;
    const message: PendingMessage = {
      clientId: crypto.randomUUID(),
      text,
      imageId: null,
      localImageURL: null,
      status: "sending",
    };
    setPending((current) => [...current, message]);
    setDraft("");
    typing.stop();
    sendPending(message);
  };

  const sendImage = async (file: File) => {
    const message: PendingMessage = {
      clientId: crypto.randomUUID(),
      text: null,
      imageId: null,
      localImageURL: URL.createObjectURL(file),
      status: "uploading",
    };
    setPending((current) => [...current, message]);
    try {
      const image = await uploadChatImage(client, chatId, file);
      const ready = {
        ...message,
        imageId: image.id,
        status: "sending" as const,
      };
      updatePending(message.clientId, ready);
      sendPending(ready);
    } catch {
      markFailed(message.clientId);
    }
  };

  const retry = (message: PendingMessage) => {
    if (!message.imageId && !message.text) return;
    updatePending(message.clientId, { status: "sending" });
    sendPending(message);
  };

  const discard = (message: PendingMessage) => settlePending(message.clientId);

  return {
    messages,
    pending,
    hasMore,
    draft,
    isTheyTyping,
    socketState,
    activity,
    changeDraft,
    sendText,
    sendImage,
    retry,
    discard,
    loadOlder,
  };
}

export type Conversation = ReturnType<typeof useChat>;
