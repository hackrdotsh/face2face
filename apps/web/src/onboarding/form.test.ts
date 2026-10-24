import { describe, expect, it } from "vitest";
import type { OnboardingState } from "@/api/types";
import { createForm, formValues, updateDraft } from "./form";

const state: OnboardingState = {
  complete: false,
  fields: [
    { key: "name", type: "text", label: "Name", required: true, value: null },
    {
      key: "birthDate",
      type: "date",
      label: "Birth date",
      required: true,
      value: null,
    },
    {
      key: "gender",
      type: "singleChoice",
      label: "Gender",
      required: true,
      value: null,
      options: [
        { id: "female", label: "Female", allowsDescription: false },
        { id: "other", label: "Other", allowsDescription: true },
      ],
    },
    { key: "done", type: "text", label: "Done", required: true, value: "kept" },
  ],
};

describe("onboarding form", () => {
  it("only asks for unanswered fields", () => {
    expect(createForm(state).fields.map((field) => field.key)).toEqual([
      "name",
      "birthDate",
      "gender",
    ]);
  });

  it("leaves empty fields out and trims text", () => {
    let form = createForm(state);
    form = updateDraft(form, "name", { text: "  Riley " });
    expect(formValues(form)).toEqual({ name: "Riley" });
  });

  it("keeps a description only for options that allow one", () => {
    let form = createForm(state);
    form = updateDraft(form, "birthDate", { text: "1999-07-04" });
    form = updateDraft(form, "gender", {
      optionId: "female",
      description: "ignored",
    });
    expect(formValues(form).gender).toEqual({ optionId: "female" });
    form = updateDraft(form, "gender", {
      optionId: "other",
      description: " Nonbinary ",
    });
    expect(formValues(form)).toEqual({
      birthDate: "1999-07-04",
      gender: { optionId: "other", description: "Nonbinary" },
    });
  });

  it("flags a required field type this build cannot render", () => {
    const form = createForm({
      complete: false,
      fields: [
        {
          key: "photo",
          type: "image",
          label: "Photo",
          required: true,
          value: null,
        },
      ],
    });
    expect(form.fields).toEqual([]);
    expect(form.needsAppUpdate).toBe(true);
  });
});
