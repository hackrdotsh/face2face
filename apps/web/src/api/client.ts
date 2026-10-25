import { APIError } from "./errors";

export type HTTPMethod = "GET" | "POST" | "PATCH" | "PUT" | "DELETE";

export interface APIRequest {
  path: string;
  method?: HTTPMethod;
  query?: Record<string, string>;
  /** Sent as JSON, except `FormData`, which is sent as multipart. */
  body?: unknown;
  /** Sends the saved bearer token. */
  authenticated?: boolean;
  /**
   * Lets the browser send and store cookies for this request. Only passkey
   * ceremonies need this, because the server keeps the WebAuthn challenge in a
   * signed cookie between the options and verify requests.
   */
  withCookies?: boolean;
}

export interface APIResponse {
  status: number;
  ok: boolean;
  headers: Headers;
  body: unknown;
}

export interface RequestRecord {
  id: number;
  method: HTTPMethod;
  url: string;
  requestBody?: unknown;
  authenticated: boolean;
  startedAt: number;
  durationMs?: number;
  status?: number;
  responseBody?: unknown;
  /** Set when the request never got an HTTP response. */
  failure?: string;
}

export interface TokenStore {
  get(): string | null;
  set(token: string | null): void;
}

export interface APIClientOptions {
  serverURL: () => string;
  tokens: TokenStore;
  /** Called when a request starts and again when it finishes, with the same id. */
  onRecord?: (record: RequestRecord) => void;
  fetch?: typeof fetch;
}

let nextRecordId = 1;

export class APIClient {
  constructor(private readonly options: APIClientOptions) {}

  get token(): string | null {
    return this.options.tokens.get();
  }

  clearToken(): void {
    this.options.tokens.set(null);
  }

  /** Sends a request and throws `APIError` for any non-2xx response. */
  async send<T = unknown>(request: APIRequest): Promise<T> {
    const response = await this.exchange(request);
    if (!response.ok) throw APIError.from(response.status, response.body);
    return response.body as T;
  }

  /** Sends a request and returns the response whatever its status. */
  async exchange(request: APIRequest): Promise<APIResponse> {
    const method =
      request.method ?? (request.body === undefined ? "GET" : "POST");
    const url = this.url(request);
    const headers = new Headers({ Accept: "application/json" });
    const isForm = request.body instanceof FormData;
    if (request.body !== undefined && !isForm)
      headers.set("Content-Type", "application/json");
    const token = this.token;
    const authenticated = Boolean(request.authenticated && token);
    if (authenticated) headers.set("Authorization", `Bearer ${token}`);

    const record: RequestRecord = {
      id: nextRecordId++,
      method,
      url,
      requestBody: request.body,
      authenticated,
      startedAt: Date.now(),
    };
    this.options.onRecord?.({ ...record });

    let response: Response;
    try {
      response = await (this.options.fetch ?? fetch)(url, {
        method,
        headers,
        body: encodeBody(request.body),
        credentials: request.withCookies ? "include" : "omit",
      });
    } catch (error) {
      this.options.onRecord?.({
        ...record,
        durationMs: Date.now() - record.startedAt,
        failure: error instanceof Error ? error.message : String(error),
      });
      throw new APIError("network", 0);
    }

    const body = await readBody(response);
    const sessionToken = response.headers.get("set-auth-token");
    if (response.ok && sessionToken) this.options.tokens.set(sessionToken);
    this.options.onRecord?.({
      ...record,
      durationMs: Date.now() - record.startedAt,
      status: response.status,
      responseBody: body,
    });
    return {
      status: response.status,
      ok: response.ok,
      headers: response.headers,
      body,
    };
  }

  private url(request: APIRequest): string {
    const url = new URL(
      request.path.replace(/^\//, ""),
      `${this.options.serverURL()}/`,
    );
    for (const [name, value] of Object.entries(request.query ?? {})) {
      url.searchParams.set(name, value);
    }
    return url.toString();
  }
}

function encodeBody(body: unknown): BodyInit | undefined {
  if (body === undefined) return undefined;
  if (body instanceof FormData) return body;
  return JSON.stringify(body);
}

async function readBody(response: Response): Promise<unknown> {
  const text = await response.text();
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}
