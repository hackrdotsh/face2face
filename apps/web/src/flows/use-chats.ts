import { useCallback, useEffect, useState } from "react";
import { listChats } from "@/api/chats";
import type { ChatSummary } from "@/api/types";
import { useSession } from "@/session/session";
import { useActivity } from "./use-activity";
import type { NotificationFeed } from "./use-notifications";

/**
 * The person's chats. Reloads on chat activity and on new notifications,
 * since a `connected` notification means a new chat exists.
 */
export function useChats(feed: NotificationFeed) {
  const { client } = useSession();
  const activity = useActivity();
  const [chats, setChats] = useState<ChatSummary[]>([]);
  const [hasLoaded, setHasLoaded] = useState(false);

  const reload = useCallback(
    () =>
      activity.run(async () => {
        setChats(await listChats(client));
        setHasLoaded(true);
      }),
    [activity.run, client],
  );

  const latestNotificationId = feed.notifications[0]?.id;
  const latestMessageId = feed.latestChatActivity?.messageId;
  useEffect(() => {
    void reload();
  }, [reload, latestNotificationId, latestMessageId]);

  const unreadCount = chats.reduce(
    (total, chat) => total + chat.unreadCount,
    0,
  );

  return { chats, hasLoaded, unreadCount, activity, reload };
}

export type ChatList = ReturnType<typeof useChats>;
