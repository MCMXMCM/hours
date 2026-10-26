import { Book } from "lucide-react";
import "./guides.css";

/** A guide on its way: what is shown until it has been fetched and read. */
export function GuideOpening() {
  return (
    <div className="guide-status" role="status">
      <span className="spinner" />
      <p>Opening guide…</p>
    </div>
  );
}

export interface GuideUnavailableProps {
  /** Why the guide cannot be shown. */
  message: string;
  /**
   * Fetches the guide again. The native app reads its guides from its own
   * bundle and has no need of this; a page that reads them over a
   * connection has.
   */
  onRetry: () => void;
}

export function GuideUnavailable({ message, onRetry }: GuideUnavailableProps) {
  return (
    <div className="guide-status" role="alert">
      <Book aria-hidden="true" />
      <h1>Guide unavailable</h1>
      <p>{message}</p>
      <button type="button" onClick={onRetry}>
        Try Again
      </button>
    </div>
  );
}
