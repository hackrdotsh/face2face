import type { HTTPMethod } from "@/api/client";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { ErrorAlert } from "@/screens/parts";
import { JSONView } from "./JSONView";
import { rawMethods, useRawRequest } from "./use-raw-request";

export function RawConsole() {
  const raw = useRawRequest();
  return (
    <form
      className="flex flex-col gap-3 text-xs"
      onSubmit={(event) => {
        event.preventDefault();
        void raw.send();
      }}
    >
      <div className="flex gap-2">
        <select
          aria-label="Method"
          className="rounded-lg border bg-background px-2 font-mono"
          value={raw.method}
          onChange={(event) => raw.setMethod(event.target.value as HTTPMethod)}
        >
          {rawMethods.map((method) => (
            <option key={method}>{method}</option>
          ))}
        </select>
        <Input
          aria-label="Path"
          className="font-mono"
          value={raw.path}
          onChange={(event) => raw.setPath(event.target.value)}
        />
      </div>
      <Textarea
        aria-label="JSON body"
        className="font-mono"
        placeholder='{"values": {}}'
        value={raw.body}
        onChange={(event) => raw.setBody(event.target.value)}
      />
      <div className="flex gap-4">
        <Label className="flex items-center gap-2">
          <Checkbox
            checked={raw.authenticated}
            onCheckedChange={raw.setAuthenticated}
          />
          Send bearer token
        </Label>
        <Label className="flex items-center gap-2">
          <Checkbox
            checked={raw.withCookies}
            onCheckedChange={raw.setWithCookies}
          />
          Include cookies
        </Label>
      </div>
      <Button type="submit" size="sm" loading={raw.activity.busy}>
        Send
      </Button>
      <ErrorAlert message={raw.activity.error} />
      {raw.response && (
        <>
          <p className="font-medium">HTTP {raw.response.status}</p>
          <JSONView value={raw.response.body} />
        </>
      )}
    </form>
  );
}
