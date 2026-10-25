import { InfoIcon, WarningCircleIcon } from "@phosphor-icons/react";
import type { ComponentProps, FormEvent, ReactNode } from "react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Field, FieldDescription, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import type { SocketState } from "@/flows/use-socket";

export function ErrorAlert({ message }: { message: string | null }) {
  if (!message) return null;
  return (
    <Alert variant="error">
      <WarningCircleIcon />
      <AlertDescription>{message}</AlertDescription>
    </Alert>
  );
}

export function Notice({
  message,
  children,
}: {
  message: string | null;
  children?: ReactNode;
}) {
  if (!message) return null;
  return (
    <Alert variant="info">
      <InfoIcon />
      <AlertDescription>
        {message} {children}
      </AlertDescription>
    </Alert>
  );
}

export function TextField({
  label,
  error,
  hint,
  onValueChange,
  ...input
}: {
  label: string;
  error?: string;
  hint?: ReactNode;
  onValueChange: (value: string) => void;
} & Omit<ComponentProps<typeof Input>, "onChange">) {
  return (
    <Field className="w-full" invalid={Boolean(error)}>
      <FieldLabel>{label}</FieldLabel>
      <Input
        {...input}
        onChange={(event) => onValueChange(event.target.value)}
      />
      {hint && <FieldDescription>{hint}</FieldDescription>}
      {error && <p className="text-destructive-foreground text-xs">{error}</p>}
    </Field>
  );
}

/**
 * A form that runs `onSubmit` without reloading the page. Browser validation is
 * off so every submission reaches the API, which owns validation.
 */
export function ActionForm({
  onSubmit,
  children,
}: {
  onSubmit: () => void;
  children: ReactNode;
}) {
  const submit = (event: FormEvent) => {
    event.preventDefault();
    onSubmit();
  };
  return (
    <form className="flex flex-col gap-4" noValidate onSubmit={submit}>
      {children}
    </form>
  );
}

const socketBadges: Record<
  SocketState,
  { label: string; variant: "success" | "warning" | "outline" | "error" }
> = {
  live: { label: "live", variant: "success" },
  connecting: { label: "connecting", variant: "outline" },
  offline: { label: "offline", variant: "warning" },
  closed: { label: "closed", variant: "error" },
};

export function SocketBadge({ state }: { state: SocketState }) {
  const badge = socketBadges[state];
  return <Badge variant={badge.variant}>{badge.label}</Badge>;
}
