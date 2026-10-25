import { useCallback, useEffect, useState } from "react";
import { cancelPost, editPost, getPost, listAttendees } from "@/api/forums";
import type { ForumPerson, Post, PostInput } from "@/api/types";
import { useSession } from "@/session/session";
import { useActivity } from "./use-activity";
import { useRsvp } from "./use-rsvp";

/**
 * One post and its full attendee list. Reloads when a new notification
 * arrives, since it may be about this post.
 */
export function usePost(postId: string, latestNotificationId?: string) {
  const { client } = useSession();
  const activity = useActivity();
  const [post, setPost] = useState<Post | null>(null);
  const [attendees, setAttendees] = useState<ForumPerson[]>([]);
  const [hasLoaded, setHasLoaded] = useState(false);

  const reload = useCallback(
    () =>
      activity.run(async () => {
        try {
          const [loaded, people] = await Promise.all([
            getPost(client, postId),
            listAttendees(client, postId),
          ]);
          setPost(loaded);
          setAttendees(people);
        } finally {
          setHasLoaded(true);
        }
      }),
    [activity.run, client, postId],
  );

  useEffect(() => {
    void reload();
  }, [reload, latestNotificationId]);

  const edit = (changes: Partial<PostInput>) =>
    activity.run(async () => {
      setPost(await editPost(client, postId, changes));
    });

  const cancel = () =>
    activity.run(async () => {
      setPost(await cancelPost(client, postId));
    });

  const show = useCallback((next: Post) => setPost(next), []);
  const { rsvp: sendRsvp, activity: rsvpActivity } = useRsvp(show);
  const rsvp = async (attending: boolean) => {
    if (!post) return;
    if (!(await sendRsvp(post, attending))) return;
    await activity.run(async () => {
      setAttendees(await listAttendees(client, postId));
    });
  };

  return {
    post,
    attendees,
    hasLoaded,
    activity,
    rsvpActivity,
    reload,
    edit,
    cancel,
    rsvp,
  };
}
