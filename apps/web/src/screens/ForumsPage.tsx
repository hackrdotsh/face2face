import { CaretLeftIcon, CaretRightIcon, PlusIcon } from "@phosphor-icons/react";
import { useState } from "react";
import type { Forum, Post } from "@/api/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardDescription,
  CardHeader,
  CardPanel,
  CardTitle,
} from "@/components/ui/card";
import { Tabs, TabsList, TabsPanel, TabsTab } from "@/components/ui/tabs";
import { useForumFeed } from "@/flows/use-forum-feed";
import { type ForumList, useForums } from "@/flows/use-forums";
import type { PostList } from "@/flows/use-post-list";
import { useUpcomingPosts } from "@/flows/use-upcoming-posts";
import { hrefFor } from "@/navigation/routes";
import { Avatar } from "./avatar";
import {
  AttendeeStack,
  EventDetails,
  PostForm,
  PostStatus,
  RsvpButton,
} from "./forum-parts";
import { ErrorAlert } from "./parts";

export function ForumsPage({ forumId }: { forumId: string | null }) {
  const list = useForums();
  if (forumId) {
    const forum = list.forums.find((candidate) => candidate.id === forumId);
    if (forum)
      return <ForumFeedCard forumId={forum.id} name={forum.interestName} />;
    if (list.hasLoaded) return <MissingForum />;
  }
  return <ForumsHome list={list} />;
}

function ForumsHome({ list }: { list: ForumList }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Forums</CardTitle>
        <CardDescription>
          One for each of your interests. Members see who's going to each event.
        </CardDescription>
      </CardHeader>
      <CardPanel className="flex flex-col gap-3">
        <ErrorAlert message={list.activity.error} />
        {list.hasLoaded && list.forums.length === 0 ? (
          <p className="text-muted-foreground text-sm">
            Pick some interests to join their forums.
          </p>
        ) : (
          <Tabs defaultValue="upcoming">
            <TabsList>
              <TabsTab value="upcoming">Upcoming</TabsTab>
              <TabsTab value="forums">Your forums</TabsTab>
            </TabsList>
            <TabsPanel value="upcoming">
              <UpcomingPosts forums={list.forums} />
            </TabsPanel>
            <TabsPanel value="forums">
              <ForumLinks forums={list.forums} />
            </TabsPanel>
          </Tabs>
        )}
      </CardPanel>
    </Card>
  );
}

function UpcomingPosts({ forums }: { forums: Forum[] }) {
  const upcoming = useUpcomingPosts();
  const forumNames = new Map(
    forums.map((forum) => [forum.id, forum.interestName]),
  );
  return (
    <div className="flex flex-col gap-3 pt-2">
      <ErrorAlert
        message={upcoming.activity.error ?? upcoming.rsvpActivity.error}
      />
      {upcoming.hasLoaded && upcoming.posts.length === 0 ? (
        <p className="text-muted-foreground text-sm">
          No upcoming events in your forums.
        </p>
      ) : (
        <ul className="flex flex-col gap-3">
          {upcoming.posts.map((post) => (
            <li key={post.id}>
              <PostSummary
                post={post}
                list={upcoming}
                forumName={forumNames.get(post.forumId)}
              />
            </li>
          ))}
        </ul>
      )}
      {upcoming.hasMore && (
        <Button
          variant="outline"
          loading={upcoming.activity.busy}
          onClick={upcoming.loadMore}
        >
          Load more events
        </Button>
      )}
    </div>
  );
}

