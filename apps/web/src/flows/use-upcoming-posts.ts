import { useCallback } from "react";
import { listUpcomingPosts } from "@/api/forums";
import { useSession } from "@/session/session";
import { usePostList } from "./use-post-list";

/** Upcoming events from all of the person's forums, soonest first. */
export function useUpcomingPosts() {
  const { client } = useSession();
  return usePostList(
    useCallback(
      (cursor?: string) => listUpcomingPosts(client, cursor),
      [client],
    ),
  );
}
