import { Button } from "@/components/ui/button";
import {
  Card,
  CardDescription,
  CardHeader,
  CardPanel,
  CardTitle,
} from "@/components/ui/card";
import { Spinner } from "@/components/ui/spinner";
import { useOnboarding } from "@/flows/use-onboarding";
import { emptyDraft } from "@/onboarding/form";
import { useSession } from "@/session/session";
import { OnboardingFieldInput } from "./OnboardingFieldInput";
import { ActionForm, ErrorAlert } from "./parts";

export function OnboardingScreen() {
  const flow = useOnboarding();
  const session = useSession();
  const { form, activity } = flow;
  return (
    <Card>
      <CardHeader>
        <CardTitle>Set up your profile</CardTitle>
        <CardDescription>
          The server decides which fields appear here.
        </CardDescription>
      </CardHeader>
      <CardPanel className="flex flex-col gap-4">
        <ErrorAlert message={activity.error} />
        {!form && activity.busy && <Spinner />}
        {!form && !activity.busy && (
          <Button variant="outline" onClick={flow.load}>
            Try again
          </Button>
        )}
        {form?.needsAppUpdate && (
          <ErrorAlert message="The server needs a field this version can't show. Update the web app." />
        )}
        {form && (
          <ActionForm onSubmit={flow.submit}>
            {form.fields.map((field) => (
              <OnboardingFieldInput
                key={field.key}
                field={field}
                draft={form.drafts[field.key] ?? emptyDraft()}
                error={flow.fieldErrors[field.key]}
                onChange={(change) => flow.edit(field.key, change)}
              />
            ))}
            <Button type="submit" loading={activity.busy}>
              Continue
            </Button>
          </ActionForm>
        )}
        <Button variant="ghost" onClick={session.signOut}>
          Sign out
        </Button>
      </CardPanel>
    </Card>
  );
}
