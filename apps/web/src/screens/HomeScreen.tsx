import type { Account } from "@/api/types";
import { useChats } from "@/flows/use-chats";
import { useConnections } from "@/flows/use-connections";
import { useNotifications } from "@/flows/use-notifications";
import { useHashRoute } from "@/navigation/use-hash-route";
import { AccountPage } from "./AccountPage";
import { AppNav } from "./AppNav";
import { ChatsPage } from "./ChatsPage";
import { InterestsPage } from "./InterestsPage";
import { NotificationsPage } from "./NotificationsPage";
import { PassedPage, pendingChances } from "./PassedPage";

/**
 * The signed-in app. The notification socket and the lists behind the nav
 * counts live here, so they stay open while the person moves between pages.
 */
export function HomeScreen({ account }: { account: Account }) {
  const { route, navigate } = useHashRoute();
  const feed = useNotifications();
  const connections = useConnections(feed.notifications[0]?.id);
  const chats = useChats(feed);
  const unansweredCount = pendingChances(connections.connections).filter(
    (connection) => connection.you.decision === null,
  ).length;

  return (
    <div className="flex flex-col gap-4">
      <AppNav
        current={route.page}
        counts={{ passed: unansweredCount, chats: chats.unreadCount }}
      />
      {route.page === "passed" && <PassedPage list={connections} />}
      {route.page === "chats" && (
        <ChatsPage
          chatId={route.chatId}
          chats={chats}
          connections={connections}
          feed={feed}
          navigate={navigate}
        />
      )}
      {route.page === "notifications" && <NotificationsPage feed={feed} />}
      {route.page === "interests" && <InterestsPage />}
      {route.page === "account" && <AccountPage account={account} />}
    </div>
  );
}
