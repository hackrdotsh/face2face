import { Button } from "@/components/ui/button";
import { Spinner } from "@/components/ui/spinner";
import { useSession } from "@/session/session";
import { HomeScreen } from "./HomeScreen";
import { OnboardingScreen } from "./OnboardingScreen";
import { ErrorAlert } from "./parts";
import { SignInScreen } from "./SignInScreen";

/** Picks the screen for the current session phase. */
export function RootScreen() {
  const session = useSession();
  const { phase } = session;
  switch (phase.kind) {
    case "checking":
      return <Spinner />;
    case "unreachable":
      return (
        <div className="flex flex-col gap-4">
          <ErrorAlert message={phase.message} />
          <Button variant="outline" onClick={session.restore}>
            Try again
          </Button>
        </div>
      );
    case "signedOut":
      return <SignInScreen />;
    case "needsOnboarding":
      return <OnboardingScreen account={phase.account} />;
    case "ready":
      return <HomeScreen account={phase.account} />;
  }
}
