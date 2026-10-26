import { useSyncExternalStore } from "react";

/** A value that components may observe. Each change replaces the value. */
export class Store<State> {
  private state: State;
  private readonly listeners = new Set<() => void>();

  constructor(initial: State) {
    this.state = initial;
  }

  get value(): State {
    return this.state;
  }

  set(next: State): void {
    if (Object.is(next, this.state)) return;
    this.state = next;
    for (const listener of [...this.listeners]) listener();
  }

  update(change: Partial<State>): void {
    const keys = Object.keys(change) as Array<keyof State>;
    if (keys.every((key) => Object.is(change[key], this.state[key]))) return;
    this.set({ ...this.state, ...change });
  }

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = (): State => this.state;
}

export function useStore<State>(store: Store<State>): State {
  return useSyncExternalStore(
    store.subscribe,
    store.getSnapshot,
    store.getSnapshot,
  );
}
