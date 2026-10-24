import {
  CheckIcon,
  GlobeIcon,
  ProhibitIcon,
  XIcon,
} from "@phosphor-icons/react";
import type {
  AppNotification,
  Connection,
  ConnectionStatus,
} from "@/api/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardDescription,
  CardHeader,
  CardPanel,
  CardTitle,
} from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { type ConnectionList, useConnections } from "@/flows/use-connections";
import { type SocketState, useNotifications } from "@/flows/use-notifications";
import { ErrorAlert } from "./parts";

const statusBadges: Record<
  ConnectionStatus,
  { label: string; variant: "info" | "outline" | "success" | "error" }
> = {
  pending: { label: "pending", variant: "info" },
  expired: { label: "expired", variant: "outline" },
  private: { label: "connected", variant: "success" },
  public: { label: "public", variant: "success" },
  blocked: { label: "blocked", variant: "error" },
};

const socketBadges: Record<
  SocketState,
  { label: string; variant: "success" | "warning" | "outline" }
> = {
  live: { label: "live", variant: "success" },
  connecting: { label: "connecting", variant: "outline" },
  offline: { label: "offline", variant: "warning" },
};

export function ConnectionsCard() {
  const feed = useNotifications();
  const list = useConnections(feed.notifications[0]?.id);
  const socket = socketBadges[feed.socketState];
  return (
    <Card>
      <CardHeader>
        <CardTitle>People you passed</CardTitle>
        <CardDescription>
          You see only shared interests until you both go public.
        </CardDescription>
        <CardAction>
          <Badge variant={socket.variant}>{socket.label}</Badge>
        </CardAction>
      </CardHeader>
      <CardPanel className="flex flex-col gap-4">
        <ErrorAlert message={list.activity.error ?? feed.activity.error} />
        {list.connections.length === 0 ? (
          <p className="text-muted-foreground text-sm">
            Nobody yet. Simulate an encounter from the dev panel.
          </p>
        ) : (
          <ul className="flex flex-col gap-3">
            {list.connections.map((connection) => (
              <ConnectionRow
                key={connection.id}
                connection={connection}
                list={list}
              />
            ))}
          </ul>
        )}
        <Button
          variant="outline"
          disabled={list.activity.busy}
          onClick={() => {
            void list.reload();
            void feed.reload();
          }}
        >
          Refresh
        </Button>
        <Separator />
        <h3 className="font-medium text-sm">Notifications</h3>
        {feed.notifications.length === 0 ? (
          <p className="text-muted-foreground text-sm">No notifications.</p>
        ) : (
          <ul className="flex flex-col gap-1 text-sm">
            {feed.notifications.slice(0, 10).map((notification) => (
              <li key={notification.id} className="flex justify-between gap-2">
                <span>{describeNotification(notification)}</span>
                <time className="shrink-0 text-muted-foreground tabular-nums">
                  {new Date(notification.createdAt).toLocaleTimeString()}
                </time>
              </li>
            ))}
          </ul>
        )}
      </CardPanel>
    </Card>
  );
}

function ConnectionRow({
  connection,
  list,
}: {
  connection: Connection;
  list: ConnectionList;
}) {
  const { busy } = list.activity;
  const status = statusBadges[connection.status];
  const canDecide =
    connection.status === "pending" && connection.you.decision === null;
  const canGoPublic =
    connection.status === "private" && connection.you.publicAt === null;
  return (
    <li className="flex flex-col gap-2 rounded-lg border p-3 text-sm">
      <div className="flex items-center justify-between gap-2">
        <span className="font-medium">
          {connection.them
            ? `${connection.them.name}${connection.them.age ? `, ${connection.them.age}` : ""}`
            : "Someone you passed"}
        </span>
        <Badge variant={status.variant}>{status.label}</Badge>
      </div>
      <p className="text-muted-foreground">
        {connection.sharedInterests.length > 0
          ? `You both like ${connection.sharedInterests.join(", ")}.`
          : "No shared interests."}
      </p>
      {connection.them && (
        <p className="text-muted-foreground">
          Their interests: {connection.them.interests.join(", ") || "none"}
        </p>
      )}
      <p className="text-muted-foreground text-xs">
        {statusDetail(connection)}
      </p>
      <div className="flex flex-wrap gap-2">
        {canDecide && (
          <>
            <Button
              size="sm"
              disabled={busy}
              onClick={() => list.decide(connection.id, "accepted")}
            >
              <CheckIcon />
              Accept
            </Button>
            <Button
              size="sm"
              variant="outline"
              disabled={busy}
              onClick={() => list.decide(connection.id, "declined")}
            >
              <XIcon />
              Decline
            </Button>
          </>
        )}
        {canGoPublic && (
          <Button
            size="sm"
            variant="outline"
            disabled={busy}
            onClick={() => list.makePublic(connection.id)}
          >
            <GlobeIcon />
            Go public
          </Button>
        )}
        {connection.status !== "blocked" && (
          <Button
            size="sm"
            variant="destructive-outline"
            disabled={busy}
            onClick={() => list.block(connection.id)}
          >
            <ProhibitIcon />
            Block
          </Button>
        )}
      </div>
    </li>
  );
}

function statusDetail(connection: Connection): string {
  switch (connection.status) {
    case "pending":
      return connection.you.decision === "accepted"
        ? `You accepted. Waiting until ${formatTime(connection.expiresAt)}.`
        : `Answer by ${formatTime(connection.expiresAt)}.`;
    case "expired":
      return "This chance ended.";
    case "private":
      return connection.you.publicAt
        ? "You agreed to go public. Waiting for them."
        : "You both accepted. Go public to see who they are.";
    case "public":
      return "You both went public.";
    case "blocked":
      return "You blocked this person. They will not be told.";
  }
}

function describeNotification(notification: AppNotification): string {
  switch (notification.kind) {
    case "encounter":
      return notification.sharedInterests.length > 0
        ? `You passed someone who likes ${notification.sharedInterests.join(", ")}.`
        : "You passed someone.";
    case "connected":
      return "You both accepted. You're connected.";
    case "public":
      return "You both went public.";
  }
}

function formatTime(iso: string): string {
  return new Date(iso).toLocaleString([], {
    weekday: "short",
    hour: "numeric",
    minute: "2-digit",
  });
}
