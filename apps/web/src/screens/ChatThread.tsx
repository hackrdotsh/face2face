import {
  ArrowLeftIcon,
  GlobeIcon,
  ImageIcon,
  PaperPlaneRightIcon,
  ProhibitIcon,
} from "@phosphor-icons/react";
import { type ReactNode, useEffect, useRef, useState } from "react";
import { mediaURL } from "@/api/chats";
import type { ChatImage, ChatMessage, ChatSummary } from "@/api/types";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardHeader,
  CardPanel,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import type { PendingMessage } from "@/flows/chat-messages";
import { type Conversation, useChat } from "@/flows/use-chat";
import type { ChatList } from "@/flows/use-chats";
import type { ConnectionList } from "@/flows/use-connections";
import { acceptedImageTypes } from "@/lib/image-types";
import { cn } from "@/lib/utils";
import type { Route } from "@/navigation/routes";
import { useSession } from "@/session/session";
import { ConnectionAvatar } from "./avatar";
import { chatTitle } from "./ChatsPage";
import { ErrorAlert, Notice, SocketBadge } from "./parts";

export function ChatThread({
  chat,
  chats,
  connections,
  navigate,
}: {
  chat: ChatSummary;
  chats: ChatList;
  connections: ConnectionList;
  navigate: (route: Route) => void;
}) {
  const conversation = useChat(chat.id);
  const isClosed = conversation.socketState === "closed";
  const backToChats = () => navigate({ page: "chats", chatId: null });
  return (
    <Card>
      <CardHeader className="flex-row items-center gap-2">
        <Button
          size="icon-sm"
          variant="ghost"
          aria-label="Back to chats"
          onClick={backToChats}
        >
          <ArrowLeftIcon />
        </Button>
        <ConnectionAvatar them={chat.connection.them} className="size-8" />
        <CardTitle className="truncate">{chatTitle(chat)}</CardTitle>
        <CardAction>
          <SocketBadge state={conversation.socketState} />
        </CardAction>
      </CardHeader>
      <CardPanel className="flex flex-col gap-3">
        <ErrorAlert
          message={conversation.activity.error ?? connections.activity.error}
        />
        {!isClosed && (
          <ConnectionBar
            chat={chat}
            connections={connections}
            onPublic={chats.reload}
            onBlocked={() => {
              void chats.reload();
              backToChats();
            }}
          />
        )}
        <MessageList conversation={conversation} />
        {isClosed ? (
          <Notice message="This chat has ended." />
        ) : (
          <Composer conversation={conversation} />
        )}
      </CardPanel>
    </Card>
  );
}

/** Who they are so far, and the actions on the connection behind this chat. */
function ConnectionBar({
  chat,
  connections,
  onPublic,
  onBlocked,
}: {
  chat: ChatSummary;
  connections: ConnectionList;
  onPublic: () => void;
  onBlocked: () => void;
}) {
  const [isConfirmingBlock, setIsConfirmingBlock] = useState(false);
  const { busy } = connections.activity;
  const { connection } = chat;
  const canGoPublic =
    connection.status === "private" && connection.you.publicAt === null;

  const goPublic = async () => {
    if (await connections.makePublic(connection.id)) onPublic();
  };
  const block = async () => {
    if (await connections.block(connection.id)) onBlocked();
  };

  return (
    <div className="flex flex-wrap items-center justify-between gap-2 text-sm">
      <p className="text-muted-foreground">{publicStatus(chat)}</p>
      <div className="flex gap-2">
        {canGoPublic && (
          <Button
            size="sm"
            variant="outline"
            disabled={busy}
            onClick={goPublic}
          >
            <GlobeIcon />
            Go public
          </Button>
        )}
        {isConfirmingBlock ? (
          <>
            <Button
              size="sm"
              variant="ghost"
              disabled={busy}
              onClick={() => setIsConfirmingBlock(false)}
            >
              Cancel
            </Button>
            <Button
              size="sm"
              variant="destructive"
              loading={busy}
              onClick={block}
            >
              Block for good
            </Button>
          </>
        ) : (
          <Button
            size="sm"
            variant="destructive-outline"
            disabled={busy}
            onClick={() => setIsConfirmingBlock(true)}
          >
            <ProhibitIcon />
            Block
          </Button>
        )}
      </div>
    </div>
  );
}

function publicStatus(chat: ChatSummary): string {
  const { connection } = chat;
  if (connection.status === "public") return "You both went public.";
  if (connection.you.publicAt)
    return "You chose to go public. Waiting for them.";
  return "Private. Go public to see who they are.";
}

