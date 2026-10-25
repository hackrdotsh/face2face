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
