import type { Avatar, OnboardingField } from "@/api/types";
import { Field, FieldLabel } from "@/components/ui/field";
import { Label } from "@/components/ui/label";
import { Radio, RadioGroup } from "@/components/ui/radio-group";
import { type FieldDraft, selectedOption } from "@/onboarding/form";
import { ProfilePhotoEditor } from "./ProfilePhotoEditor";
import { TextField } from "./parts";

/** Renders one server-described onboarding field. Add a case here when the server adds a field type. */
export function OnboardingFieldInput({
  field,
  draft,
  error,
  avatar,
  onChange,
}: {
  field: OnboardingField;
  draft: FieldDraft;
  error?: string;
  /** The signed-in person's avatar, for `image` fields. */
  avatar: Avatar;
  onChange: (change: Partial<FieldDraft>) => void;
}) {
  switch (field.type) {
    case "text":
      return (
        <TextField
          label={field.label}
          error={error}
          required={field.required}
          maxLength={field.constraints?.maxLength}
          value={draft.text}
          onValueChange={(text) => onChange({ text })}
        />
      );
    case "date":
      return (
        <TextField
          label={field.label}
          error={error}
          type="date"
          required={field.required}
          min={field.constraints?.earliestDate}
          max={field.constraints?.latestDate}
          value={draft.text}
          onValueChange={(text) => onChange({ text })}
        />
      );
    case "singleChoice": {
      const option = selectedOption(field, draft);
      return (
        <Field className="w-full" invalid={Boolean(error)}>
          <FieldLabel>{field.label}</FieldLabel>
          <RadioGroup
            value={draft.optionId ?? ""}
            onValueChange={(optionId) =>
              onChange({ optionId: String(optionId) })
            }
          >
            {field.options?.map((choice) => (
              <Label key={choice.id} className="flex items-center gap-2">
                <Radio value={choice.id} />
                {choice.label}
              </Label>
            ))}
          </RadioGroup>
          {option?.allowsDescription && (
            <TextField
              label="Describe (optional)"
              value={draft.description}
              onValueChange={(description) => onChange({ description })}
            />
          )}
          {error && (
            <p className="text-destructive-foreground text-xs">{error}</p>
          )}
        </Field>
      );
    }
    case "image":
      return <ProfilePhotoEditor avatar={avatar} label={field.label} />;
    default:
      return null;
  }
}
