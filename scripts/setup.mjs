import { randomBytes } from "node:crypto";
import { writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const root = new URL("../", import.meta.url);
const path = new URL("apps/api/.dev.vars", root);

try {
  await writeFile(
    path,
    `BETTER_AUTH_SECRET=${randomBytes(32).toString("hex")}\n`,
    {
      flag: "wx",
      mode: 0o600,
    },
  );
  process.stdout.write(
    "Created the local auth secret in apps/api/.dev.vars.\n",
  );
} catch (error) {
  if (error instanceof Error && "code" in error && error.code === "EEXIST") {
    process.stdout.write("Kept the existing local auth secret.\n");
  } else {
    throw new Error(`Could not create ${fileURLToPath(path)}`, {
      cause: error,
    });
  }
}
