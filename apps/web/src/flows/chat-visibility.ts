import { useSyncExternalStore } from "react";

export function chatPageIsVisible(): boolean {
  return document.visibilityState === "visible" && document.hasFocus();
}

export function subscribeChatVisibility(changed: () => void) {
  document.addEventListener("visibilitychange", changed);
  window.addEventListener("focus", changed);
  window.addEventListener("blur", changed);
  return () => {
    document.removeEventListener("visibilitychange", changed);
    window.removeEventListener("focus", changed);
    window.removeEventListener("blur", changed);
  };
}

export function useChatPageIsVisible() {
  return useSyncExternalStore(
    subscribeChatVisibility,
    chatPageIsVisible,
    () => false,
  );
}
