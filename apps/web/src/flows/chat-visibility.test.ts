import { afterEach, expect, it, vi } from "vitest";
import { chatPageIsVisible, subscribeChatVisibility } from "./chat-visibility";

afterEach(() => vi.unstubAllGlobals());

it("only marks a chat read when its page is visible and focused, including return to the page", () => {
  let visibilityState = "visible";
  let focused = true;
  const document = Object.assign(new EventTarget(), {
    hasFocus: () => focused,
  });
  Object.defineProperty(document, "visibilityState", {
    get: () => visibilityState,
  });
  const window = new EventTarget();
  vi.stubGlobal("document", document);
  vi.stubGlobal("window", window);
  const states: boolean[] = [];
  const unsubscribe = subscribeChatVisibility(() =>
    states.push(chatPageIsVisible()),
  );
  expect(chatPageIsVisible()).toBe(true);
  visibilityState = "hidden";
  document.dispatchEvent(new Event("visibilitychange"));
  visibilityState = "visible";
  focused = false;
  window.dispatchEvent(new Event("blur"));
  focused = true;
  window.dispatchEvent(new Event("focus"));
  expect(states).toEqual([false, false, true]);
  unsubscribe();
  window.dispatchEvent(new Event("blur"));
  expect(states).toHaveLength(3);
});
