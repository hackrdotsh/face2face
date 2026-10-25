import {
  BellIcon,
  CalendarDotsIcon,
  ChatCircleIcon,
  type Icon,
  SparkleIcon,
  UserCircleIcon,
  UsersThreeIcon,
} from "@phosphor-icons/react";
import { cn } from "@/lib/utils";
import { hrefFor, navRoute, type PageName } from "@/navigation/routes";

const navItems: { page: PageName; label: string; icon: Icon }[] = [
  { page: "passed", label: "Passed", icon: UsersThreeIcon },
  { page: "chats", label: "Chats", icon: ChatCircleIcon },
  { page: "forums", label: "Forums", icon: CalendarDotsIcon },
  { page: "notifications", label: "Alerts", icon: BellIcon },
  { page: "interests", label: "Interests", icon: SparkleIcon },
  { page: "account", label: "Account", icon: UserCircleIcon },
];

export function AppNav({
  current,
  counts,
}: {
  current: PageName;
  counts: Partial<Record<PageName, number>>;
}) {
  return (
    <nav aria-label="Pages" className="rounded-xl border bg-card p-1">
      <ul className="grid grid-cols-6 gap-1">
        {navItems.map(({ page, label, icon: ItemIcon }) => {
          const isCurrent = page === current;
          const count = counts[page] ?? 0;
          return (
            <li key={page}>
              <a
                href={hrefFor(navRoute(page))}
                aria-current={isCurrent ? "page" : undefined}
                className={cn(
                  "relative flex flex-col items-center gap-0.5 rounded-lg px-1 py-2 text-xs transition-colors focus-visible:outline-2 focus-visible:outline-ring",
                  isCurrent
                    ? "bg-accent font-medium text-foreground"
                    : "text-muted-foreground hover:bg-accent/50 hover:text-foreground",
                )}
              >
                <ItemIcon
                  className="size-5"
                  weight={isCurrent ? "fill" : "regular"}
                />
                {label}
                {count > 0 && (
                  <span className="absolute top-1 right-[calc(50%-1.25rem)] min-w-4 rounded-full bg-primary px-1 text-center text-[0.625rem] text-primary-foreground tabular-nums leading-4">
                    <span className="sr-only">, </span>
                    {count}
                    <span className="sr-only"> new</span>
                  </span>
                )}
              </a>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
