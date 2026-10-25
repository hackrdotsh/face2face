import { useCallback, useEffect, useState } from "react";
import { hrefFor, parseRoute, type Route } from "./routes";

/** The current page from the URL hash, so reload and the back button work. */
export function useHashRoute() {
  const [route, setRoute] = useState(() => parseRoute(window.location.hash));

  useEffect(() => {
    const update = () => setRoute(parseRoute(window.location.hash));
    window.addEventListener("hashchange", update);
    return () => window.removeEventListener("hashchange", update);
  }, []);

  const navigate = useCallback((next: Route) => {
    window.location.hash = hrefFor(next);
  }, []);

  return { route, navigate };
}