function ForumLinks({ forums }: { forums: Forum[] }) {
  return (
    <ul className="-mx-2 flex flex-col pt-2">
      {forums.map((forum) => (
        <li key={forum.id}>
          <a
            href={hrefFor({ page: "forums", forumId: forum.id })}
            className="flex items-center gap-3 rounded-lg px-2 py-2.5 text-sm hover:bg-accent focus-visible:outline-2 focus-visible:outline-ring"
          >
            <span className="flex-1 font-medium capitalize">
              {forum.interestName}
            </span>
            {forum.upcomingPostCount > 0 && (
              <Badge
                size="sm"
                variant="outline"
                aria-label={`${forum.upcomingPostCount} upcoming`}
              >
                {forum.upcomingPostCount}
              </Badge>
            )}
            <CaretRightIcon className="shrink-0 text-muted-foreground" />
          </a>
        </li>
      ))}
    </ul>
  );
}

function ForumFeedCard({ forumId, name }: { forumId: string; name: string }) {
  const feed = useForumFeed(forumId);
  const [composing, setComposing] = useState(false);
  return (
    <Card>
      <CardHeader>
        <a
          href={hrefFor({ page: "forums", forumId: null })}
          className="flex w-fit items-center gap-1 text-muted-foreground text-sm hover:text-foreground"
        >
          <CaretLeftIcon />
          Forums
        </a>
        <CardTitle className="capitalize">{name}</CardTitle>
        <CardAction>
          {!composing && (
            <Button size="sm" onClick={() => setComposing(true)}>
              <PlusIcon />
              New event
            </Button>
          )}
        </CardAction>
      </CardHeader>
      <CardPanel className="flex flex-col gap-4">
        <ErrorAlert message={feed.activity.error ?? feed.rsvpActivity.error} />
        {composing && (
          <div className="rounded-lg border p-4">
            <PostForm
              post={null}
              busy={feed.activity.busy}
              submitLabel="Post event"
              onSubmit={async (input) => {
                const created = await feed.create(input);
                if (created) setComposing(false);
                return created;
              }}
              onCancel={() => setComposing(false)}
            />
          </div>
        )}
        {feed.hasLoaded && feed.posts.length === 0 ? (
          <p className="text-muted-foreground text-sm">
            No events yet. Post the first one.
          </p>
        ) : (
          <ul className="flex flex-col gap-3">
            {feed.posts.map((post) => (
              <li key={post.id}>
                <PostSummary post={post} list={feed} />
              </li>
            ))}
          </ul>
        )}
        {feed.hasMore && (
          <Button
            variant="outline"
            loading={feed.activity.busy}
            onClick={feed.loadMore}
          >
            Load older events
          </Button>
        )}
      </CardPanel>
    </Card>
  );
}

function PostSummary({
  post,
  list,
  forumName,
}: {
  post: Post;
  list: PostList;
  forumName?: string;
}) {
  return (
    <article className="flex flex-col gap-3 rounded-lg border p-4">
      <header className="flex items-start justify-between gap-2">
        <a
          href={hrefFor({ page: "post", postId: post.id })}
          className="font-medium hover:underline focus-visible:outline-2 focus-visible:outline-ring"
        >
          {post.title}
        </a>
        <PostStatus post={post} />
      </header>
      <EventDetails post={post} />
      <p className="text-muted-foreground text-xs">
        {forumName && <span className="capitalize">{forumName} · </span>}
        <Avatar
          avatar={post.author.avatar}
          className="mr-1 size-4 align-text-bottom"
        />
        Posted by {post.isAuthor ? "you" : post.author.name}
      </p>
      <footer className="flex items-center justify-between gap-2">
        <AttendeeStack post={post} />
        <RsvpButton
          post={post}
          busy={list.rsvpActivity.busy}
          onRsvp={(attending) => list.rsvp(post, attending)}
        />
      </footer>
    </article>
  );
}

function MissingForum() {
  return (
    <Card>
      <CardPanel className="flex flex-col items-start gap-3 text-sm">
        <p>This forum is not available. Add its interest to join it.</p>
        <a
          className="font-medium underline underline-offset-4"
          href={hrefFor({ page: "forums", forumId: null })}
        >
          Back to forums
        </a>
      </CardPanel>
    </Card>
  );
}
