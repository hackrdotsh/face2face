import type { APIClient } from "./client";
import type { Account, CoordinatorStatus } from "./types";

export function currentAccount(client: APIClient) {
  return client.send<Account>({ path: "api/me", authenticated: true });
}

export function coordinatorStatus(client: APIClient) {
  return client.send<CoordinatorStatus>({
    path: "api/coordinator",
    authenticated: true,
  });
}
