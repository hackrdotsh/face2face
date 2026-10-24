import { DurableObject } from "cloudflare:workers";

export class UserCoordinator extends DurableObject<Env> {
  async status() {
    const result = this.ctx.storage.sql
      .exec<{ ready: number }>("SELECT 1 AS ready")
      .one();
    return { ready: result.ready === 1, storage: "sqlite" };
  }
}
