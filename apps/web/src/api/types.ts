export interface User {
  id: string;
  name: string;
  email: string;
}

export interface Account {
  user: User;
  onboardingComplete: boolean;
}

export interface ChoiceOption {
  id: string;
  label: string;
  allowsDescription: boolean;
}

export interface ChoiceValue {
  optionId: string;
  description?: string;
}

export type FieldValue = string | ChoiceValue;

export interface FieldConstraints {
  maxLength?: number;
  earliestDate?: string;
  latestDate?: string;
}

/** `type` stays open so a field type added on the server reaches the UI as unsupported instead of failing. */
export interface OnboardingField {
  key: string;
  type: "text" | "date" | "singleChoice" | (string & {});
  label: string;
  required: boolean;
  value: FieldValue | null;
  constraints?: FieldConstraints;
  options?: ChoiceOption[];
}

export interface OnboardingState {
  complete: boolean;
  fields: OnboardingField[];
}

export interface Passkey {
  id: string;
  name?: string | null;
  deviceType: string;
  backedUp: boolean;
  createdAt: string;
}

export interface CoordinatorStatus {
  ready: boolean;
  storage: string;
}
