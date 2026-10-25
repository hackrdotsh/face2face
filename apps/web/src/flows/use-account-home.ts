import { useCallback, useEffect, useState } from "react";
import { coordinatorStatus } from "@/api/account";
import { deletePasskey, listPasskeys, registerPasskey } from "@/api/passkeys";
import type { CoordinatorStatus, Passkey } from "@/api/types";
import { useSession } from "@/session/session";
import { useActivity } from "./use-activity";

/** The signed-in home: coordinator status and passkey management. */
export function useAccountHome() {
  const { client } = useSession();
  const activity = useActivity();
  const [passkeys, setPasskeys] = useState<Passkey[]>([]);
  const [coordinator, setCoordinator] = useState<CoordinatorStatus | null>(
    null,
  );
  const [passkeyName, setPasskeyName] = useState("This browser");

  const reload = useCallback(
    () =>
      activity.run(async () => {
        const [keys, status] = await Promise.all([
          listPasskeys(client),
          coordinatorStatus(client),
        ]);
        setPasskeys(keys);
        setCoordinator(status);
      }),
    [activity.run, client],
  );

  useEffect(() => {
    void reload();
  }, [reload]);

  const addPasskey = () =>
    activity.run(async () => {
      await registerPasskey(client, passkeyName.trim() || "This browser");
      setPasskeys(await listPasskeys(client));
    });

  const removePasskey = (id: string) =>
    activity.run(async () => {
      await deletePasskey(client, id);
      setPasskeys(await listPasskeys(client));
    });

  return {
    passkeys,
    coordinator,
    passkeyName,
    setPasskeyName,
    activity,
    reload,
    addPasskey,
    removePasskey,
  };
}

export type AccountHome = ReturnType<typeof useAccountHome>;
