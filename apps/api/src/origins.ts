export function webOrigins(env: Env) {
  return env.DEV_WEB_ORIGIN
    ? [...env.WEB_ORIGINS, env.DEV_WEB_ORIGIN]
    : env.WEB_ORIGINS;
}
