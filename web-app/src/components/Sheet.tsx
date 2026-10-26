import { Drawer } from "@base-ui/react/drawer";
import { X } from "lucide-react";
import { useRef, type ReactNode } from "react";

export interface SheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  /** Shown in place of the visible title, which is then kept for assistive technology. */
  hidesTitle?: boolean;
  /** How tall the sheet stands on a phone. */
  detent?: "medium" | "large";
  /** A control at the leading edge of the bar, opposite Close. */
  leading?: ReactNode;
  /**
   * Stands in the bar in place of the title, beside Close: a search field,
   * for one. The title is then kept for assistive technology.
   */
  header?: ReactNode;
  closeLabel?: string;
  /**
   * What takes the focus as the sheet opens, in place of the sheet itself: a
   * field that is the sheet's purpose, for one. It is asked as the sheet
   * opens, and `null` leaves the choice to the sheet.
   */
  initialFocus?: () => HTMLElement | null;
  children: ReactNode;
}

/**
 * A sheet, as the native app presents its secondary screens: rising from the
 * foot of a phone with a grabber, and standing as a page on a wide screen.
 * It can be dragged down, dismissed with Escape, or closed from its bar.
 */
export function Sheet({
  open,
  onOpenChange,
  title,
  hidesTitle = false,
  detent = "large",
  leading,
  header,
  closeLabel = "Close",
  initialFocus,
  children,
}: SheetProps) {
  const popup = useRef<HTMLDivElement>(null);
  return (
    <Drawer.Root open={open} onOpenChange={onOpenChange} swipeDirection="down">
      <Drawer.Portal>
        <Drawer.Backdrop className="sheet__backdrop" />
        <Drawer.Viewport className="sheet__viewport">
          <Drawer.Popup
            ref={popup}
            className={`sheet sheet--${detent}`}
            initialFocus={
              initialFocus ? () => initialFocus() ?? popup.current : undefined
            }
          >
            <div className="sheet__grabber" aria-hidden="true" />
            <header
              className={
                header ? "sheet__bar sheet__bar--custom" : "sheet__bar"
              }
            >
              {header ? (
                <div className="sheet__bar-header">{header}</div>
              ) : (
                <div className="sheet__bar-side">{leading}</div>
              )}
              <Drawer.Title
                className={
                  hidesTitle || header ? "sheet__title sr-only" : "sheet__title"
                }
              >
                {title}
              </Drawer.Title>
              <div className="sheet__bar-side sheet__bar-side--trailing">
                <Drawer.Close
                  className="icon-button sheet__close"
                  aria-label={closeLabel}
                >
                  <X aria-hidden="true" />
                </Drawer.Close>
              </div>
            </header>
            <Drawer.Content className="sheet__content">
              {children}
            </Drawer.Content>
          </Drawer.Popup>
        </Drawer.Viewport>
      </Drawer.Portal>
    </Drawer.Root>
  );
}
