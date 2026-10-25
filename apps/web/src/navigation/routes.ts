export const pageNames = [
  "passed",
  "chats",
  "forums",
  "notifications",
  "interests",
  "account",
] as const;

export type PageName = (typeof pageNames)[number];

type SimplePage = Exclude<PageName, "chats" | "forums">;

export type Route =
  | { page: "chats"; chatId: string | null }
  | { page: "forums"; forumId: string | null }
  | { page: "post"; postId: string }
  | { page: SimplePage };

export const defaultRoute: Route = { page: "passed" };

/**
 * Reads a hash such as `#/chats/<id>`, `#/forums/<id>`, or `#/posts/<id>`.
 * Anything unknown goes to the default page.
 */
export function parseRoute(hash: string): Route {
  const [page, rawId] = hash.replace(/^#\/?/, "").split("/");
  const id = rawId ? decodeURIComponent(rawId) : null;
  if (page === "chats") return { page, chatId: id };
  if (page === "forums") return { page, forumId: id };
  if (page === "posts" && id) return { page: "post", postId: id };
  if (isSimplePage(page)) return { page };
  return defaultRoute;
}

export function hrefFor(route: Route): string {
  switch (route.page) {
    case "chats":
      return route.chatId
        ? `#/chats/${encodeURIComponent(route.chatId)}`
        : "#/chats";
    case "forums":
      return route.forumId
        ? `#/forums/${encodeURIComponent(route.forumId)}`
        : "#/forums";
    case "post":
      return `#/posts/${encodeURIComponent(route.postId)}`;
    default:
      return `#/${route.page}`;
  }
}

/** The nav entry a route belongs to. */
export function navPageOf(route: Route): PageName {
  return route.page === "post" ? "forums" : route.page;
}

export function navRoute(page: PageName): Route {
  if (page === "chats") return { page, chatId: null };
  if (page === "forums") return { page, forumId: null };
  return { page };
}

function isSimplePage(value: string | undefined): value is SimplePage {
  return (
    value !== "chats" &&
    value !== "forums" &&
    (pageNames as readonly (string | undefined)[]).includes(value)
  );
}
