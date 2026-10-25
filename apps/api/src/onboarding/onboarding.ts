import type { Database } from "../db/client";
import type { PhotoViewer } from "../profiles/person";
import type {
  FieldContext,
  FieldDescription,
  OnboardingField,
} from "./field-types";
import {
  loadProfileSnapshot,
  mergeProfileChanges,
  type ProfileChanges,
  saveProfileChanges,
} from "./profile-store";

export interface OnboardingState {
  complete: boolean;
  fields: FieldDescription[];
}

export type OnboardingUpdateResult =
  | { ok: true; state: OnboardingState }
  | { ok: false; fieldErrors: Record<string, string> };

export function describeOnboarding(
  fields: OnboardingField[],
  context: FieldContext,
): OnboardingState {
  const descriptions = fields.map((field) => field.describe(context));
  const complete = descriptions.every(
    (description) => !description.required || description.value !== null,
  );
  return { complete, fields: descriptions };
}

export function parseOnboardingValues(
  fields: OnboardingField[],
  values: Record<string, unknown>,
  context: FieldContext,
):
  | { ok: true; changes: ProfileChanges }
  | { ok: false; fieldErrors: Record<string, string> } {
  const fieldsByKey = new Map(fields.map((field) => [field.key, field]));
  const fieldErrors: Record<string, string> = {};
  const changeSets: ProfileChanges[] = [];
  for (const [key, input] of Object.entries(values)) {
    const field = fieldsByKey.get(key);
    if (!field) {
      fieldErrors[key] = "This field is not part of onboarding.";
      continue;
    }
    const result = field.parse(input, context);
    if (result.ok) changeSets.push(result.changes);
    else fieldErrors[key] = result.message;
  }
  if (Object.keys(fieldErrors).length > 0) return { ok: false, fieldErrors };
  return { ok: true, changes: mergeProfileChanges(changeSets) };
}

export async function getOnboardingState(
  db: Database,
  viewPhoto: PhotoViewer,
  fields: OnboardingField[],
  userId: string,
  now: Date,
): Promise<OnboardingState> {
  const snapshot = await loadProfileSnapshot(db, viewPhoto, userId);
  return describeOnboarding(fields, { snapshot, today: isoDate(now) });
}

export async function updateOnboarding(
  db: Database,
  viewPhoto: PhotoViewer,
  fields: OnboardingField[],
  userId: string,
  values: Record<string, unknown>,
  now: Date,
): Promise<OnboardingUpdateResult> {
  const snapshot = await loadProfileSnapshot(db, viewPhoto, userId);
  const parsed = parseOnboardingValues(fields, values, {
    snapshot,
    today: isoDate(now),
  });
  if (!parsed.ok) return parsed;
  await saveProfileChanges(db, userId, parsed.changes, now);
  return {
    ok: true,
    state: await getOnboardingState(db, viewPhoto, fields, userId, now),
  };
}

function isoDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}
