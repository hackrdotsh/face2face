import { removeProfilePhoto, uploadProfilePhoto } from "@/api/profile";
import { type CropArea, cropToSquare } from "@/lib/crop-image";
import { useSession } from "@/session/session";
import { useActivity } from "./use-activity";

/** Changes the signed-in person's photo, then reloads the account to show it. */
export function useProfilePhoto() {
  const { client, refreshAccount } = useSession();
  const activity = useActivity();

  /** Crops the circle's square out of the picked image and uploads it. */
  const upload = (imageURL: string, area: CropArea) =>
    activity.run(async () => {
      await uploadProfilePhoto(client, await cropToSquare(imageURL, area));
      await refreshAccount();
    });

  const remove = () =>
    activity.run(async () => {
      await removeProfilePhoto(client);
      await refreshAccount();
    });

  return { activity, upload, remove };
}
