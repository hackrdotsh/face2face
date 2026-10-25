import {
  CalendarDotsIcon,
  FlaskIcon,
  UsersThreeIcon,
} from "@phosphor-icons/react";
import type { DevConnection } from "@/api/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Separator } from "@/components/ui/separator";
import { ErrorAlert, Notice } from "@/screens/parts";
import { useSession } from "@/session/session";
import { JSONView } from "./JSONView";
import { type Simulator, useSimulator } from "./use-simulator";

export function SimulatorPanel() {
  const simulator = useSimulator();
  const { busy } = simulator.activity;
  return (
    <div className="flex flex-col gap-4 text-sm">
      <p className="text-muted-foreground text-xs">
        Simulated encounters do not prove two people were near each other.
      </p>
      <ErrorAlert message={simulator.activity.error} />
      <Notice message={simulator.notice} />
      <div className="flex flex-wrap gap-2">
        <Button
          size="sm"
          variant="outline"
          disabled={busy}
          onClick={simulator.seed}
        >
          <UsersThreeIcon />
          Seed people
        </Button>
        <Button
          size="sm"
          variant="outline"
          disabled={busy}
          onClick={simulator.seedForumPosts}
        >
          <CalendarDotsIcon />
          Seed forum posts
        </Button>
        <Button
          size="sm"
          variant="ghost"
          disabled={busy}
          onClick={simulator.reload}
        >
          Refresh
        </Button>
        <Button
          size="sm"
          variant="destructive-outline"
          disabled={busy}
          onClick={simulator.resetConnections}
        >
          Delete connections and posts
        </Button>
      </div>
      <PeopleList simulator={simulator} />
      <Button
        disabled={busy || simulator.selectedIds.length !== 2}
        onClick={simulator.simulateEncounter}
      >
        <FlaskIcon />
        Simulate encounter
      </Button>
      <Separator />
      <ConnectionTable simulator={simulator} />
      {simulator.inbox && (
        <>
          <Separator />
          <h3 className="font-medium">
            {simulator.nameOf(simulator.inbox.userId)}'s inbox
          </h3>
          <JSONView value={simulator.inbox.notifications} />
        </>
      )}
    </div>
  );
}

function PeopleList({ simulator }: { simulator: Simulator }) {
  const session = useSession();
  const signedInId =
    "account" in session.phase ? session.phase.account.user.id : null;
  const { busy } = simulator.activity;
  if (simulator.users.length === 0) {
    return <p className="text-muted-foreground">No people yet. Seed some.</p>;
  }
  return (
    <div className="flex flex-col gap-1">
      <p className="text-muted-foreground text-xs">
        Pick two people who pass each other.
      </p>
      <ul className="flex flex-col divide-y rounded-lg border">
        {simulator.users.map((user) => (
          <li key={user.id} className="flex items-center gap-3 px-3 py-2">
            <Checkbox
              aria-label={`Select ${user.name || user.email}`}
              checked={simulator.selectedIds.includes(user.id)}
              onCheckedChange={() => simulator.toggleSelected(user.id)}
            />
            <div className="min-w-0 flex-1">
              <p className="flex items-center gap-2 font-medium">
                {user.name || user.email}
                {user.id === signedInId && <Badge variant="info">you</Badge>}
              </p>
              <p className="truncate text-muted-foreground text-xs">
                {user.interests.join(", ") || "no interests"}
              </p>
            </div>
            <Button
              size="xs"
              variant="ghost"
              disabled={busy}
              onClick={() => simulator.showInbox(user.id)}
            >
              Inbox
            </Button>
            {user.seeded && (
              <Button
                size="xs"
                variant="outline"
                disabled={busy || user.id === signedInId}
                onClick={() => simulator.signInAs(user)}
              >
                Sign in
              </Button>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}

function ConnectionTable({ simulator }: { simulator: Simulator }) {
  if (simulator.connections.length === 0) {
    return <p className="text-muted-foreground">No connections yet.</p>;
  }
  return (
    <div className="flex flex-col gap-2">
      <h3 className="font-medium">All connections</h3>
      <ul className="flex flex-col gap-2">
        {simulator.connections.map((connection) => (
          <ConnectionRow
            key={connection.id}
            connection={connection}
            simulator={simulator}
          />
        ))}
      </ul>
    </div>
  );
}

function ConnectionRow({
  connection,
  simulator,
}: {
  connection: DevConnection;
  simulator: Simulator;
}) {
  return (
    <li className="flex flex-col gap-1 rounded-lg border p-2 text-xs">
      <div className="flex items-center justify-between gap-2">
        <span className="font-medium text-sm">
          {simulator.nameOf(connection.userLowId)} ·{" "}
          {simulator.nameOf(connection.userHighId)}
        </span>
        <Badge variant="outline">{connection.status}</Badge>
      </div>
      <p className="text-muted-foreground">
        Shares: {connection.sharedInterests.join(", ") || "nothing"}
      </p>
      <p className="font-mono text-muted-foreground">
        low {sideSummary(connection.lowDecision, connection.lowPublicAt)} · high{" "}
        {sideSummary(connection.highDecision, connection.highPublicAt)}
        {connection.blockedBy && ` · blocked by ${connection.blockedBy}`}
      </p>
      {connection.status === "pending" && (
        <Button
          className="self-start"
          size="xs"
          variant="outline"
          disabled={simulator.activity.busy}
          onClick={() => simulator.expire(connection.id)}
        >
          Expire now
        </Button>
      )}
    </li>
  );
}

function sideSummary(decision: string | null, publicAt: string | null) {
  return `${decision ?? "undecided"}${publicAt ? ", public" : ""}`;
}
