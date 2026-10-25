import { useCallback, useEffect, useState } from "react";
import {
  blockConnection,
  decideConnection,
  goPublic,
  listConnections,
} from "@/api/connections";
import type { Connection, ConnectionDecision } from "@/api/types";
import { useSession } from "@/session/session";
import { useActivity } from "./use-activity";

/**
 * The person's connections and the actions on them. Reloads whenever
 * `latestNotificationId` changes, because every notification is about one.
 */
export function useConnections(latestNotificationId: string | undefined) {
  const { client } = useSession();
  const activity = useActivity();
  const [connections, setConnections] = useState<Connection[]>([]);
  const [newlyConnectedId, setNewlyConnectedId] = useState<string | null>(null);

  const reload = useCallback(
    () =>
      activity.run(async () => {
        setConnections(await listConnections(client));
      }),
    [activity.run, client],
  );

  // Every notification is about a connection, so a new one means the list changed.
  useEffect(() => {
    void reload();
  }, [reload, latestNotificationId]);

  const replace = (updated: Connection) =>
    setConnections((current) =>
      current
        .map((existing) => (existing.id === updated.id ? updated : existing))
        .filter((connection) => connection.status !== "expired"),
    );

  const decide = (connectionId: string, decision: ConnectionDecision) =>
    activity.run(async () => {
      const updated = await decideConnection(client, connectionId, decision);
      replace(updated);
      if (updated.status === "private") setNewlyConnectedId(updated.id);
    });

  const makePublic = (connectionId: string) =>
    activity.run(async () => {
      replace(await goPublic(client, connectionId));
    });

  const block = (connectionId: string) =>
    activity.run(async () => {
      replace(await blockConnection(client, connectionId));
    });

  return {
    connections,
    newlyConnectedId,
    activity,
    reload,
    decide,
    makePublic,
    block,
  };
}

export type ConnectionList = ReturnType<typeof useConnections>;
