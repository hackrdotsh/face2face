import type { TypingState } from "@/api/types";

/** How often `started` repeats while the person keeps typing. */
export const typingRefreshMs = 3000;
/** How long without a new character before the person counts as stopped. */
export const typingIdleMs = 5000;
/** How long the other person's `started` lasts without a refresh, in case `stopped` never arrives. */
export const theirTypingTimeoutMs = 8000;

/**
 * Decides when to tell the other person this person is typing. Each draft
 * change counts as a keystroke. `started` repeats while keystrokes continue,
 * and `stopped` goes out after a pause, on send, or when the draft is cleared.
 */
export class TypingSignal {
  private isTyping = false;
  private lastStartedAt = 0;
  private idleTimer: ReturnType<typeof setTimeout> | undefined;

  constructor(
    private readonly emit: (state: TypingState) => void,
    private readonly now: () => number = Date.now,
  ) {}

  draftChanged(draft: string) {
    if (!draft.trim()) return this.stop();
    const now = this.now();
    if (!this.isTyping || now - this.lastStartedAt >= typingRefreshMs) {
      this.isTyping = true;
      this.lastStartedAt = now;
      this.emit("started");
    }
    clearTimeout(this.idleTimer);
    this.idleTimer = setTimeout(() => this.stop(), typingIdleMs);
  }

  stop() {
    clearTimeout(this.idleTimer);
    if (!this.isTyping) return;
    this.isTyping = false;
    this.emit("stopped");
  }
}
