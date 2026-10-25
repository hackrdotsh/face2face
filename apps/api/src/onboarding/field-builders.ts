import { z } from "zod";
import type { ProfilePhoto } from "../profiles/person";
import type {
  ChoiceOption,
  ChoiceValue,
  FieldContext,
  FieldParseResult,
  OnboardingField,
} from "./field-types";
import type { ProfileChanges, ProfileSnapshot } from "./profile-store";

interface FieldBase<Value> {
  key: string;
  label: string;
  required: boolean;
  read(snapshot: ProfileSnapshot): Value | null;
  write(value: Value): ProfileChanges;
}

const choiceDescriptionMaxLength = 60;
const earliestBirthDate = "1900-01-01";

export function textField(
  field: FieldBase<string> & { maxLength: number; emptyMessage: string },
): OnboardingField {
  const schema = z
    .string(field.emptyMessage)
    .trim()
    .min(1, field.emptyMessage)
    .max(field.maxLength, `Use ${field.maxLength} characters or fewer.`);
  return {
    key: field.key,
    describe: ({ snapshot }) => ({
      key: field.key,
      type: "text",
      label: field.label,
      required: field.required,
      value: field.read(snapshot),
      constraints: { maxLength: field.maxLength },
    }),
    parse: (input) => toParseResult(schema.safeParse(input), field.write),
  };
}

export function birthDateField(
  field: FieldBase<string> & { minimumAgeYears: number },
): OnboardingField {
  const tooYoungMessage = `You must be ${field.minimumAgeYears} or older to use face2face.`;
  const latestDate = (today: string) =>
    subtractYears(today, field.minimumAgeYears);
  const schemaFor = (context: FieldContext) =>
    z.iso
      .date("Enter a date as YYYY-MM-DD.")
      .refine((date) => date >= earliestBirthDate, "Enter a real birth date.")
      .refine((date) => date <= latestDate(context.today), tooYoungMessage);
  return {
    key: field.key,
    describe: ({ snapshot, today }) => ({
      key: field.key,
      type: "date",
      label: field.label,
      required: field.required,
      value: field.read(snapshot),
      constraints: {
        earliestDate: earliestBirthDate,
        latestDate: latestDate(today),
      },
    }),
    parse: (input, context) =>
      toParseResult(schemaFor(context).safeParse(input), field.write),
  };
}

export function singleChoiceField(
  field: FieldBase<ChoiceValue> & {
    options(snapshot: ProfileSnapshot): ChoiceOption[];
    descriptionMessage: string;
  },
): OnboardingField {
  const schemaFor = ({ snapshot }: FieldContext) => {
    const options = new Map(
      field.options(snapshot).map((option) => [option.id, option]),
    );
    return z
      .object(
        {
          optionId: z.string("Choose an option."),
          description: z
            .string()
            .trim()
            .max(
              choiceDescriptionMaxLength,
              `Use ${choiceDescriptionMaxLength} characters or fewer.`,
            )
            .optional(),
        },
        "Choose an option.",
      )
      .refine((value) => options.has(value.optionId), "Choose an option.")
      .transform((value) => withDescriptionIfAllowed(value, options))
      .refine(
        (value) =>
          !options.get(value.optionId)?.allowsDescription || value.description,
        field.descriptionMessage,
      );
  };
  return {
    key: field.key,
    describe: ({ snapshot }) => ({
      key: field.key,
      type: "singleChoice",
      label: field.label,
      required: field.required,
      value: field.read(snapshot),
      options: field.options(snapshot),
    }),
    parse: (input, context) =>
      toParseResult(schemaFor(context).safeParse(input), field.write),
  };
}

function withDescriptionIfAllowed(
  value: ChoiceValue,
  options: Map<string, ChoiceOption>,
): ChoiceValue {
  const allowsDescription = options.get(value.optionId)?.allowsDescription;
  if (!allowsDescription || !value.description) {
    return { optionId: value.optionId };
  }
  return { optionId: value.optionId, description: value.description };
}

function toParseResult<Value>(
  result: z.ZodSafeParseResult<Value>,
  write: (value: Value) => ProfileChanges,
): FieldParseResult {
  if (result.success) return { ok: true, changes: write(result.data) };
  return {
    ok: false,
    message: result.error.issues[0]?.message ?? "Check this field.",
  };
}

function subtractYears(isoDate: string, years: number): string {
  const date = new Date(`${isoDate}T00:00:00Z`);
  date.setUTCFullYear(date.getUTCFullYear() - years);
  return date.toISOString().slice(0, 10);
}

/** Set by uploading to `/api/profile/photo`, never by an onboarding update. */
export function photoField(
  field: Omit<FieldBase<ProfilePhoto>, "write">,
): OnboardingField {
  return {
    key: field.key,
    describe: ({ snapshot }) => ({
      key: field.key,
      type: "image",
      label: field.label,
      required: field.required,
      value: field.read(snapshot),
    }),
    parse: () => ({ ok: false, message: "Upload the photo instead." }),
  };
}
