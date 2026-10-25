import {
  birthDateField,
  interestsField,
  photoField,
  singleChoiceField,
  textField,
} from "./field-builders";
import type { OnboardingField } from "./field-types";

export const onboardingFields: OnboardingField[] = [
  textField({
    key: "name",
    label: "Name",
    required: true,
    maxLength: 80,
    emptyMessage: "Enter your name.",
    read: (snapshot) => snapshot.name || null,
    write: (name) => ({ user: { name } }),
  }),
  birthDateField({
    key: "birthDate",
    label: "Date of birth",
    required: true,
    minimumAgeYears: 18,
    read: (snapshot) => snapshot.birthDate,
    write: (birthDate) => ({ profile: { birthDate } }),
  }),
  singleChoiceField({
    key: "gender",
    label: "Gender",
    required: true,
    descriptionMessage: "Describe your gender.",
    options: (snapshot) => snapshot.genderOptions,
    read: (snapshot) => {
      if (!snapshot.genderId) return null;
      if (!snapshot.genderDescription) return { optionId: snapshot.genderId };
      return {
        optionId: snapshot.genderId,
        description: snapshot.genderDescription,
      };
    },
    write: (gender) => ({
      profile: {
        genderId: gender.optionId,
        genderDescription: gender.description ?? null,
      },
    }),
  }),
  interestsField({
    key: "interests",
    label: "Interests",
    required: false,
    read: (snapshot) =>
      snapshot.interestIds.length > 0 ? snapshot.interestIds : null,
  }),
  photoField({
    key: "photo",
    label: "Profile photo",
    required: false,
    read: (snapshot) => snapshot.photo,
  }),
];
