import type { APIClient } from "./client";
import type { InterestChoices } from "./types";

export function listInterestChoices(client: APIClient) {
  return client.send<InterestChoices>({
    path: "api/interests",
    authenticated: true,
  });
}

export function replaceInterests(client: APIClient, interestIds: string[]) {
  return client.send<InterestChoices>({
    path: "api/interests",
    method: "PUT",
    body: { interestIds },
    authenticated: true,
  });
}
