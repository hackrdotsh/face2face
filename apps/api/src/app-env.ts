import type { createAuth } from "./auth";

type Session = NonNullable<
  Awaited<ReturnType<ReturnType<typeof createAuth>["api"]["getSession"]>>
>;

export interface AppEnv {
  Bindings: Env;
  Variables: { user: Session["user"] };
}
