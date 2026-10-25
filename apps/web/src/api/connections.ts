import type { APIClient } from "./client";
import type { Connection, ConnectionDecision } from "./types";

export async function listConnections(client: APIClient) {
  const { connections } = await client.send<{ connections: Connection[] }>({
    path: "api/connections",
    authenticated: true,
  });
  return connections;
}

export function decideConnection(
  client: APIClient,
  connectionId: string,
  decision: ConnectionDecision,
) {
  return changeConnection(client, connectionId, "decision", { decision });
}

export function goPublic(client: APIClient, connectionId: string) {
  return changeConnection(client, connectionId, "public", {});
}

export function blockConnection(client: APIClient, connectionId: string) {
  return changeConnection(client, connectionId, "block", {});
}

async function changeConnection(
  client: APIClient,
  connectionId: string,
  action: "decision" | "public" | "block",
  body: unknown,
) {
  const { connection } = await client.send<{ connection: Connection }>({
    path: `api/connections/${encodeURIComponent(connectionId)}/${action}`,
    body,
    authenticated: true,
  });
  return connection;
}
