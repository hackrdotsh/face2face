import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { defaultServerURL, normalizeServerURL } from "@/config/server";
import { useSession } from "@/session/session";

/** Chooses which API server the app talks to. Each server keeps its own session. */
export function ServerBar() {
  const session = useSession();
  const [draft, setDraft] = useState(session.serverURL);
  const [invalid, setInvalid] = useState(false);

  const apply = (input: string) => {
    const url = normalizeServerURL(input);
    setInvalid(!url);
    if (!url) return;
    setDraft(url);
    session.changeServer(url);
  };

  return (
    <form
      className="flex flex-wrap items-center gap-2"
      onSubmit={(event) => {
        event.preventDefault();
        apply(draft);
      }}
    >
      <Input
        aria-label="API server URL"
        aria-invalid={invalid}
        className="w-72 font-mono"
        size="sm"
        value={draft}
        onChange={(event) => setDraft(event.target.value)}
      />
      <Button type="submit" size="sm" variant="outline">
        Connect
      </Button>
      {session.serverURL !== defaultServerURL && (
        <Button
          size="sm"
          variant="ghost"
          onClick={() => apply(defaultServerURL)}
        >
          Use default
        </Button>
      )}
      {invalid && (
        <span className="text-destructive-foreground text-xs">
          Enter an http(s) URL with no path.
        </span>
      )}
    </form>
  );
}
