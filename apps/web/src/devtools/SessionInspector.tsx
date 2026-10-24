import { useState } from "react";
import { Button } from "@/components/ui/button";
import { useSession } from "@/session/session";
import { JSONView } from "./JSONView";

export function SessionInspector() {
  const session = useSession();
  const [revealed, setRevealed] = useState(false);
  const token = session.client.token;
  return (
    <div className="flex flex-col gap-3 text-xs">
      <Row label="Server">{session.serverURL}</Row>
      <Row label="Phase">{session.phase.kind}</Row>
      <Row label="Bearer token">
        {token ? (
          <span className="flex items-center gap-2">
            <span className="break-all font-mono">
              {revealed ? token : `${token.slice(0, 8)}…`}
            </span>
            <Button
              size="xs"
              variant="ghost"
              onClick={() => setRevealed(!revealed)}
            >
              {revealed ? "Hide" : "Show"}
            </Button>
          </span>
        ) : (
          "none"
        )}
      </Row>
      {"account" in session.phase && <JSONView value={session.phase.account} />}
      <div className="flex gap-2">
        <Button size="sm" variant="outline" onClick={session.restore}>
          Recheck session
        </Button>
        <Button
          size="sm"
          variant="ghost"
          disabled={!token}
          onClick={() => {
            session.client.clearToken();
            void session.restore();
          }}
        >
          Forget token locally
        </Button>
      </div>
    </div>
  );
}

function Row({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="grid grid-cols-[7rem_1fr] gap-2">
      <span className="text-muted-foreground">{label}</span>
      <span>{children}</span>
    </div>
  );
}
