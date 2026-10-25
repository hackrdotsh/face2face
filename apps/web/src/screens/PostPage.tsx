import { CaretLeftIcon } from "@phosphor-icons/react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardDescription,
  CardHeader,
  CardPanel,
  CardTitle,
} from "@/components/ui/card";
import { usePost } from "@/flows/use-post";
import { hrefFor } from "@/navigation/routes";
import { Avatar } from "./avatar";
import {
  AttendeeStack,
  EventDetails,
  PostForm,
  PostStatus,
  RsvpButton,
} from "./forum-parts";
import { ErrorAlert, Notice } from "./parts";

export function PostPage({
  postId,
  latestNotificationId,
}: {
  postId: string;
  latestNotificationId?: string;
}) {
  const view = usePost(postId, latestNotificationId);
  const [editing, setEditing] = useState(false);
  const [confirmingCancel, setConfirmingCancel] = useState(false);
  const { post } = view;

  if (!post) {
    return (
      <Card>
        <CardPanel className="flex flex-col items-start gap-3 text-sm">
          <ErrorAlert message={view.activity.error} />
          {view.hasLoaded && <p>This event is not available.</p>}
          <BackLink forumId={null} />
        </CardPanel>
      </Card>
    );
  }

  const canChange = post.isAuthor && !post.cancelled;
  return (
    <Card>
      <CardHeader>
        <BackLink forumId={post.forumId} />
        <CardTitle>{post.title}</CardTitle>
        <CardDescription>
          <Avatar
            avatar={post.author.avatar}
            className="mr-1 size-4 align-text-bottom"
          />
          Posted by {post.isAuthor ? "you" : post.author.name}
          {post.edited && " · edited"}
        </CardDescription>
        <CardAction>
          <PostStatus post={post} />
        </CardAction>
      </CardHeader>
      <CardPanel className="flex flex-col gap-4">
        <ErrorAlert message={view.activity.error ?? view.rsvpActivity.error} />
        {post.cancelled && <Notice message="The host cancelled this event." />}
        {editing ? (
          <PostForm
            post={post}
            busy={view.activity.busy}
            submitLabel="Save changes"
            onSubmit={async (input) => {
              const saved = await view.edit(input);
              if (saved) setEditing(false);
              return saved;
            }}
            onCancel={() => setEditing(false)}
          />
        ) : (
          <>
            <EventDetails post={post} />
            {post.description && (
              <p className="whitespace-pre-wrap text-sm">{post.description}</p>
            )}
            <div className="flex items-center justify-between gap-2">
              <AttendeeStack post={post} />
              <RsvpButton
                post={post}
                busy={view.rsvpActivity.busy}
                onRsvp={view.rsvp}
              />
            </div>
          </>
        )}
        {view.attendees.length > 0 && (
          <section className="flex flex-col gap-2">
            <h3 className="font-medium text-sm">Going</h3>
            <ul className="flex flex-col gap-2">
              {view.attendees.map((person) => (
                <li
                  key={person.userId}
                  className="flex items-center gap-2 text-sm"
                >
                  <Avatar avatar={person.avatar} />
                  {person.name}
                </li>
              ))}
            </ul>
          </section>
        )}
        {canChange && !editing && (
          <div className="flex justify-end gap-2 border-t pt-4">
            {confirmingCancel ? (
              <>
                <Button
                  variant="ghost"
                  onClick={() => setConfirmingCancel(false)}
                >
                  Keep event
                </Button>
                <Button
                  variant="destructive"
                  loading={view.activity.busy}
                  onClick={async () => {
                    await view.cancel();
                    setConfirmingCancel(false);
                  }}
                >
                  Cancel and tell attendees
                </Button>
              </>
            ) : (
              <>
                <Button
                  variant="destructive-outline"
                  onClick={() => setConfirmingCancel(true)}
                >
                  Cancel event
                </Button>
                <Button variant="outline" onClick={() => setEditing(true)}>
                  Edit
                </Button>
              </>
            )}
          </div>
        )}
      </CardPanel>
    </Card>
  );
}

function BackLink({ forumId }: { forumId: string | null }) {
  return (
    <a
      href={hrefFor({ page: "forums", forumId })}
      className="flex w-fit items-center gap-1 text-muted-foreground text-sm hover:text-foreground"
    >
      <CaretLeftIcon />
      {forumId ? "Back to forum" : "Forums"}
    </a>
  );
}
