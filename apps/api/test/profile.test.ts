import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { photoWithExif } from "./fixtures/photo-with-exif";
import {
  bearerHeaders,
  callAPI,
  postJSON,
  requireAuthToken,
  signInWithEmailCode,
} from "./helpers";

const ava = "seed-ava";
const ben = "seed-ben";

type Headers = Record<string, string>;

interface Avatar {
  seed: string;
  photo: { large: string; thumb: string } | null;
}

beforeEach(async () => {
  await env.DB.prepare("DELETE FROM rate_limit").run();
  await postJSON("/api/dev/reset", {});
  await postJSON("/api/dev/seed", {});
});

async function signInAs(userId: string): Promise<Headers> {
  const response = await postJSON("/api/auth/sign-in/email", {
    email: `${userId.replace("seed-", "")}@seed.face2face.test`,
    password: "face2face-seed-password",
  });
  return bearerHeaders(requireAuthToken(response));
}

function uploadPhoto(headers: Headers, bytes: Uint8Array<ArrayBuffer>) {
  const form = new FormData();
  form.append("image", new File([bytes], "photo.jpg", { type: "image/jpeg" }));
  return callAPI("/api/profile/photo", {
    method: "PUT",
    headers,
    body: form,
  });
}

async function uploadedAvatar(headers: Headers): Promise<Avatar> {
  const response = await uploadPhoto(headers, photoWithExif);
  expect(response.status).toBe(200);
  return (await response.json<{ avatar: Avatar }>()).avatar;
}

async function readAvatar(headers: Headers): Promise<Avatar> {
  const response = await callAPI("/api/me", { headers });
  return (await response.json<{ user: { avatar: Avatar } }>()).user.avatar;
}

function storedKey(path: string): string {
  return new URL(path, "http://localhost").pathname.replace("/media/", "");
}

describe("profile photos", () => {
  it("crops to stripped WebP squares", async () => {
    const { photo } = await uploadedAvatar(await signInAs(ava));
    const expectedEdges = { large: 1024, thumb: 256 };
    for (const [variant, edge] of Object.entries(expectedEdges)) {
      const path = photo?.[variant as keyof typeof expectedEdges] ?? "";
      const served = await callAPI(path);
      expect(served.status).toBe(200);
      expect(served.headers.get("Content-Type")).toBe("image/webp");
      const bytes = await served.arrayBuffer();
      const info = await env.IMAGES.info(new Blob([bytes]).stream());
      expect(info).toMatchObject({ width: edge, height: edge });
      const text = new TextDecoder("latin1").decode(bytes);
      expect(text).not.toContain("Exif");
      expect(text).not.toContain("f2f-exif-marker");
    }
  });

  it("gives each person a stable seed that does not contain their ID", async () => {
    const avaHeaders = await signInAs(ava);
    const first = await readAvatar(avaHeaders);
    expect(first).toEqual({ seed: expect.any(String), photo: null });
    expect(first.seed).toMatch(/^[A-Za-z0-9_-]{22}$/);
    expect(first.seed).not.toContain(ava);
    expect((await readAvatar(avaHeaders)).seed).toBe(first.seed);
    expect((await readAvatar(await signInAs(ben))).seed).not.toBe(first.seed);
  });

  it("deletes the old files when the photo is replaced or removed", async () => {
    const headers = await signInAs(ava);
    const first = await uploadedAvatar(headers);
    const second = await uploadedAvatar(headers);
    expect(await env.MEDIA.get(storedKey(first.photo?.large ?? ""))).toBeNull();
    expect((await readAvatar(headers)).photo).toEqual(second.photo);

    const removed = await callAPI("/api/profile/photo", {
      method: "DELETE",
      headers,
    });
    expect((await removed.json<{ avatar: Avatar }>()).avatar.photo).toBeNull();
    expect(
      await env.MEDIA.get(storedKey(second.photo?.thumb ?? "")),
    ).toBeNull();
  });

  it("rejects a file that is not an image", async () => {
    const response = await uploadPhoto(
      await signInAs(ava),
      new TextEncoder().encode("<svg onload=alert(1)>"),
    );
    expect(response.status).toBe(415);
  });

  it("refuses a path signed for another variant", async () => {
    const { photo } = await uploadedAvatar(await signInAs(ava));
    const forged = (photo?.thumb ?? "").replace("/thumb?", "/large?");
    expect((await callAPI(forged)).status).toBe(403);
  });

  it("is an optional onboarding step set only by upload", async () => {
    const headers = bearerHeaders(
      await signInWithEmailCode("photo@example.test"),
    );
    const photoField = async () => {
      const response = await callAPI("/api/onboarding", { headers });
      const state = await response.json<{
        fields: {
          key: string;
          type: string;
          required: boolean;
          value: unknown;
        }[];
      }>();
      return state.fields.find((field) => field.key === "photo");
    };
    expect(await photoField()).toMatchObject({
      type: "image",
      required: false,
      value: null,
    });

    const { photo } = await uploadedAvatar(headers);
    expect((await photoField())?.value).toEqual(photo);

    const patched = await callAPI("/api/onboarding", {
      method: "PATCH",
      headers: { ...headers, "Content-Type": "application/json" },
      body: JSON.stringify({ values: { photo: "anything" } }),
    });
    expect(patched.status).toBe(400);
  });

  it("shows the photo on forum posts", async () => {
    const headers = await signInAs(ava);
    const { photo } = await uploadedAvatar(headers);
    const response = await callAPI("/api/forums/coffee/posts", {
      method: "POST",
      headers: { ...headers, "Content-Type": "application/json" },
      body: JSON.stringify({
        title: "Espresso",
        startsAt: "2030-01-01T09:00:00Z",
      }),
    });
    const { post } = await response.json<{
      post: { author: { avatar: Avatar } };
    }>();
    expect(post.author.avatar.photo).toEqual(photo);
  });
});
