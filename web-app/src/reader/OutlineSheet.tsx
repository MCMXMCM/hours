import { Sheet } from "@/components/Sheet.tsx";
import type { OfficeReaderOutlineEntry } from "./presentation/index.ts";

export interface OutlineSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  entries: readonly OfficeReaderOutlineEntry[];
  onSelect: (sectionID: string) => void;
}

/** The parts of the open office, each a place to jump to. */
export function OutlineSheet({
  open,
  onOpenChange,
  entries,
  onSelect,
}: OutlineSheetProps) {
  return (
    <Sheet
      open={open}
      onOpenChange={onOpenChange}
      title="Office sections"
      detent="medium"
      closeLabel="Close Office Sections"
    >
      <ul className="outline">
        {entries.map((entry) => (
          <li key={entry.id}>
            <button type="button" lang="la" onClick={() => onSelect(entry.id)}>
              {entry.title}
            </button>
          </li>
        ))}
      </ul>
    </Sheet>
  );
}
