import { useCallback } from "react";
import { createPost, listPosts } from "@/api/forums";
import type { PostInput } from "@/api/types";
import { useSession } from "@/session/session";
import { usePostList } from "./use-post-list";

/** One forum's posts, newest first, loaded a page at a time. */
export function useForumFeed(forumId: string) {
  const { client } = useSession();
  const list = usePostList(
    useCallback(
      (cursor?: string) => listPosts(client, forumId, cursor),
      [client, forumId],
    ),
  );

  const create = (input: PostInput) =>
    list.activity.run(async () => {
      const post = await createPost(client, forumId, input);
      list.setPosts((current) => [post, ...current]);
    });

  return { ...list, create };
}
