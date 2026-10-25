import type { ProfilePhoto } from "../profiles/person";
import type { ProfileChanges, ProfileSnapshot } from "./profile-store";

export interface ChoiceOption {
  id: string;
  label: string;
  allowsDescription: boolean;
}

export interface ChoiceValue {
  optionId: string;
  description?: string;
}

export interface FieldConstraints {
  maxLength?: number;
  earliestDate?: string;
  latestDate?: string;
}

export interface FieldDescription {
  key: string;
  type: "text" | "date" | "singleChoice" | "image" | "interests";
  label: string;
  required: boolean;
  value: string | string[] | ChoiceValue | ProfilePhoto | null;
  constraints?: FieldConstraints;
  options?: ChoiceOption[];
}

export interface FieldContext {
  snapshot: ProfileSnapshot;
  today: string;
}

export type FieldParseResult =
  | { ok: true; changes: ProfileChanges }
  | { ok: false; message: string };

export interface OnboardingField {
  key: string;
  describe(context: FieldContext): FieldDescription;
  parse(input: unknown, context: FieldContext): FieldParseResult;
}
