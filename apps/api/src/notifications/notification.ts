/** What happened, as told to one person. Holds no identity of the other person. */
export type NotificationEvent =
  | {
      kind: "encounter";
      connectionId: string;
      sharedInterests: string[];
      expiresAt: string;
    }
  | { kind: "connected"; connectionId: string }
  | { kind: "public"; connectionId: string }
  /** One card per chat. The chat ID is the connection ID. */
  | { kind: "message"; chatId: string }
  | {
      kind: "post_updated" | "post_cancelled" | "post_rsvp";
      postId: string;
      forumId: string;
    };

export type Notification = NotificationEvent & {
  id: string;
  createdAt: string;
};

export interface Notifier {
  send(userId: string, event: NotificationEvent): Promise<void>;
}

export function coordinatorNotifier(env: Env): Notifier {
  return {
    async send(userId, event) {
      await env.USER_COORDINATORS.getByName(userId).notify(event);
    },
  };
}

/**
 * The lock-screen text for events that reach a phone outside the app. Other
 * events stay in the inbox only. The text never names the other person.
 */
export function pushTextFor(
  event: NotificationEvent,
): { title: string; body: string } | null {
  switch (event.kind) {
    case "encounter":
      return {
        title: "A new hello",
        body:
          event.sharedInterests.length === 0
            ? "There's a new chance to connect."
            : `A new chance to connect over ${event.sharedInterests.join(" and ")}.`,
      };
    case "connected":
      return {
        title: "It's a connection",
        body: "You both said yes. Find your new connection at the café.",
      };
    case "public":
      return {
        title: "A little more face to face",
        body: "You both chose to share your profiles. Say hello again.",
      };
    default:
      return null;
  }
}
