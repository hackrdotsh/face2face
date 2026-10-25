import { useCallback, useEffect, useState } from "react";
import { signInWithPassword } from "@/api/auth";
import * as dev from "@/api/dev";
import type { AppNotification, DevConnection, DevUser } from "@/api/types";
import { useActivity } from "@/flows/use-activity";
import { useSession } from "@/session/session";

const pairSize = 2;

/** Seeded people, simulated encounters, and raw connection rows for local testing. */
export function useSimulator() {
  const session = useSession();
  const { client } = session;
  const activity = useActivity();
  const [users, setUsers] = useState<DevUser[]>([]);
  const [seedPassword, setSeedPassword] = useState("");
  const [connections, setConnections] = useState<DevConnection[]>([]);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [notice, setNotice] = useState<string | null>(null);
  const [inbox, setInbox] = useState<{
    userId: string;
    notifications: AppNotification[];
  } | null>(null);

  const loadState = useCallback(async () => {
    const [directory, rows] = await Promise.all([
      dev.listDevUsers(client),
      dev.listDevConnections(client),
    ]);
    setUsers(directory.users);
    setSeedPassword(directory.seedPassword);
    setConnections(rows);
  }, [client]);

  const reload = useCallback(
    () => activity.run(loadState),
    [activity.run, loadState],
  );

  useEffect(() => {
    void reload();
  }, [reload]);

  const runAndReload = (action: () => Promise<string | null>) =>
    activity.run(async () => {
      setNotice(await action());
      await loadState();
    });

  const seed = () =>
    runAndReload(async () => {
      const { userIds } = await dev.seedUsers(client);
      return `Seeded ${userIds.length} people.`;
    });

  const seedForumPosts = () =>
    runAndReload(async () => {
      const { postIds } = await dev.seedForums(client);
      return `Seeded ${postIds.length} forum posts.`;
    });

  const toggleSelected = (userId: string) =>
    setSelectedIds((current) =>
      current.includes(userId)
        ? current.filter((id) => id !== userId)
        : [...current, userId].slice(-pairSize),
    );

  const simulateEncounter = () =>
    runAndReload(async () => {
      const [firstUserId, secondUserId] = selectedIds;
      if (!firstUserId || !secondUserId) return "Pick two people first.";
      const result = await dev.simulateEncounter(
        client,
        firstUserId,
        secondUserId,
      );
      return encounterNotice(result.outcome);
    });

  const expire = (connectionId: string) =>
    runAndReload(async () => {
      await dev.expireConnection(client, connectionId);
      return "Expired. Each person sees it on their next refresh.";
    });

  const resetConnections = () =>
    runAndReload(async () => {
      await dev.resetConnections(client);
      return "Deleted every connection, block, and forum post.";
    });

  const signInAs = (user: DevUser) =>
    activity.run(async () => {
      await signInWithPassword(client, user.email, seedPassword);
      await session.refreshAccount();
      setNotice(`Signed in as ${user.name}.`);
    });

  const showInbox = (userId: string) =>
    activity.run(async () => {
      setInbox({
        userId,
        notifications: await dev.listUserNotifications(client, userId),
      });
    });

  const nameOf = (userId: string) =>
    users.find((user) => user.id === userId)?.name ?? userId;

  return {
    users,
    connections,
    selectedIds,
    notice,
    inbox,
    activity,
    reload,
    seed,
    seedForumPosts,
    toggleSelected,
    simulateEncounter,
    expire,
    resetConnections,
    signInAs,
    showInbox,
    nameOf,
  };
}

export type Simulator = ReturnType<typeof useSimulator>;

function encounterNotice(outcome: "created" | "alreadyActive" | "ignored") {
  switch (outcome) {
    case "created":
      return "Simulated encounter. Both people were notified.";
    case "alreadyActive":
      return "They already have an open connection. Nothing changed.";
    case "ignored":
      return "One of them blocked the other. The encounter was ignored.";
  }
}
