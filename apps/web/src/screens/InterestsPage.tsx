import { CheckIcon } from "@phosphor-icons/react";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardDescription,
  CardHeader,
  CardPanel,
  CardTitle,
} from "@/components/ui/card";
import { useInterests } from "@/flows/use-interests";
import { ErrorAlert } from "./parts";

export function InterestsPage() {
  const picker = useInterests();
  const { busy } = picker.activity;
  const atLimit = picker.selectedIds.length >= picker.maxSelected;
  return (
    <Card>
      <CardHeader>
        <CardTitle>Your interests</CardTitle>
        <CardDescription>
          People you pass see the ones you share. Pick up to{" "}
          {picker.maxSelected}.
        </CardDescription>
      </CardHeader>
      <CardPanel className="flex flex-col gap-4">
        <ErrorAlert message={picker.activity.error} />
        <ul className="flex flex-wrap gap-2">
          {picker.interests.map((interest) => {
            const selected = picker.selectedIds.includes(interest.id);
            return (
              <li key={interest.id}>
                <Button
                  size="sm"
                  variant={selected ? "default" : "outline"}
                  aria-pressed={selected}
                  disabled={busy || (!selected && atLimit)}
                  onClick={() => picker.toggle(interest.id)}
                >
                  {selected && <CheckIcon />}
                  {interest.name}
                  <span className="text-xs tabular-nums opacity-64">
                    {interest.memberCount}
                  </span>
                </Button>
              </li>
            );
          })}
        </ul>
        <div className="flex items-center justify-between gap-2">
          <p className="text-muted-foreground text-sm tabular-nums">
            {picker.selectedIds.length} of {picker.maxSelected} picked
          </p>
          <Button
            loading={busy}
            disabled={!picker.hasChanges}
            onClick={picker.save}
          >
            Save interests
          </Button>
        </div>
      </CardPanel>
    </Card>
  );
}
