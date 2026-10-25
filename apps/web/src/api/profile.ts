import type { APIClient } from "./client";
import type { Avatar } from "./types";

/** Replaces the profile photo. The server strips metadata and makes square sizes. */
export async function uploadProfilePhoto(client: APIClient, photo: Blob) {
  const form = new FormData();
  form.append("image", photo, "photo.jpg");
  const { avatar } = await client.send<{ avatar: Avatar }>({
    path: "api/profile/photo",
    method: "PUT",
    body: form,
    authenticated: true,
  });
  return avatar;
}

export async function removeProfilePhoto(client: APIClient) {
  const { avatar } = await client.send<{ avatar: Avatar }>({
    path: "api/profile/photo",
    method: "DELETE",
    authenticated: true,
  });
  return avatar;
}
