import { CaretRightIcon } from "@phosphor-icons/react";
import type { AppNotification } from "@/api/types";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardDescription,
  CardHeader,
  CardPanel,
  CardTitle,
} from "@/components/ui/card";
import type { NotificationFeed } from "@/flows/use-notifications";
import { hrefFor, type Route } from "@/navigation/routes";
import { ErrorAlert, SocketBadge } from "./parts";

export function NotificationsPage({ feed }: { feed: NotificationFeed }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Notifications</CardTitle>
        <CardDescription>
          The inbox keeps the latest 200. New ones arrive live over the socket.
        </CardDescription>
        <CardAction className="flex items-center gap-2">
          <SocketBadge state={feed.socketState} />
          <Button
            size="sm"
            variant="outline"
            disabled={feed.activity.busy}
            onClick={feed.reload}
          >
            Refresh
          </Button>
        </CardAction>
      </CardHeader>
      <CardPanel className="flex flex-col gap-3">
        <ErrorAlert message={feed.activity.error} />
        {feed.notifications.length === 0 ? (
          <p className="text-muted-foreground text-sm">No notifications.</p>
        ) : (
          <ul className="-mx-2 flex flex-col">
            {feed.notifications.map((notification) => (
              <li key={notification.id}>
                <a
                  href={hrefFor(destinationOf(notification))}
                  className="flex items-center gap-3 rounded-lg px-2 py-2.5 text-sm hover:bg-accent focus-visible:outline-2 focus-visible:outline-ring"
                >
                  <span className="flex-1">
                    {describeNotification(notification)}
                  </span>
                  <time className="shrink-0 text-muted-foreground text-xs tabular-nums">
                    {new Date(notification.createdAt).toLocaleTimeString([], {
                      hour: "numeric",
                      minute: "2-digit",
                    })}
                  </time>
                  <CaretRightIcon className="shrink-0 text-muted-foreground" />
                </a>
              </li>
            ))}
          </ul>
        )}
      </CardPanel>
    </Card>
  );
}

function destinationOf(notification: AppNotification): Route {
  switch (notification.kind) {
    case "encounter":
      return { page: "passed" };
    case "post_updated":
    case "post_cancelled":
    case "post_rsvp":
      return { page: "post", postId: notification.postId };
    default:
      return { page: "chats", chatId: notification.connectionId };
  }
}

function describeNotification(notification: AppNotification): string {
  switch (notification.kind) {
    case "encounter":
      return notification.sharedInterests.length > 0
        ? `You passed someone who likes ${notification.sharedInterests.join(", ")}.`
        : "You passed someone.";
    case "connected":
      return "You both accepted. Your chat is open.";
    case "public":
      return "You both went public.";
    case "post_updated":
      return "An event you're going to changed.";
    case "post_cancelled":
      return "An event you're going to was cancelled.";
    case "post_rsvp":
      return "Someone is going to your event.";
  }
}
