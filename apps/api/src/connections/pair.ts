import type { ConnectionSide } from "../db/schema";

export interface OrderedPair {
  lowId: string;
  highId: string;
}

/** Orders two user IDs so each pair is stored one way only. */
export function orderPair(firstId: string, secondId: string): OrderedPair {
  return firstId < secondId
    ? { lowId: firstId, highId: secondId }
    : { lowId: secondId, highId: firstId };
}

export function sideOf(
  row: { userLowId: string; userHighId: string },
  userId: string,
): ConnectionSide | null {
  if (row.userLowId === userId) return "low";
  if (row.userHighId === userId) return "high";
  return null;
}

export function otherSide(side: ConnectionSide): ConnectionSide {
  return side === "low" ? "high" : "low";
}

export function userOnSide(
  row: { userLowId: string; userHighId: string },
  side: ConnectionSide,
): string {
  return side === "low" ? row.userLowId : row.userHighId;
}
