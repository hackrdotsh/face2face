import { CaretRightIcon } from "@phosphor-icons/react";
import type { RequestRecord } from "@/api/client";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useSession } from "@/session/session";
import { JSONView } from "./JSONView";
import { useRequestRecords } from "./request-log";

export function RequestLogView() {
  const { requestLog } = useSession();
  const records = useRequestRecords(requestLog);
  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center justify-between">
        <p className="text-muted-foreground text-xs">
          {records.length} requests
        </p>
        <Button size="xs" variant="ghost" onClick={requestLog.clear}>
          Clear
        </Button>
      </div>
      {records.map((record) => (
        <RequestRow key={record.id} record={record} />
      ))}
    </div>
  );
}

function RequestRow({ record }: { record: RequestRecord }) {
  const path = new URL(record.url).pathname;
  return (
    <details className="group rounded-lg border p-2 text-xs">
      <summary className="flex cursor-pointer list-none items-center gap-2">
        <CaretRightIcon className="size-3 transition-transform group-open:rotate-90" />
        <StatusBadge record={record} />
        <span className="font-mono">{record.method}</span>
        <span className="flex-1 truncate font-mono">{path}</span>
        {record.authenticated && <Badge variant="outline">bearer</Badge>}
        {record.durationMs !== undefined && (
          <span className="text-muted-foreground">{record.durationMs} ms</span>
        )}
      </summary>
      <div className="mt-2 flex flex-col gap-2">
        <p className="break-all font-mono text-muted-foreground">
          {record.url}
        </p>
        {record.requestBody !== undefined && (
          <>
            <p className="font-medium">Request</p>
            <JSONView value={redact(record.requestBody)} />
          </>
        )}
        <p className="font-medium">Response</p>
        {record.failure ? (
          <p className="text-destructive-foreground">{record.failure}</p>
        ) : (
          <JSONView value={record.responseBody} />
        )}
      </div>
    </details>
  );
}

function StatusBadge({ record }: { record: RequestRecord }) {
  if (record.failure) return <Badge variant="error">failed</Badge>;
  if (record.status === undefined) return <Badge variant="outline">…</Badge>;
  const variant =
    record.status < 300 ? "success" : record.status < 500 ? "warning" : "error";
  return <Badge variant={variant}>{record.status}</Badge>;
}

/** Hides passwords in the log. Codes stay visible because they are what this tool tests. */
function redact(body: unknown): unknown {
  if (typeof body !== "object" || body === null || Array.isArray(body))
    return body;
  return Object.fromEntries(
    Object.entries(body).map(([key, value]) => [
      key,
      key === "password" ? "••••••" : value,
    ]),
  );
}
