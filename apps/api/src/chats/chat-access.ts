import type { Connection } from "../connections/lifecycle";
import { sideOf } from "../connections/pair";
import { findConnectionFor } from "../connections/store";
import type { Database } from "../db/client";
import type { ChatAccess } from "./chat-types";

/** Only people who both accepted can chat. A block ends the chat for both. */
export function hasChat(row: Connection): boolean {
  return row.status === "private" || row.status === "public";
}

export function chatAccessFor(
  row: Connection,
  userId: string,
): ChatAccess | null {
  const side = sideOf(row, userId);
  if (!side || !hasChat(row)) return null;
  return {
    connectionId: row.id,
    side,
    lowUserId: row.userLowId,
    highUserId: row.userHighId,
  };
}

export async function findChatAccess(
  db: Database,
  connectionId: string,
  userId: string,
): Promise<ChatAccess | null> {
  const row = await findConnectionFor(db, connectionId, userId);
  return row ? chatAccessFor(row, userId) : null;
}
