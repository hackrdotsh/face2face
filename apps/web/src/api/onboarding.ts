import type { APIClient } from "./client";
import type { FieldValue, OnboardingState } from "./types";

export function onboardingState(client: APIClient) {
  return client.send<OnboardingState>({
    path: "api/onboarding",
    authenticated: true,
  });
}

export function updateOnboarding(
  client: APIClient,
  values: Record<string, FieldValue>,
) {
  return client.send<OnboardingState>({
    path: "api/onboarding",
    method: "PATCH",
    body: { values },
    authenticated: true,
  });
}
