import { useSyncExternalStore } from "react";
import type { RequestRecord } from "@/api/client";

const limit = 200;

/** The most recent API requests, newest first. */
export class RequestLog {
  private records: readonly RequestRecord[] = [];
  private readonly listeners = new Set<() => void>();

  record = (record: RequestRecord): void => {
    const others = this.records.filter((existing) => existing.id !== record.id);
    this.records = [record, ...others]
      .sort((a, b) => b.id - a.id)
      .slice(0, limit);
    this.emit();
  };

  clear = (): void => {
    this.records = [];
    this.emit();
  };

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  snapshot = (): readonly RequestRecord[] => this.records;

  private emit() {
    for (const listener of this.listeners) listener();
  }
}

export function useRequestRecords(log: RequestLog): readonly RequestRecord[] {
  return useSyncExternalStore(log.subscribe, log.snapshot);
}
