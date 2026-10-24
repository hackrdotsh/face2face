import type {
  ChoiceOption,
  FieldValue,
  OnboardingField,
  OnboardingState,
} from "@/api/types";

/** Editable input for one onboarding field. Only the slots matching the field's type are used. */
export interface FieldDraft {
  /** Text, or a `YYYY-MM-DD` date. */
  text: string;
  optionId: string | null;
  description: string;
}

/** The fields a person still has to answer, their drafts, and the values to send to the server. */
export interface OnboardingForm {
  fields: OnboardingField[];
  drafts: Record<string, FieldDraft>;
  /** True when the server requires a field this build cannot render. */
  needsAppUpdate: boolean;
}

const supportedTypes = new Set(["text", "date", "singleChoice"]);

export function isSupported(field: OnboardingField): boolean {
  return supportedTypes.has(field.type);
}

export function emptyDraft(): FieldDraft {
  return { text: "", optionId: null, description: "" };
}

export function createForm(state: OnboardingState): OnboardingForm {
  const unanswered = state.fields.filter((field) => field.value === null);
  const fields = unanswered.filter(isSupported);
  return {
    fields,
    drafts: Object.fromEntries(
      fields.map((field) => [field.key, emptyDraft()]),
    ),
    needsAppUpdate: unanswered.some(
      (field) => field.required && !isSupported(field),
    ),
  };
}

export function updateDraft(
  form: OnboardingForm,
  key: string,
  change: Partial<FieldDraft>,
): OnboardingForm {
  const draft = form.drafts[key] ?? emptyDraft();
  return {
    ...form,
    drafts: { ...form.drafts, [key]: { ...draft, ...change } },
  };
}

export function selectedOption(
  field: OnboardingField,
  draft: FieldDraft | undefined,
): ChoiceOption | undefined {
  if (!draft?.optionId) return undefined;
  return field.options?.find((option) => option.id === draft.optionId);
}

/** Values for every field with input. Empty fields are left out so the server reports them as missing. */
export function formValues(form: OnboardingForm): Record<string, FieldValue> {
  const values: Record<string, FieldValue> = {};
  for (const field of form.fields) {
    const value = draftValue(field, form.drafts[field.key]);
    if (value !== undefined) values[field.key] = value;
  }
  return values;
}

function draftValue(
  field: OnboardingField,
  draft: FieldDraft | undefined,
): FieldValue | undefined {
  if (!draft) return undefined;
  switch (field.type) {
    case "text":
    case "date": {
      const text = draft.text.trim();
      return text || undefined;
    }
    case "singleChoice": {
      const option = selectedOption(field, draft);
      if (!option) return undefined;
      const description = draft.description.trim();
      return option.allowsDescription && description
        ? { optionId: option.id, description }
        : { optionId: option.id };
    }
    default:
      return undefined;
  }
}
