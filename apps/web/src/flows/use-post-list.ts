import { useCallback, useEffect, useState } from "react";
import type { Post, PostPage } from "@/api/types";
import { replacePost } from "./posts";
import { useActivity } from "./use-activity";
import { useRsvp } from "./use-rsvp";

/**
 * A paged list of posts. `loadPage` gets the last post ID of the list for the
 * next page, and nothing for the first. Keep it stable with `useCallback`.
 */
export function usePostList(loadPage: (cursor?: string) => Promise<PostPage>) {
  const activity = useActivity();
  const [posts, setPosts] = useState<Post[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [hasLoaded, setHasLoaded] = useState(false);

  const reload = useCallback(
    () =>
      activity.run(async () => {
        const page = await loadPage();
        setPosts(page.posts);
        setHasMore(page.hasMore);
        setHasLoaded(true);
      }),
    [activity.run, loadPage],
  );

  useEffect(() => {
    setPosts([]);
    setHasLoaded(false);
    void reload();
  }, [reload]);

  const loadMore = () =>
    activity.run(async () => {
      const page = await loadPage(posts.at(-1)?.id);
      setPosts((current) => [...current, ...page.posts]);
      setHasMore(page.hasMore);
    });

  const show = useCallback(
    (post: Post) => setPosts((current) => replacePost(current, post)),
    [],
  );
  const { rsvp, activity: rsvpActivity } = useRsvp(show);

  return {
    posts,
    setPosts,
    hasMore,
    hasLoaded,
    activity,
    rsvpActivity,
    reload,
    loadMore,
    rsvp,
  };
}

export type PostList = ReturnType<typeof usePostList>;
