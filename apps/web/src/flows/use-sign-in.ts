import { useState } from "react";
import * as auth from "@/api/auth";
import { APIError } from "@/api/errors";
import { signInWithPasskey as passkeySignIn } from "@/api/passkeys";
import { useSession } from "@/session/session";
import { useActivity } from "./use-activity";

export type SignInMethod = "emailCode" | "password" | "createAccount";
export type SignInStep =
  | { kind: "details" }
  | { kind: "code"; purpose: auth.EmailCodePurpose };

/** Sign-in, sign-up, verification, and password reset state for the signed-out screen. */
export function useSignIn() {
  const session = useSession();
  const { client } = session;
  const activity = useActivity();
  const [method, setMethod] = useState<SignInMethod>("emailCode");
  const [step, setStep] = useState<SignInStep>({ kind: "details" });
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [code, setCode] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [notice, setNotice] = useState<string | null>(null);

  const showCodeEntry = (purpose: auth.EmailCodePurpose, message?: string) => {
    setCode("");
    setNotice(message ?? `Enter the 6-digit code we sent to ${email}.`);
    setStep({ kind: "code", purpose });
  };

  const clearSecrets = () => {
    setPassword("");
    setNewPassword("");
    setCode("");
  };

  const finishSignIn = async () => {
    clearSecrets();
    setNotice(null);
    setStep({ kind: "details" });
    await session.refreshAccount();
  };

  const submitDetails = () =>
    activity.run(async () => {
      switch (method) {
        case "emailCode":
          await auth.sendSignInCode(client, email);
          showCodeEntry("sign-in");
          return;
        case "password":
          try {
            await auth.signInWithPassword(client, email, password);
          } catch (error) {
            if (
              error instanceof APIError &&
              error.kind === "emailNotVerified"
            ) {
              showCodeEntry(
                "email-verification",
                `Verify your email first. We sent a code to ${email}.`,
              );
              return;
            }
            throw error;
          }
          await finishSignIn();
          return;
        case "createAccount":
          await auth.createAccount(client, email, password);
          showCodeEntry("email-verification");
          return;
      }
    });

  const submitCode = () =>
    activity.run(async () => {
      if (step.kind !== "code") return;
      switch (step.purpose) {
        case "sign-in":
          await auth.signInWithCode(client, email, code);
          break;
        case "email-verification":
          await auth.verifyEmail(client, email, code);
          break;
        case "forget-password":
          await auth.resetPassword(client, email, code, newPassword);
          clearSecrets();
          setMethod("password");
          setStep({ kind: "details" });
          setNotice("Password updated. Sign in with your new password.");
          return;
      }
      await finishSignIn();
    });

  const resendCode = () =>
    activity.run(async () => {
      if (step.kind !== "code") return;
      switch (step.purpose) {
        case "sign-in":
          await auth.sendSignInCode(client, email);
          break;
        case "email-verification":
          await auth.resendVerificationCode(client, email);
          break;
        case "forget-password":
          await auth.requestPasswordReset(client, email);
          break;
      }
      setNotice(`We sent a new code to ${email}.`);
    });

  const forgotPassword = () =>
    activity.run(async () => {
      await auth.requestPasswordReset(client, email);
      showCodeEntry("forget-password");
    });

  const signInWithPasskey = () =>
    activity.run(async () => {
      await passkeySignIn(client);
      await finishSignIn();
    });

  const backToDetails = () => {
    setStep({ kind: "details" });
    setCode("");
    setNotice(null);
    activity.clearError();
  };

  const chooseMethod = (next: SignInMethod) => {
    setMethod(next);
    setNotice(null);
    activity.clearError();
  };

  return {
    method,
    step,
    email,
    password,
    code,
    newPassword,
    notice,
    activity,
    setEmail,
    setPassword,
    setCode,
    setNewPassword,
    chooseMethod,
    submitDetails,
    submitCode,
    resendCode,
    forgotPassword,
    signInWithPasskey,
    backToDetails,
  };
}

export type SignInFlow = ReturnType<typeof useSignIn>;
