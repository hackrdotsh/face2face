import { useCallback, useEffect, useState } from "react";
import { listForums } from "@/api/forums";
import type { Forum } from "@/api/types";
import { useSession } from "@/session/session";
import { useActivity } from "./use-activity";

/** The forums of the person's interests. */
export function useForums() {
  const { client } = useSession();
  const activity = useActivity();
  const [forums, setForums] = useState<Forum[]>([]);
  const [hasLoaded, setHasLoaded] = useState(false);

  const reload = useCallback(
    () =>
      activity.run(async () => {
        setForums(await listForums(client));
        setHasLoaded(true);
      }),
    [activity.run, client],
  );

  useEffect(() => {
    void reload();
  }, [reload]);

  return { forums, hasLoaded, activity, reload };
}

export type ForumList = ReturnType<typeof useForums>;
