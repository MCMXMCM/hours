import { reloadIntoUpdate, updateStore } from "@/app/offline.ts";
import { useStore } from "@/app/store.ts";

/** Says that a newer copy of the app is ready, and lets the reader take it. */
export function UpdatePrompt() {
  const { isWaiting } = useStore(updateStore);
  if (!isWaiting) return null;
  return (
    <div className="update-prompt" role="status">
      <span>A new version of Hours is ready.</span>
      <button type="button" onClick={() => void reloadIntoUpdate()}>
        Reload
      </button>
      <button
        type="button"
        className="update-prompt__later"
        aria-label="Later"
        onClick={() => updateStore.set({ isWaiting: false })}
      >
        Later
      </button>
    </div>
  );
}
