import type { APIClient } from "./client";
import type {
  AppNotification,
  DevConnection,
  DevUser,
  SimulatedEncounter,
} from "./types";

/** Calls a local-only route. The API answers 404 unless `DEV_TOOLS` is "true". */
export function seedUsers(client: APIClient) {
  return client.send<{ userIds: string[]; password: string }>({
    path: "api/dev/seed",
    body: {},
  });
}

/** Seeds the people too, then replaces the seeded forum posts. */
export function seedForums(client: APIClient) {
  return client.send<{ postIds: string[] }>({
    path: "api/dev/forums/seed",
    body: {},
  });
}

export function listDevUsers(client: APIClient) {
  return client.send<{ seedPassword: string; users: DevUser[] }>({
    path: "api/dev/users",
  });
}

export async function listDevConnections(client: APIClient) {
  const { connections } = await client.send<{
    connections: DevConnection[];
  }>({ path: "api/dev/connections" });
  return connections;
}

export function simulateEncounter(
  client: APIClient,
  firstUserId: string,
  secondUserId: string,
) {
  return client.send<SimulatedEncounter>({
    path: "api/dev/encounters",
    body: { firstUserId, secondUserId },
  });
}

export function expireConnection(client: APIClient, connectionId: string) {
  return client.send({
    path: `api/dev/connections/${encodeURIComponent(connectionId)}/expire`,
    body: {},
  });
}

export function resetConnections(client: APIClient) {
  return client.send({ path: "api/dev/reset", body: {} });
}

export async function listUserNotifications(client: APIClient, userId: string) {
  const { notifications } = await client.send<{
    notifications: AppNotification[];
  }>({ path: `api/dev/users/${encodeURIComponent(userId)}/notifications` });
  return notifications;
}
