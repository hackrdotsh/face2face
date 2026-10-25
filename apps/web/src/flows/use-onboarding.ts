import { useCallback, useEffect, useState } from "react";
import { APIError } from "@/api/errors";
import { onboardingState, updateOnboarding } from "@/api/onboarding";
import {
  createForm,
  type FieldDraft,
  formValues,
  type OnboardingForm,
  updateDraft,
} from "@/onboarding/form";
import { useSession } from "@/session/session";
import { useActivity } from "./use-activity";

/** Loads the server's onboarding fields, holds the drafts, and submits them. */
export function useOnboarding() {
  const session = useSession();
  const { client } = session;
  const activity = useActivity();
  const [form, setForm] = useState<OnboardingForm | null>(null);
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});

  const load = useCallback(
    () =>
      activity.run(async () => {
        setForm(createForm(await onboardingState(client)));
      }),
    [activity.run, client],
  );

  useEffect(() => {
    void load();
  }, [load]);

  const edit = (key: string, change: Partial<FieldDraft>) => {
    setForm((current) => current && updateDraft(current, key, change));
    setFieldErrors(({ [key]: _, ...rest }) => rest);
  };

  const submit = () =>
    activity.run(async () => {
      if (!form) return;
      try {
        const state = await updateOnboarding(client, formValues(form));
        setFieldErrors({});
        if (state.complete) {
          await session.refreshAccount();
          return;
        }
        setForm(createForm(state));
      } catch (error) {
        if (error instanceof APIError && error.kind === "invalidFields") {
          setFieldErrors(error.fields);
        }
        throw error;
      }
    });

  return { form, fieldErrors, activity, load, edit, submit };
}

export type OnboardingFlow = ReturnType<typeof useOnboarding>;
