export type APIErrorKind =
  | "unauthenticated"
  | "invalidCredentials"
  | "emailNotVerified"
  | "invalidCode"
  | "onboardingRequired"
  | "invalidFields"
  | "rateLimited"
  | "notFound"
  | "conflict"
  | "network"
  | "server";

const messages: Record<APIErrorKind, string> = {
  unauthenticated: "Sign in to continue.",
  invalidCredentials: "Check your email and password, then try again.",
  emailNotVerified: "Verify your email to continue. We sent you a new code.",
  invalidCode: "That code is wrong or expired. Check it or request a new one.",
  onboardingRequired: "Finish setting up your profile to continue.",
  invalidFields: "Check the highlighted fields, then try again.",
  rateLimited: "Too many attempts. Wait a minute and try again.",
  notFound: "That no longer exists. Refresh and try again.",
  conflict:
    "That changed since you last looked. Refresh to see where it stands.",
  network: "Could not reach the API. Check the server URL.",
  server: "The API returned an error. Try again.",
};

export class APIError extends Error {
  constructor(
    readonly kind: APIErrorKind,
    readonly status: number,
    readonly fields: Record<string, string> = {},
  ) {
    super(
      kind === "server" && status === 400
        ? "Check what you entered, then try again."
        : kind === "server"
          ? `The API returned HTTP ${status}. Try again.`
          : messages[kind],
    );
    this.name = "APIError";
  }

  /** Maps Better Auth error codes and face2face error bodies to the kinds the app handles. */
  static from(status: number, body: unknown): APIError {
    const decoded = isRecord(body) ? body : {};
    const code = stringValue(decoded.error) ?? stringValue(decoded.code);
    if (status === 400 && code === "invalid_fields") {
      return new APIError("invalidFields", status, fieldErrors(decoded.fields));
    }
    if (
      (status === 400 && (code === "INVALID_OTP" || code === "OTP_EXPIRED")) ||
      (status === 403 && code === "TOO_MANY_ATTEMPTS")
    ) {
      return new APIError("invalidCode", status);
    }
    if (status === 401 && code === "INVALID_EMAIL_OR_PASSWORD") {
      return new APIError("invalidCredentials", status);
    }
    if (status === 401) return new APIError("unauthenticated", status);
    if (status === 403 && code === "EMAIL_NOT_VERIFIED") {
      return new APIError("emailNotVerified", status);
    }
    if (status === 403 && code === "onboarding_required") {
      return new APIError("onboardingRequired", status);
    }
    if (status === 404) return new APIError("notFound", status);
    if (status === 409) return new APIError("conflict", status);
    if (status === 429) return new APIError("rateLimited", status);
    return new APIError("server", status);
  }
}

export function errorMessage(error: unknown): string {
  if (error instanceof APIError) return error.message;
  if (error instanceof DOMException && error.name === "NotAllowedError") {
    return "The passkey request was cancelled or timed out.";
  }
  if (error instanceof Error) return error.message;
  return "Something went wrong. Try again.";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function fieldErrors(value: unknown): Record<string, string> {
  if (!isRecord(value)) return {};
  return Object.fromEntries(
    Object.entries(value).filter(
      (entry): entry is [string, string] => typeof entry[1] === "string",
    ),
  );
}
