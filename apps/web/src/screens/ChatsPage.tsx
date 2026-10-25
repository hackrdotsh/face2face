import { CaretRightIcon } from "@phosphor-icons/react";
import type { ChatMessage, ChatSummary } from "@/api/types";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardAction,
  CardDescription,
  CardHeader,
  CardPanel,
  CardTitle,
} from "@/components/ui/card";
import type { ChatList } from "@/flows/use-chats";
import type { ConnectionList } from "@/flows/use-connections";
import type { NotificationFeed } from "@/flows/use-notifications";
import { hrefFor, type Route } from "@/navigation/routes";
import { ChatThread } from "./ChatThread";
import { ErrorAlert, SocketBadge } from "./parts";

export function ChatsPage({
  chatId,
  chats,
  connections,
  feed,
  navigate,
}: {
  chatId: string | null;
  chats: ChatList;
  connections: ConnectionList;
  feed: NotificationFeed;
  navigate: (route: Route) => void;
}) {
  if (chatId) {
    const chat = chats.chats.find((candidate) => candidate.id === chatId);
    if (chat) {
      return (
        <ChatThread
          chat={chat}
          chats={chats}
          connections={connections}
          navigate={navigate}
        />
      );
    }
    if (chats.hasLoaded) return <MissingChat />;
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Chats</CardTitle>
        <CardDescription>
          Open once you both accept. Names stay hidden until you both go public.
        </CardDescription>
        <CardAction>
          <SocketBadge state={feed.socketState} />
        </CardAction>
      </CardHeader>
      <CardPanel className="flex flex-col gap-3">
        <ErrorAlert message={chats.activity.error} />
        {chats.chats.length === 0 ? (
          <p className="text-muted-foreground text-sm">
            No chats yet. Accept someone you passed to start one.
          </p>
        ) : (
          <ul className="-mx-2 flex flex-col">
            {chats.chats.map((chat) => (
              <li key={chat.id}>
                <ChatRow chat={chat} />
              </li>
            ))}
          </ul>
        )}
      </CardPanel>
    </Card>
  );
}

function MissingChat() {
  return (
    <Card>
      <CardPanel className="flex flex-col items-start gap-3 text-sm">
        <p>This chat is not available. It may have ended.</p>
        <a
          className="font-medium underline underline-offset-4"
          href={hrefFor({ page: "chats", chatId: null })}
        >
          Back to chats
        </a>
      </CardPanel>
    </Card>
  );
}

function ChatRow({ chat }: { chat: ChatSummary }) {
  const hasUnread = chat.unreadCount > 0;
  return (
    <a
      href={hrefFor({ page: "chats", chatId: chat.id })}
      className="flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-left text-sm hover:bg-accent focus-visible:outline-2 focus-visible:outline-ring"
    >
      <span className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="flex items-baseline justify-between gap-2">
          <span className={hasUnread ? "font-semibold" : "font-medium"}>
            {chatTitle(chat)}
          </span>
          {chat.lastMessage && (
            <time className="shrink-0 text-muted-foreground text-xs tabular-nums">
              {formatShortTime(chat.lastMessage.createdAt)}
            </time>
          )}
        </span>
        <span className="truncate text-muted-foreground">
          {preview(chat.lastMessage)}
        </span>
      </span>
      {hasUnread && (
        <Badge size="sm" aria-label={`${chat.unreadCount} unread`}>
          {chat.unreadCount}
        </Badge>
      )}
      <CaretRightIcon className="shrink-0 text-muted-foreground" />
    </a>
  );
}

export function chatTitle(chat: ChatSummary): string {
  const them = chat.connection.them;
  if (them) return them.age ? `${them.name}, ${them.age}` : them.name;
  const shared = chat.connection.sharedInterests;
  return shared.length > 0
    ? `Someone who likes ${shared.slice(0, 2).join(" and ")}`
    : "Someone you passed";
}

function preview(message: ChatMessage | null): string {
  if (!message) return "Say hi.";
  const body = message.text ?? (message.image ? "Photo" : "");
  return message.from === "you" ? `You: ${body}` : body;
}

function formatShortTime(iso: string): string {
  const date = new Date(iso);
  const isToday = date.toDateString() === new Date().toDateString();
  return isToday
    ? date.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })
    : date.toLocaleDateString([], { month: "short", day: "numeric" });
}
