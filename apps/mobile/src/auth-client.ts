import { expoClient } from "@better-auth/expo/client";
import { createAuthClient } from "better-auth/react";
import * as SecureStore from "expo-secure-store";
import { apiURL } from "./api";

export const authClient = createAuthClient({
  baseURL: apiURL,
  plugins: [
    expoClient({
      scheme: "face2face",
      storagePrefix: "face2face",
      storage: SecureStore,
    }),
  ],
});
