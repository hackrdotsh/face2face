export const apiURL =
  process.env.EXPO_PUBLIC_API_URL ?? "http://localhost:8787";

export async function checkAPI(): Promise<void> {
  const response = await fetch(`${apiURL}/health`, {
    signal: AbortSignal.timeout(5000),
  });
  const body: unknown = await response.json();
  if (
    !response.ok ||
    typeof body !== "object" ||
    body === null ||
    !("status" in body) ||
    body.status !== "ok"
  ) {
    throw new Error("Unexpected health response");
  }
}