function MessageList({ conversation }: { conversation: Conversation }) {
  const bottom = useRef<HTMLDivElement>(null);
  const { messages, pending, isTheyTyping } = conversation;
  const newestKey = `${messages.at(-1)?.id}:${pending.length}:${isTheyTyping}`;

  useEffect(() => {
    if (newestKey) bottom.current?.scrollIntoView({ block: "end" });
  }, [newestKey]);

  return (
    <div className="flex h-96 flex-col gap-2 overflow-y-auto rounded-lg border bg-muted/40 p-3">
      {conversation.hasMore && (
        <Button
          size="xs"
          variant="ghost"
          className="self-center"
          disabled={conversation.activity.busy}
          onClick={conversation.loadOlder}
        >
          Load earlier messages
        </Button>
      )}
      {messages.length === 0 && pending.length === 0 && (
        <p className="m-auto text-muted-foreground text-sm">No messages yet.</p>
      )}
      {messages.map((message) => (
        <MessageBubble key={message.id} message={message} />
      ))}
      {pending.map((message) => (
        <PendingBubble
          key={message.clientId}
          message={message}
          conversation={conversation}
        />
      ))}
      <p aria-live="polite" className="min-h-5 text-muted-foreground text-xs">
        {isTheyTyping ? "Typing…" : ""}
      </p>
      <div ref={bottom} />
    </div>
  );
}

function MessageBubble({ message }: { message: ChatMessage }) {
  const isOwn = message.from === "you";
  return (
    <div
      className={cn(
        "flex flex-col gap-0.5",
        isOwn ? "items-end" : "items-start",
      )}
    >
      <Bubble isOwn={isOwn}>
        {message.image && <ChatPhoto image={message.image} />}
        {message.text && (
          <p className="whitespace-pre-wrap break-words">{message.text}</p>
        )}
      </Bubble>
      <time className="px-1 text-muted-foreground text-xs tabular-nums">
        {new Date(message.createdAt).toLocaleTimeString([], {
          hour: "numeric",
          minute: "2-digit",
        })}
      </time>
    </div>
  );
}

function PendingBubble({
  message,
  conversation,
}: {
  message: PendingMessage;
  conversation: Conversation;
}) {
  const isFailed = message.status === "failed";
  return (
    <div className="flex flex-col items-end gap-0.5">
      <Bubble isOwn className="opacity-70">
        {message.localImageURL && (
          <img
            src={message.localImageURL}
            alt="Your photo, sending"
            className="max-h-48 rounded-md object-cover"
          />
        )}
        {message.text && (
          <p className="whitespace-pre-wrap break-words">{message.text}</p>
        )}
      </Bubble>
      {isFailed ? (
        <span className="flex items-center gap-1 text-destructive-foreground text-xs">
          Not sent.
          {(message.imageId || message.text) && (
            <Button
              size="xs"
              variant="link"
              onClick={() => conversation.retry(message)}
            >
              Retry
            </Button>
          )}
          <Button
            size="xs"
            variant="link"
            onClick={() => conversation.discard(message)}
          >
            Discard
          </Button>
        </span>
      ) : (
        <span className="px-1 text-muted-foreground text-xs">
          {message.status === "uploading" ? "Uploading…" : "Sending…"}
        </span>
      )}
    </div>
  );
}

function Bubble({
  isOwn,
  className,
  children,
}: {
  isOwn: boolean;
  className?: string;
  children: ReactNode;
}) {
  return (
    <div
      className={cn(
        "flex max-w-[80%] flex-col gap-2 rounded-2xl px-3 py-2 text-sm",
        isOwn
          ? "rounded-br-md bg-primary text-primary-foreground"
          : "rounded-bl-md border bg-background",
        className,
      )}
    >
      {children}
    </div>
  );
}

/** Shows the preview size, with its dimensions reserved before it loads. */
function ChatPhoto({ image }: { image: ChatImage }) {
  const { serverURL } = useSession();
  const { preview, original } = image.variants;
  return (
    <a
      href={mediaURL(serverURL, original.path)}
      target="_blank"
      rel="noreferrer"
      className="-mx-1 -mt-0.5 block"
    >
      <img
        src={mediaURL(serverURL, preview.path)}
        width={preview.width}
        height={preview.height}
        alt="Photo"
        className="h-auto max-h-64 w-full rounded-md bg-muted object-cover"
      />
    </a>
  );
}

function Composer({ conversation }: { conversation: Conversation }) {
  const fileInput = useRef<HTMLInputElement>(null);
  return (
    <form
      className="flex items-center gap-2"
      onSubmit={(event) => {
        event.preventDefault();
        conversation.sendText();
      }}
    >
      <input
        ref={fileInput}
        type="file"
        accept={acceptedImageTypes}
        className="hidden"
        onChange={(event) => {
          const file = event.target.files?.[0];
          event.target.value = "";
          if (file) void conversation.sendImage(file);
        }}
      />
      <Button
        type="button"
        size="icon"
        variant="outline"
        aria-label="Send a photo"
        onClick={() => fileInput.current?.click()}
      >
        <ImageIcon />
      </Button>
      <Input
        aria-label="Message"
        placeholder="Message"
        autoComplete="off"
        maxLength={4000}
        value={conversation.draft}
        onChange={(event) => conversation.changeDraft(event.target.value)}
      />
      <Button
        type="submit"
        size="icon"
        aria-label="Send"
        disabled={!conversation.draft.trim()}
      >
        <PaperPlaneRightIcon />
      </Button>
    </form>
  );
}
