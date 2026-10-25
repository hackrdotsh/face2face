import { FingerprintIcon, TrashIcon } from "@phosphor-icons/react";
import type { Account } from "@/api/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardDescription,
  CardHeader,
  CardPanel,
  CardTitle,
} from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { useAccountHome } from "@/flows/use-account-home";
import { useSession } from "@/session/session";
import { ProfilePhotoEditor } from "./ProfilePhotoEditor";
import { ActionForm, ErrorAlert, TextField } from "./parts";

export function AccountPage({ account }: { account: Account }) {
  const home = useAccountHome();
  const session = useSession();
  const { busy } = home.activity;
  return (
    <Card>
      <CardHeader>
        <CardTitle>Hi, {account.user.name}</CardTitle>
        <CardDescription>{account.user.email}</CardDescription>
      </CardHeader>
      <CardPanel className="flex flex-col gap-4">
        <ErrorAlert message={home.activity.error} />
        <ProfilePhotoEditor
          avatar={account.user.avatar}
          label="Profile photo"
        />
        <Separator />
        <div className="flex items-center gap-2 text-sm">
          Coordinator
          {home.coordinator ? (
            <Badge variant={home.coordinator.ready ? "success" : "warning"}>
              {home.coordinator.ready ? "ready" : "not ready"} ·{" "}
              {home.coordinator.storage}
            </Badge>
          ) : (
            <Badge variant="outline">unknown</Badge>
          )}
        </div>
        <Separator />
        <h3 className="font-medium text-sm">Passkeys</h3>
        {home.passkeys.length === 0 && (
          <p className="text-muted-foreground text-sm">
            No passkeys yet. Adding one is optional.
          </p>
        )}
        <ul className="flex flex-col gap-2">
          {home.passkeys.map((passkey) => (
            <li
              key={passkey.id}
              className="flex items-center justify-between gap-2 text-sm"
            >
              <span>
                {passkey.name || "Unnamed passkey"}{" "}
                <span className="text-muted-foreground">
                  {passkey.deviceType}
                  {passkey.backedUp ? ", synced" : ""}
                </span>
              </span>
              <Button
                size="icon-sm"
                variant="ghost"
                aria-label={`Delete ${passkey.name || "passkey"}`}
                disabled={busy}
                onClick={() => home.removePasskey(passkey.id)}
              >
                <TrashIcon />
              </Button>
            </li>
          ))}
        </ul>
        <ActionForm onSubmit={home.addPasskey}>
          <TextField
            label="Passkey name"
            value={home.passkeyName}
            onValueChange={home.setPasskeyName}
          />
          <Button type="submit" variant="outline" loading={busy}>
            <FingerprintIcon />
            Add a passkey
          </Button>
        </ActionForm>
        <Separator />
        <div className="flex gap-2">
          <Button variant="outline" disabled={busy} onClick={home.reload}>
            Refresh
          </Button>
          <Button
            variant="destructive-outline"
            loading={session.activity.busy}
            onClick={session.signOut}
          >
            Sign out
          </Button>
        </div>
      </CardPanel>
    </Card>
  );
}
