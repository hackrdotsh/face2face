import { loadCounterparts } from "../connections/connections";
import type { Connection } from "../connections/lifecycle";
import { findConnectionFor, listConnectionsFor } from "../connections/store";
import { viewConnection } from "../connections/view";
import type { Database } from "../db/client";
import type { PersonViewer } from "../profiles/person";
import { chatAccessFor } from "./chat-access";
import type { ChatRoom } from "./chat-room";
import type { ChatSummary } from "./chat-types";

export type ChatRooms = DurableObjectNamespace<ChatRoom>;

/** Every chat the person can open, most recent activity first. */
export async function listChatSummaries(
  db: Database,
  viewPerson: PersonViewer,
  rooms: ChatRooms,
  userId: string,
  now: Date,
): Promise<ChatSummary[]> {
  const rows = await listConnectionsFor(db, userId);
  const summaries = await summarize(db, viewPerson, rooms, rows, userId, now);
  return summaries.sort(
    (first, second) => activityTime(second) - activityTime(first),
  );
}

export async function getChatSummary(
  db: Database,
  viewPerson: PersonViewer,
  rooms: ChatRooms,
  userId: string,
  connectionId: string,
  now: Date,
): Promise<ChatSummary | null> {
  const row = await findConnectionFor(db, connectionId, userId);
  if (!row) return null;
  const [summary] = await summarize(db, viewPerson, rooms, [row], userId, now);
  return summary ?? null;
}

async function summarize(
  db: Database,
  viewPerson: PersonViewer,
  rooms: ChatRooms,
  rows: Connection[],
  userId: string,
  now: Date,
): Promise<ChatSummary[]> {
  const chatRows = rows.filter((row) => chatAccessFor(row, userId));
  const counterparts = await loadCounterparts(
    db,
    viewPerson,
    chatRows,
    userId,
    now,
  );
  return Promise.all(
    chatRows.flatMap((row) => {
      const access = chatAccessFor(row, userId);
      const connection = viewConnection(row, userId, counterparts);
      if (!access || !connection) return [];
      return rooms
        .getByName(row.id)
        .summarize(access)
        .then((room) => ({ id: row.id, connection, ...room }));
    }),
  );
}

function activityTime(summary: ChatSummary): number {
  return Date.parse(
    summary.lastMessage?.createdAt ??
      summary.connection.resolvedAt ??
      summary.connection.createdAt,
  );
}
