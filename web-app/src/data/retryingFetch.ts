// Asking a server again for what it failed, for a moment, to give.
//
// The app reads only static files, and a store of static files now and then
// answers one request in many thousands with a 5xx that it would not give a
// moment later. A reader is not to be shown a failure for that, so what
// answers so is asked again, briefly.

export type Fetcher = (input: string, init?: RequestInit) => Promise<Response>;

export interface RetryOptions {
  /** How long to wait before each further asking, in milliseconds. */
  readonly delays?: readonly number[];
  readonly wait?: (milliseconds: number) => Promise<void>;
}

/** The answers that say only that the server could not answer just now. */
const passingFailures: ReadonlySet<number> = new Set([429, 500, 502, 503, 504]);

const defaultDelays: readonly number[] = [250, 1000];

function pause(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

/**
 * A fetcher that asks again when the answer is a passing failure, and
 * returns the last answer when its patience is spent. A request that fails
 * to be made at all (there is no connection) is not repeated: that failure
 * is the caller's to report at once.
 */
export function retrying(
  fetcher: Fetcher,
  options: RetryOptions = {},
): Fetcher {
  const delays = options.delays ?? defaultDelays;
  const wait = options.wait ?? pause;
  return async (input, init) => {
    for (let attempt = 0; ; attempt += 1) {
      const response = await fetcher(input, init);
      if (!passingFailures.has(response.status) || attempt >= delays.length) {
        return response;
      }
      // The unread answer is let go, that its connection may serve again.
      void response.body?.cancel().catch(() => undefined);
      await wait(delays[attempt]);
    }
  };
}

/** `fetch`, asking again as `retrying` does. */
export const retryingFetch: Fetcher = retrying((input, init) =>
  fetch(input, init),
);
