import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { TypingState } from "@/api/types";
import { TypingSignal, typingIdleMs, typingRefreshMs } from "./typing-signal";

describe("TypingSignal", () => {
  let sent: TypingState[];
  let signal: TypingSignal;

  beforeEach(() => {
    vi.useFakeTimers();
    sent = [];
    signal = new TypingSignal((state) => sent.push(state));
  });

  afterEach(() => vi.useRealTimers());

  it("sends started once for a burst of keystrokes", () => {
    signal.draftChanged("h");
    signal.draftChanged("he");
    signal.draftChanged("hey");
    expect(sent).toEqual(["started"]);
  });

  it("repeats started while typing continues", () => {
    signal.draftChanged("h");
    vi.advanceTimersByTime(typingRefreshMs);
    signal.draftChanged("he");
    expect(sent).toEqual(["started", "started"]);
  });

  it("sends stopped after a pause with no new character", () => {
    signal.draftChanged("hey");
    vi.advanceTimersByTime(typingIdleMs - 1);
    expect(sent).toEqual(["started"]);
    vi.advanceTimersByTime(1);
    expect(sent).toEqual(["started", "stopped"]);
  });

  it("restarts the pause on every keystroke", () => {
    signal.draftChanged("h");
    vi.advanceTimersByTime(typingIdleMs - 1000);
    signal.draftChanged("he");
    vi.advanceTimersByTime(typingIdleMs - 1000);
    expect(sent).not.toContain("stopped");
  });

  it("sends stopped when the draft is cleared, and only once", () => {
    signal.draftChanged("hey");
    signal.draftChanged("");
    vi.advanceTimersByTime(typingIdleMs);
    signal.stop();
    expect(sent).toEqual(["started", "stopped"]);
  });

  it("sends nothing for whitespace", () => {
    signal.draftChanged("   ");
    expect(sent).toEqual([]);
  });
});
