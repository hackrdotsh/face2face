import { useCallback, useRef, useState } from "react";
import { errorMessage } from "@/api/errors";

export interface Activity {
  busy: boolean;
  error: string | null;
  /** Runs `action` unless another one is in flight. Resolves false when it failed or did not run. */
  run: (action: () => Promise<void>) => Promise<boolean>;
  clearError: () => void;
}

/** Tracks one in-flight action and its error message for a screen. */
export function useActivity(): Activity {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const running = useRef(false);

  const run = useCallback(async (action: () => Promise<void>) => {
    if (running.current) return false;
    running.current = true;
    setBusy(true);
    setError(null);
    try {
      await action();
      return true;
    } catch (caught) {
      setError(errorMessage(caught));
      return false;
    } finally {
      running.current = false;
      setBusy(false);
    }
  }, []);

  const clearError = useCallback(() => setError(null), []);
  return { busy, error, run, clearError };
}
