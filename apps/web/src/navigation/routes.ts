export const pageNames = [
  "passed",
  "chats",
  "notifications",
  "interests",
  "account",
] as const;

export type PageName = (typeof pageNames)[number];

export type Route =
  | { page: "chats"; chatId: string | null }
  | { page: Exclude<PageName, "chats"> };

export const defaultRoute: Route = { page: "passed" };

/** Reads a hash such as `#/chats/<id>`. Anything unknown goes to the default page. */
export function parseRoute(hash: string): Route {
  const [page, id] = hash.replace(/^#\/?/, "").split("/");
  if (page === "chats") {
    return { page, chatId: id ? decodeURIComponent(id) : null };
  }
  if (isPageName(page)) return { page };
  return defaultRoute;
}

export function hrefFor(route: Route): string {
  if (route.page === "chats" && route.chatId) {
    return `#/chats/${encodeURIComponent(route.chatId)}`;
  }
  return `#/${route.page}`;
}

function isPageName(
  value: string | undefined,
): value is Exclude<PageName, "chats"> {
  return (pageNames as readonly (string | undefined)[]).includes(value);
}
