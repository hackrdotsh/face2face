import { useCallback, useEffect, useState } from "react";
import { listInterestChoices, replaceInterests } from "@/api/interests";
import type { InterestChoices } from "@/api/types";
import { useSession } from "@/session/session";
import { useActivity } from "./use-activity";

/** The person's saved interests and an unsaved selection to edit. */
export function useInterests() {
  const { client } = useSession();
  const activity = useActivity();
  const [saved, setSaved] = useState<InterestChoices | null>(null);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);

  const show = useCallback((choices: InterestChoices) => {
    setSaved(choices);
    setSelectedIds(
      choices.interests
        .filter((choice) => choice.selected)
        .map((choice) => choice.id),
    );
  }, []);

  const reload = useCallback(
    () =>
      activity.run(async () => {
        show(await listInterestChoices(client));
      }),
    [activity.run, client, show],
  );

  useEffect(() => {
    void reload();
  }, [reload]);

  const maxSelected = saved?.maxSelected ?? 0;
  const savedIds =
    saved?.interests
      .filter((choice) => choice.selected)
      .map((choice) => choice.id) ?? [];
  const hasChanges =
    savedIds.length !== selectedIds.length ||
    savedIds.some((id) => !selectedIds.includes(id));

  const toggle = (interestId: string) =>
    setSelectedIds((current) => {
      if (current.includes(interestId)) {
        return current.filter((id) => id !== interestId);
      }
      if (current.length >= maxSelected) return current;
      return [...current, interestId];
    });

  const save = () =>
    activity.run(async () => {
      show(await replaceInterests(client, selectedIds));
    });

  return {
    interests: saved?.interests ?? [],
    selectedIds,
    maxSelected,
    hasChanges,
    activity,
    toggle,
    save,
  };
}
