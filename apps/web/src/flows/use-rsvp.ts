import { useCallback } from "react";
import { setAttending } from "@/api/forums";
import type { Post } from "@/api/types";
import { useSession } from "@/session/session";
import { withAttending } from "./posts";
import { useActivity } from "./use-activity";

/**
 * Shows the RSVP right away through `show`, then shows the server's version,
 * or the previous version again if the request fails.
 */
export function useRsvp(show: (post: Post) => void) {
  const { client } = useSession();
  const activity = useActivity();

  const rsvp = useCallback(
    async (post: Post, attending: boolean) => {
      show(withAttending(post, attending));
      const saved = await activity.run(async () => {
        show(await setAttending(client, post.id, attending));
      });
      if (!saved) show(post);
      return saved;
    },
    [activity.run, client, show],
  );

  return { rsvp, activity };
}
