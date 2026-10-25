import { CalendarDotsIcon, CheckIcon, MapPinIcon } from "@phosphor-icons/react";
import { useState } from "react";
import type { Post, PostInput } from "@/api/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Field, FieldLabel } from "@/components/ui/field";
import { Textarea } from "@/components/ui/textarea";
import { formatEventTime, fromLocalInput, toLocalInput } from "@/flows/posts";
import { Avatar } from "./avatar";
import { ActionForm, TextField } from "./parts";

/** Overlapping faces of the first attendees, then the total. */
export function AttendeeStack({ post }: { post: Post }) {
  const { attendeeCount, attendeePreview } = post;
  if (attendeeCount === 0) {
    return <span className="text-muted-foreground text-sm">No one yet</span>;
  }
  const names = attendeePreview.map((person) => person.name).join(", ");
  return (
    <span className="flex items-center gap-2">
      <span className="flex -space-x-2">
        {attendeePreview.map((person) => (
          <Avatar
            key={person.userId}
            avatar={person.avatar}
            className="bg-card ring-2 ring-card"
          />
        ))}
      </span>
      <span className="text-muted-foreground text-sm tabular-nums">
        <span className="sr-only">{names}. </span>
        {attendeeCount} going
      </span>
    </span>
  );
}

export function EventDetails({ post }: { post: Post }) {
  return (
    <ul className="flex flex-col gap-1 text-muted-foreground text-sm">
      <li className="flex items-center gap-1.5">
        <CalendarDotsIcon className="shrink-0" />
        {formatEventTime(post)}
      </li>
      {post.location && (
        <li className="flex items-center gap-1.5">
          <MapPinIcon className="shrink-0" />
          {post.location}
        </li>
      )}
    </ul>
  );
}

export function PostStatus({ post }: { post: Post }) {
  if (post.cancelled) return <Badge variant="error">Cancelled</Badge>;
  if (post.past) return <Badge variant="outline">Over</Badge>;
  return null;
}

export function RsvpButton({
  post,
  busy,
  onRsvp,
}: {
  post: Post;
  busy: boolean;
  onRsvp: (attending: boolean) => void;
}) {
  if (post.cancelled || (post.past && !post.attending)) return null;
  return (
    <Button
      size="sm"
      variant={post.attending ? "default" : "outline"}
      aria-pressed={post.attending}
      disabled={busy || post.past}
      onClick={() => onRsvp(!post.attending)}
    >
      {post.attending && <CheckIcon />}
      {post.attending ? "Going" : "I'm going"}
    </Button>
  );
}

interface PostDraft {
  title: string;
  description: string;
  location: string;
  startsAt: string;
  endsAt: string;
}

function draftOf(post: Post | null): PostDraft {
  return {
    title: post?.title ?? "",
    description: post?.description ?? "",
    location: post?.location ?? "",
    startsAt: toLocalInput(post?.startsAt ?? null),
    endsAt: toLocalInput(post?.endsAt ?? null),
  };
}

interface DraftProblems {
  title?: string;
  startsAt?: string;
  endsAt?: string;
}

function readDraft(
  draft: PostDraft,
): { input: PostInput } | { problems: DraftProblems } {
  const title = draft.title.trim();
  const startsAt = fromLocalInput(draft.startsAt);
  const endsAt = fromLocalInput(draft.endsAt);
  const problems: DraftProblems = {};
  if (!title) problems.title = "Add a title.";
  if (!startsAt) problems.startsAt = "Add a start time.";
  if (startsAt && endsAt && endsAt < startsAt) {
    problems.endsAt = "The end time must be after the start time.";
  }
  if (!startsAt || Object.keys(problems).length > 0) return { problems };
  return {
    input: {
      title,
      description: draft.description.trim() || null,
      location: draft.location.trim() || null,
      startsAt,
      endsAt,
    },
  };
}

/** Creates a post when `post` is null, and edits it otherwise. */
export function PostForm({
  post,
  busy,
  submitLabel,
  onSubmit,
  onCancel,
}: {
  post: Post | null;
  busy: boolean;
  submitLabel: string;
  onSubmit: (input: PostInput) => Promise<boolean>;
  onCancel: () => void;
}) {
  const [draft, setDraft] = useState(() => draftOf(post));
  const [problems, setProblems] = useState<DraftProblems>({});
  const set = (field: keyof PostDraft) => (value: string) =>
    setDraft((current) => ({ ...current, [field]: value }));

  const submit = async () => {
    const read = readDraft(draft);
    if ("problems" in read) {
      setProblems(read.problems);
      return;
    }
    setProblems({});
    if (await onSubmit(read.input)) setDraft(draftOf(null));
  };

  return (
    <ActionForm onSubmit={submit}>
      <TextField
        label="Title"
        value={draft.title}
        maxLength={120}
        error={problems.title}
        onValueChange={set("title")}
      />
      <Field className="w-full">
        <FieldLabel>Description (optional)</FieldLabel>
        <Textarea
          value={draft.description}
          maxLength={4000}
          rows={3}
          onChange={(event) => set("description")(event.target.value)}
        />
      </Field>
      <TextField
        label="Location (optional)"
        value={draft.location}
        maxLength={200}
        onValueChange={set("location")}
      />
      <div className="grid gap-4 sm:grid-cols-2">
        <TextField
          label="Starts"
          type="datetime-local"
          value={draft.startsAt}
          error={problems.startsAt}
          onValueChange={set("startsAt")}
        />
        <TextField
          label="Ends (optional)"
          type="datetime-local"
          value={draft.endsAt}
          error={problems.endsAt}
          onValueChange={set("endsAt")}
        />
      </div>
      <div className="flex justify-end gap-2">
        <Button type="button" variant="ghost" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit" loading={busy}>
          {submitLabel}
        </Button>
      </div>
    </ActionForm>
  );
}
