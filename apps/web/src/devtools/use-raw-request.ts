import { useState } from "react";
import type { APIResponse, HTTPMethod } from "@/api/client";
import { useActivity } from "@/flows/use-activity";
import { useSession } from "@/session/session";

export const rawMethods: HTTPMethod[] = [
  "GET",
  "POST",
  "PATCH",
  "PUT",
  "DELETE",
];

/** Sends any request to the API with the current session attached. */
export function useRawRequest() {
  const { client } = useSession();
  const activity = useActivity();
  const [method, setMethod] = useState<HTTPMethod>("GET");
  const [path, setPath] = useState("/api/me");
  const [body, setBody] = useState("");
  const [authenticated, setAuthenticated] = useState(true);
  const [withCookies, setWithCookies] = useState(false);
  const [response, setResponse] = useState<APIResponse | null>(null);

  const send = () =>
    activity.run(async () => {
      const trimmed = body.trim();
      let parsed: unknown;
      if (trimmed) {
        try {
          parsed = JSON.parse(trimmed);
        } catch {
          throw new Error("The body must be valid JSON.");
        }
      }
      setResponse(
        await client.exchange({
          path,
          method,
          body: parsed,
          authenticated,
          withCookies,
        }),
      );
    });

  return {
    method,
    path,
    body,
    authenticated,
    withCookies,
    response,
    activity,
    setMethod,
    setPath,
    setBody,
    setAuthenticated,
    setWithCookies,
    send,
  };
}
