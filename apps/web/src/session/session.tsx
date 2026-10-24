import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { currentAccount } from "@/api/account";
import { signOut as endSession } from "@/api/auth";
import { APIClient } from "@/api/client";
import { APIError } from "@/api/errors";
import type { Account } from "@/api/types";
import { loadServerURL, saveServerURL } from "@/config/server";
import { RequestLog } from "@/devtools/request-log";
import { type Activity, useActivity } from "@/flows/use-activity";
import { browserTokenStore } from "./token-store";

export type SessionPhase =
  | { kind: "checking" }
  | { kind: "signedOut" }
  | { kind: "needsOnboarding"; account: Account }
  | { kind: "ready"; account: Account }
  /** The saved session could not be checked, for example because the API is down. */
  | { kind: "unreachable"; message: string };

export interface Session {
  phase: SessionPhase;
  client: APIClient;
  requestLog: RequestLog;
  serverURL: string;
  activity: Activity;
  changeServer: (url: string) => void;
  /** Checks the saved session again. */
  restore: () => Promise<void>;
  /** Reloads the signed-in account, for example after signing in or finishing onboarding. */
  refreshAccount: () => Promise<void>;
  signOut: () => Promise<void>;
}

const SessionContext = createContext<Session | null>(null);

export function phaseFor(account: Account): SessionPhase {
  return account.onboardingComplete
    ? { kind: "ready", account }
    : { kind: "needsOnboarding", account };
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const [serverURL, setServerURL] = useState(loadServerURL);
  const [phase, setPhase] = useState<SessionPhase>({ kind: "checking" });
  const activity = useActivity();
  const serverRef = useRef(serverURL);
  serverRef.current = serverURL;

  const requestLog = useMemo(() => new RequestLog(), []);
  const client = useMemo(
    () =>
      new APIClient({
        serverURL: () => serverRef.current,
        tokens: browserTokenStore(() => serverRef.current),
        onRecord: requestLog.record,
      }),
    [requestLog],
  );

  const refreshAccount = useCallback(async () => {
    if (!client.token) {
      setPhase({ kind: "signedOut" });
      return;
    }
    try {
      setPhase(phaseFor(await currentAccount(client)));
    } catch (error) {
      if (error instanceof APIError && error.kind === "unauthenticated") {
        client.clearToken();
        setPhase({ kind: "signedOut" });
        return;
      }
      throw error;
    }
  }, [client]);

  const restore = useCallback(async () => {
    setPhase({ kind: "checking" });
    try {
      await refreshAccount();
    } catch (error) {
      setPhase({
        kind: "unreachable",
        message: error instanceof Error ? error.message : String(error),
      });
    }
  }, [refreshAccount]);

  // A server change starts a fresh session check against the new server.
  useEffect(() => {
    void restore();
  }, [restore, serverURL]);

  const changeServer = useCallback((url: string) => {
    saveServerURL(url);
    setServerURL(url);
  }, []);

  const signOut = useCallback(async () => {
    await activity.run(async () => {
      try {
        await endSession(client);
      } catch (error) {
        if (!(error instanceof APIError && error.kind === "unauthenticated"))
          throw error;
      }
      setPhase({ kind: "signedOut" });
    });
  }, [activity.run, client]);

  const value = useMemo<Session>(
    () => ({
      phase,
      client,
      requestLog,
      serverURL,
      activity,
      changeServer,
      restore,
      refreshAccount,
      signOut,
    }),
    [
      phase,
      client,
      requestLog,
      serverURL,
      activity,
      changeServer,
      restore,
      refreshAccount,
      signOut,
    ],
  );

  return (
    <SessionContext.Provider value={value}>{children}</SessionContext.Provider>
  );
}

export function useSession(): Session {
  const session = useContext(SessionContext);
  if (!session)
    throw new Error("useSession must be used inside SessionProvider");
  return session;
}
