import type { EmailMessage } from "./send-email";

export type OTPPurpose =
  | "sign-in"
  | "email-verification"
  | "forget-password"
  | "change-email";

const subjects: Record<OTPPurpose, string> = {
  "sign-in": "Your face2face sign-in code",
  "email-verification": "Verify your face2face email",
  "forget-password": "Reset your face2face password",
  "change-email": "Confirm your new face2face email",
};

export function createOTPEmail(
  to: string,
  otp: string,
  purpose: OTPPurpose,
  expiresInMinutes: number,
): EmailMessage {
  return {
    to,
    subject: subjects[purpose],
    text: `Your code is ${otp}. It expires in ${expiresInMinutes} minutes. If you didn't request it, you can ignore this email.`,
  };
}
