import { FingerprintIcon } from "@phosphor-icons/react";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardDescription,
  CardHeader,
  CardPanel,
  CardTitle,
} from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { Tabs, TabsList, TabsTab } from "@/components/ui/tabs";
import {
  type SignInFlow,
  type SignInMethod,
  useSignIn,
} from "@/flows/use-sign-in";
import { ActionForm, ErrorAlert, Notice, TextField } from "./parts";

const methods: { value: SignInMethod; label: string }[] = [
  { value: "emailCode", label: "Email code" },
  { value: "password", label: "Password" },
  { value: "createAccount", label: "Create account" },
];

const codeTitles = {
  "sign-in": "Enter your sign-in code",
  "email-verification": "Verify your email",
  "forget-password": "Reset your password",
};

export function SignInScreen() {
  const flow = useSignIn();
  return (
    <Card>
      <CardHeader>
        <CardTitle>
          {flow.step.kind === "code"
            ? codeTitles[flow.step.purpose]
            : "Sign in to face2face"}
        </CardTitle>
        <CardDescription>
          Development servers write codes to the API log instead of sending
          email.
        </CardDescription>
      </CardHeader>
      <CardPanel className="flex flex-col gap-4">
        <Notice message={flow.notice} />
        <ErrorAlert message={flow.activity.error} />
        {flow.step.kind === "code" ? (
          <CodeStep flow={flow} />
        ) : (
          <DetailsStep flow={flow} />
        )}
      </CardPanel>
    </Card>
  );
}

function DetailsStep({ flow }: { flow: SignInFlow }) {
  const { busy } = flow.activity;
  const usesPassword = flow.method !== "emailCode";
  return (
    <>
      <Tabs
        value={flow.method}
        onValueChange={(value) => flow.chooseMethod(value as SignInMethod)}
      >
        <TabsList>
          {methods.map((method) => (
            <TabsTab key={method.value} value={method.value}>
              {method.label}
            </TabsTab>
          ))}
        </TabsList>
      </Tabs>
      <ActionForm onSubmit={flow.submitDetails}>
        <TextField
          label="Email"
          type="email"
          autoComplete="email"
          required
          value={flow.email}
          onValueChange={flow.setEmail}
        />
        {usesPassword && (
          <TextField
            label="Password"
            type="password"
            autoComplete={
              flow.method === "createAccount"
                ? "new-password"
                : "current-password"
            }
            hint={
              flow.method === "createAccount"
                ? "At least 12 characters."
                : undefined
            }
            required
            value={flow.password}
            onValueChange={flow.setPassword}
          />
        )}
        <Button type="submit" loading={busy}>
          {flow.method === "emailCode"
            ? "Send code"
            : flow.method === "password"
              ? "Sign in"
              : "Create account"}
        </Button>
        {flow.method === "password" && (
          <Button
            variant="link"
            disabled={busy || !flow.email}
            onClick={flow.forgotPassword}
          >
            Forgot password?
          </Button>
        )}
      </ActionForm>
      <Separator />
      <Button
        variant="outline"
        disabled={busy}
        onClick={flow.signInWithPasskey}
      >
        <FingerprintIcon />
        Sign in with a passkey
      </Button>
    </>
  );
}

function CodeStep({ flow }: { flow: SignInFlow }) {
  const { busy } = flow.activity;
  const resetting =
    flow.step.kind === "code" && flow.step.purpose === "forget-password";
  return (
    <ActionForm onSubmit={flow.submitCode}>
      <TextField
        label="6-digit code"
        inputMode="numeric"
        autoComplete="one-time-code"
        maxLength={6}
        required
        value={flow.code}
        onValueChange={flow.setCode}
      />
      {resetting && (
        <TextField
          label="New password"
          type="password"
          autoComplete="new-password"
          hint="At least 12 characters."
          required
          value={flow.newPassword}
          onValueChange={flow.setNewPassword}
        />
      )}
      <Button type="submit" loading={busy}>
        {resetting ? "Reset password" : "Continue"}
      </Button>
      <div className="flex gap-2">
        <Button variant="ghost" disabled={busy} onClick={flow.resendCode}>
          Send a new code
        </Button>
        <Button variant="ghost" disabled={busy} onClick={flow.backToDetails}>
          Back
        </Button>
      </div>
    </ActionForm>
  );
}
