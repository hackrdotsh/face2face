import { CheckIcon, ProhibitIcon, XIcon } from "@phosphor-icons/react";
import type { Connection } from "@/api/types";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardDescription,
  CardHeader,
  CardPanel,
  CardTitle,
} from "@/components/ui/card";
import type { ConnectionList } from "@/flows/use-connections";
import { hrefFor } from "@/navigation/routes";
import { ErrorAlert, Notice } from "./parts";

/** Chances still waiting on an answer. Accepted people move to Chats. */
export function PassedPage({ list }: { list: ConnectionList }) {
  const chances = pendingChances(list.connections);
  return (
    <Card>
      <CardHeader>
        <CardTitle>People you passed</CardTitle>
        <CardDescription>
          You have 24 hours to answer. You see only the interests you share.
        </CardDescription>
        <CardAction>
          <Button
            size="sm"
            variant="outline"
            disabled={list.activity.busy}
            onClick={list.reload}
          >
            Refresh
          </Button>
        </CardAction>
      </CardHeader>
      <CardPanel className="flex flex-col gap-4">
        <ErrorAlert message={list.activity.error} />
        {list.newlyConnectedId && (
          <Notice message="You both accepted.">
            <a
              className="font-medium underline underline-offset-4"
              href={hrefFor({ page: "chats", chatId: list.newlyConnectedId })}
            >
              Open the chat
            </a>
          </Notice>
        )}
        {chances.length === 0 ? (
          <p className="text-muted-foreground text-sm">
            Nobody waiting. Simulate an encounter from the dev panel.
          </p>
        ) : (
          <ul className="flex flex-col gap-3">
            {chances.map((connection) => (
              <ChanceRow
                key={connection.id}
                connection={connection}
                list={list}
              />
            ))}
          </ul>
        )}
      </CardPanel>
    </Card>
  );
}

export function pendingChances(connections: Connection[]): Connection[] {
  return connections.filter((connection) => connection.status === "pending");
}

function ChanceRow({
  connection,
  list,
}: {
  connection: Connection;
  list: ConnectionList;
}) {
  const { busy } = list.activity;
  const hasAnswered = connection.you.decision !== null;
  return (
    <li className="flex flex-col gap-2 rounded-lg border p-3 text-sm">
      <p className="font-medium">
        {connection.sharedInterests.length > 0
          ? `You both like ${connection.sharedInterests.join(", ")}`
          : "No shared interests"}
      </p>
      <p className="text-muted-foreground text-xs">
        {hasAnswered
          ? `You accepted. Waiting for them until ${formatTime(connection.expiresAt)}.`
          : `Answer by ${formatTime(connection.expiresAt)}.`}
      </p>
      <div className="flex flex-wrap gap-2">
        {!hasAnswered && (
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
        <Button
          size="sm"
          variant="destructive-outline"
          disabled={busy}
          onClick={() => list.block(connection.id)}
        >
          <ProhibitIcon />
          Block
        </Button>
      </div>
    </li>
  );
}

function formatTime(iso: string): string {
  return new Date(iso).toLocaleString([], {
    weekday: "short",
    hour: "numeric",
    minute: "2-digit",
  });
}
